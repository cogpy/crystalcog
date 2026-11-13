require "spec"
require "file_utils"
require "random/secure"
require "../../src/atomspace/distributed_storage"

# Two cluster nodes in one process, each with its own AtomSpace and storage.
private class TwoNodes
  getter first : AtomSpace::DistributedStorageNode
  getter second : AtomSpace::DistributedStorageNode
  getter clusters : Array(AtomSpace::DistributedAtomSpaceCluster)
  getter path : String

  def initialize(partition : AtomSpace::PartitionStrategy, replication : AtomSpace::ReplicationStrategy)
    @path = File.join(Dir.tempdir, "crystalcog_two_nodes_#{Random::Secure.hex(4)}")
    @clusters = (0...2).map do
      AtomSpace::DistributedAtomSpaceCluster.new(cluster_id: "two_nodes", local_atomspace: AtomSpace::AtomSpace.new,
        host: "127.0.0.1", adaptive_heartbeat_enabled: false)
    end
    @clusters.each(&.start)
    sleep 100.milliseconds
    seed = @clusters[0].local_node
    @clusters[1].join_cluster(seed.host, seed.port).should be_true
    sleep 100.milliseconds
    @clusters.each(&.cluster_nodes.size.should(eq(2)))

    storages = @clusters.map_with_index do |cluster, i|
      AtomSpace::DistributedStorageNode.new("node#{i}", cluster, storage_path: @path,
        partition_strategy: partition, replication_strategy: replication, replication_factor: 2)
    end
    storages.each(&.open.should(be_true))
    @first, @second = storages[0], storages[1]
  end

  def local_atoms(storage) : Int64
    storage.get_stats["local_atoms"].as(Int).to_i64
  end

  def total_atoms : Int64
    local_atoms(@first) + local_atoms(@second)
  end

  # Cluster messages are delivered by fibers over real sockets, so the
  # nodes agree a little after a call returns. Wait until the block holds
  # (the assertions that follow still decide the outcome).
  def settle(limit : Time::Span = 10.seconds, &) : Nil
    deadline = Time.monotonic + limit
    until yield
      break if Time.monotonic > deadline
      sleep 20.milliseconds
    end
  end

  def close
    [@first, @second].each(&.close)
    @clusters.each(&.stop)
    FileUtils.rm_rf(@path)
  end
end

private def two_nodes(partition, replication, &)
  nodes = TwoNodes.new(partition, replication)
  begin
    yield nodes
  ensure
    nodes.close
  end
end

private def sample_graph : {AtomSpace::AtomSpace, Array(AtomSpace::Atom)}
  space = AtomSpace::AtomSpace.new
  animal = space.add_concept_node("animal", AtomSpace::SimpleTruthValue.new(0.9, 0.7))
  20.times do |i|
    creature = space.add_concept_node("creature-#{i}")
    space.add_inheritance_link(creature, animal, AtomSpace::SimpleTruthValue.new(0.5 + i / 100.0, 0.6))
  end
  {space, space.get_all_atoms}
end

describe "AtomWire content addresses" do
  it "are the same for equal content and differ otherwise" do
    a = AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "cat")
    b = AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "cat", AtomSpace::SimpleTruthValue.new(0.1, 0.1))
    c = AtomSpace::Node.new(AtomSpace::AtomType::PREDICATE_NODE, "cat")
    a.handle.should_not eq(b.handle)
    AtomSpace::AtomWire.address(a).should eq(AtomSpace::AtomWire.address(b))
    AtomSpace::AtomWire.address(a).should_not eq(AtomSpace::AtomWire.address(c))

    ab = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [a, c] of AtomSpace::Atom)
    ba = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [c, a] of AtomSpace::Atom)
    again = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [b, c] of AtomSpace::Atom)
    AtomSpace::AtomWire.address(ab).should eq(AtomSpace::AtomWire.address(again))
    AtomSpace::AtomWire.address(ab).should_not eq(AtomSpace::AtomWire.address(ba))
    # Fixed by the content alone, not by anything in this process.
    AtomSpace::AtomWire.address(a).should eq("bbbf60bb403ac6eac728968eeb65fbcf")
    AtomSpace::AtomWire.ring_position("node").should eq(6079478208108954607_u64)
  end
end

describe "DistributedStorageNode across two nodes" do
  it "partitions atoms so each lives on exactly one node and is reachable from both" do
    two_nodes(AtomSpace::PartitionStrategy::HashBased, AtomSpace::ReplicationStrategy::SingleCopy) do |nodes|
      _, atoms = sample_graph
      atoms.each { |atom| nodes.first.store_atom(atom).should be_true }
      nodes.settle { nodes.total_atoms == atoms.size }

      nodes.total_atoms.should eq(atoms.size)
      atoms.each do |atom|
        fetched = nodes.first.fetch_atom(atom.handle).not_nil!
        fetched.to_s.should eq(atom.to_s)
        fetched.truth_value.strength.should eq(atom.truth_value.strength)
        # The second node never saw these handles; it finds the atoms by content.
        nodes.second.fetch_atom_by_content(atom).not_nil!.to_s.should eq(atom.to_s)
      end
    end
  end

  it "replicates to the backup node and removes from both" do
    two_nodes(AtomSpace::PartitionStrategy::HashBased, AtomSpace::ReplicationStrategy::PrimaryBackup) do |nodes|
      _, atoms = sample_graph
      atoms.each { |atom| nodes.first.store_atom(atom).should be_true }
      nodes.settle { nodes.local_atoms(nodes.first) == atoms.size && nodes.local_atoms(nodes.second) == atoms.size }
      nodes.local_atoms(nodes.first).should eq(atoms.size)
      nodes.local_atoms(nodes.second).should eq(atoms.size)

      # A copy of the whole graph can be rebuilt from the second node alone.
      copy = AtomSpace::AtomSpace.new
      AtomSpace::FileStorageNode.new("reader", File.join(nodes.path, "#{nodes.clusters[1].node_id}.scm")).tap do |file|
        file.open.should be_true
        file.load_atomspace(copy).should be_true
      end
      copy.get_all_atoms.map(&.to_s).sort.should eq(atoms.map(&.to_s).sort)

      link = atoms.find!(&.link?)
      nodes.first.remove_atom(link).should be_true
      nodes.settle { nodes.total_atoms == 2 * (atoms.size - 1) }
      nodes.local_atoms(nodes.first).should eq(atoms.size - 1)
      nodes.local_atoms(nodes.second).should eq(atoms.size - 1)
      nodes.second.fetch_atom_by_content(link).should be_nil
    end
  end

  it "keeps all atoms of a type together and moves real data when rebalancing" do
    two_nodes(AtomSpace::PartitionStrategy::TypeBased, AtomSpace::ReplicationStrategy::SingleCopy) do |nodes|
      space = AtomSpace::AtomSpace.new
      atoms = (0...20).map { |i| space.add_concept_node("concept-#{i}", AtomSpace::SimpleTruthValue.new(0.3, 0.9)) }
      atoms.each { |atom| nodes.first.store_atom(atom).should be_true }
      nodes.settle { nodes.total_atoms == 20 }

      counts = [nodes.local_atoms(nodes.first), nodes.local_atoms(nodes.second)]
      counts.sort.should eq([0, 20])

      nodes.first.rebalance_cluster.should be_true
      nodes.settle { nodes.local_atoms(nodes.first) == 10 && nodes.local_atoms(nodes.second) == 10 }
      nodes.local_atoms(nodes.first).should eq(10)
      nodes.local_atoms(nodes.second).should eq(10)
      nodes.first.distribution_metrics["balance_score"].as_f.should eq(1.0)

      atoms.each do |atom|
        nodes.first.fetch_atom(atom.handle).not_nil!.to_s.should eq(atom.to_s)
        nodes.second.fetch_atom_by_content(atom).not_nil!.truth_value.confidence.should eq(0.9)
      end
    end
  end

  it "loads the atoms other nodes hold into an AtomSpace, links included" do
    two_nodes(AtomSpace::PartitionStrategy::HashBased, AtomSpace::ReplicationStrategy::SingleCopy) do |nodes|
      _, atoms = sample_graph
      atoms.each { |atom| nodes.first.store_atom(atom).should be_true }
      nodes.settle { nodes.total_atoms == atoms.size }

      loaded = AtomSpace::AtomSpace.new
      nodes.second.load_atomspace(loaded).should be_true
      loaded.get_all_atoms.map(&.to_s).sort.should eq(atoms.map(&.to_s).sort)
      animal = loaded.get_nodes_by_name("animal").first
      loaded.get_incoming(animal).size.should eq(20)
    end
  end
end

describe "Atom#incoming" do
  it "lists the links that use an atom in its AtomSpace" do
    space = AtomSpace::AtomSpace.new
    cat = space.add_concept_node("cat")
    animal = space.add_concept_node("animal")
    detached = AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "loose")
    detached.incoming.should be_empty
    detached.atomspace.should be_nil
    cat.atomspace.should be(space)
    cat.incoming.should be_empty

    link = space.add_inheritance_link(cat, animal)
    list = space.add_list_link([cat, cat] of AtomSpace::Atom)
    cat.incoming.map(&.handle).sort.should eq([link.handle, list.handle].sort)
    animal.incoming.should eq([link])
    link.incoming.should be_empty

    space.remove_atom(link).should be_true
    link.atomspace.should be_nil
    animal.incoming.should be_empty
    space.clear
    cat.atomspace.should be_nil
    cat.incoming.should be_empty
  end
end
