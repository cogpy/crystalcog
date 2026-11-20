require "spec"
require "socket"
require "../../src/atomspace/distributed_storage"

private def snap_node(path : String? = nil) : AtomSpace::DistributedAtomSpaceCluster
  node = AtomSpace::DistributedAtomSpaceCluster.new(cluster_id: "snapshots", local_atomspace: AtomSpace::AtomSpace.new,
    host: "127.0.0.1", adaptive_heartbeat_enabled: false, state_path: path)
  node.vote_timeout = 500.milliseconds
  node.replication_timeout = 500.milliseconds
  node
end

private def with_state_files(count : Int32, &)
  paths = Array.new(count) { File.tempname("cluster-snapshot", ".journal") }
  begin
    yield paths
  ensure
    paths.each do |path|
      File.delete(path) if File.exists?(path)
      File.delete("#{path}.tmp") if File.exists?("#{path}.tmp")
    end
  end
end

private def settle(limit : Time::Span = 10.seconds, &) : Nil
  deadline = Time.monotonic + limit
  until yield
    break if Time.monotonic > deadline
    sleep 20.milliseconds
  end
end

private def started(node)
  node.start
  sleep 100.milliseconds
  node
end

private def join(node, seed) : Nil
  node.join_cluster(seed.local_node.host, seed.local_node.port).should be_true
end

private def ask_node(node, message) : JSON::Any
  socket = TCPSocket.new(node.local_node.host, node.local_node.port)
  begin
    socket.read_timeout = 5.seconds
    socket.puts(message.to_json)
    JSON.parse(socket.gets.not_nil!)
  ensure
    socket.close
  end
end

private def entry(term : Int32, text : String)
  {"term" => term, "kind" => "command", "data" => text}
end

private def append(node, term : Int32, prev_index : Int32, prev_term : Int32, entries, commit : Int32) : JSON::Any
  ask_node(node, {"type" => "log_append", "term" => term, "leader_id" => "a-leader", "prev_index" => prev_index,
                  "prev_term" => prev_term, "entries" => entries, "commit" => commit})
end

# A tiny application: the commands it has seen, rebuilt from snapshots.
private class Tally
  getter seen = [] of String
  getter restores = [] of {UInt64, JSON::Any}

  def initialize(node)
    node.on_commit { |_, command| @seen << command.as_s }
    node.on_restore do |index, state|
      @restores << {index, state}
      @seen = state.as_a.map(&.as_s)
    end
  end

  def state
    @seen
  end
end

private def concept(name : String) : AtomSpace::Atom
  AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, name).as(AtomSpace::Atom)
end

describe "DistributedAtomSpaceCluster snapshots" do
  it "cuts the log short behind what is applied" do
    node = started(snap_node)
    begin
      tally = Tally.new(node)
      node.compact(tally.state).should be_nil # nothing applied yet
      node.start_election.should be_true
      %w(a b c).each { |command| node.propose(command).should_not be_nil }
      node.log_size.should eq(4)

      node.compact(tally.state).should eq(4)
      node.snapshot_index.should eq(4)
      node.log_size.should eq(4)
      node.log_terms.should be_empty
      node.committed.should be_empty
      node.cluster_stats["snapshot_index"].as_i64.should eq(4)
      node.compact(tally.state).should be_nil # nothing new to cover

      node.propose("d").should eq(5)
      node.log_terms.should eq([1])
      node.committed.map(&.as_s).should eq(["d"])
      tally.seen.should eq(["a", "b", "c", "d"])
    ensure
      node.stop
    end
  end

  it "brings a member that joins later up to date from the snapshot" do
    leader = started(snap_node)
    late = snap_node
    begin
      leader.start_election.should be_true
      leader_tally = Tally.new(leader)
      %w(a b).each { |command| leader.propose(command).should_not be_nil }
      leader.add_atom_in_order(AtomSpace::InheritanceLink.new(concept("dog"), concept("animal"),
        AtomSpace::SimpleTruthValue.new(0.8, 0.7))).should_not be_nil
      leader.compact(leader_tally.state).should eq(4)
      leader.propose("c").should eq(5)

      late_tally = Tally.new(late)
      started(late)
      join(late, leader)
      settle { leader.cluster_nodes.size == 2 }
      leader.replicate.should eq(1)

      # The state as of entry 4, then what came after.
      late_tally.restores.should eq([{4_u64, JSON.parse(%(["a","b"]))}])
      late_tally.seen.should eq(["a", "b", "c"])
      late.snapshot_index.should eq(4)
      late.log_size.should eq(5)
      late.commit_index.should eq(5)
      # And the atom placed before the snapshot, with its truth value.
      links = late.local_atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
      links.size.should eq(1)
      links.first.truth_value.strength.should be_close(0.8, 1e-9)
      links.first.truth_value.confidence.should be_close(0.7, 1e-9)

      leader.propose("d").should eq(6)
      settle { late.last_applied == 6 }
      late_tally.seen.should eq(["a", "b", "c", "d"])
    ensure
      leader.stop
      late.stop
    end
  end

  it "sends the snapshot to a member that came back after the log was cut" do
    with_state_files(3) do |paths|
      nodes = paths.map { |path| started(snap_node(path)) }
      begin
        nodes[1..].each { |node| join(node, nodes[0]) }
        everyone = nodes.map(&.node_id).sort
        settle { nodes.all? { |node| node.cluster_nodes.map(&.id).sort == everyone } }
        nodes[0].start_election.should be_true
        tallies = nodes.map { |node| Tally.new(node) }
        nodes[0].propose("a").should eq(2)
        settle { nodes[2].last_applied == 2 }

        # The third member goes away; the others carry on and cut their logs.
        nodes[2].stop
        settle { nodes[0].cluster_nodes.size == 2 }
        %w(b c).each { |command| nodes[0].propose(command).should_not be_nil }
        nodes[0].compact(tallies[0].state).should eq(4)

        back = snap_node(paths[2])
        back.log_size.should eq(2)
        back_tally = Tally.new(back)
        nodes[2] = started(back)
        join(back, nodes[0])
        settle { nodes[0].cluster_nodes.size == 3 }
        nodes[0].replicate.should eq(2)
        # Its own log ended at entry 2, which the snapshot covers.
        back.snapshot_index.should eq(4)
        back_tally.restores.map(&.[0]).should eq([4_u64])
        back_tally.seen.should eq(["a", "b", "c"])

        nodes[0].propose("d").should eq(5)
        settle { nodes.all? { |node| node.last_applied == 5 } }
        back_tally.seen.should eq(["a", "b", "c", "d"])
      ensure
        nodes.each(&.stop)
      end
    end
  end

  it "starts again from a kept snapshot" do
    with_state_files(1) do |paths|
      node = started(snap_node(paths[0]))
      tally = Tally.new(node)
      node.start_election.should be_true
      %w(a b).each { |command| node.propose(command).should_not be_nil }
      node.add_atom_in_order(concept("dog")).should_not be_nil
      node.compact(tally.state).should eq(4)
      node.propose("c").should eq(5)
      node.stop

      back = snap_node(paths[0])
      back_tally = Tally.new(back)
      back.snapshot_index.should eq(4)
      back.log_terms.should eq([1])
      back.commit_index.should eq(4)
      started(back)
      begin
        # Restored at start, before anything after the snapshot.
        back_tally.restores.should eq([{4_u64, JSON.parse(%(["a","b"]))}])
        back.local_atomspace.get_nodes_by_name("dog").size.should eq(1)
        back.start_election.should be_true
        back_tally.seen.should eq(["a", "b", "c"])
        back.committed.map(&.as_s).should eq(["c"])
      ensure
        back.stop
      end

      # The journal holds the snapshot in place of the entries it covers.
      lines = File.read_lines(paths[0]).map { |line| JSON.parse(line) }
      lines.count { |line| line.as_h.has_key?("snapshot") }.should eq(1)
      lines.find! { |line| line.as_h.has_key?("snapshot") }["snapshot"]["index"].as_i64.should eq(4)
      AtomSpace::DistributedAtomSpaceCluster.read_state(paths[0]).log.map(&.term).should eq([1, 2])
    end
  end

  it "passes over entries its own snapshot covers, and cuts back after it" do
    with_state_files(1) do |paths|
      node = started(snap_node(paths[0]))
      begin
        tally = Tally.new(node)
        append(node, 1, 0, 0, [entry(1, "one"), entry(1, "two"), entry(1, "three")], 3)
        tally.seen.should eq(["one", "two", "three"])
        node.compact(tally.state).should eq(3)

        # A leader that does not know of the snapshot sends from the start.
        answer = append(node, 1, 0, 0, [entry(1, "one"), entry(1, "two"), entry(1, "three"), entry(1, "four")], 4)
        answer["success"].as_bool.should be_true
        answer["have"].as_i64.should eq(4)
        tally.seen.should eq(["one", "two", "three", "four"])

        # An entry after the snapshot that another leader replaces.
        append(node, 1, 4, 1, [entry(1, "lost")], 4)
        append(node, 2, 4, 1, [entry(2, "five")], 5)["success"].as_bool.should be_true
        node.log_terms.should eq([1, 2])
        tally.seen.should eq(["one", "two", "three", "four", "five"])
        node.stop

        kept = AtomSpace::DistributedAtomSpaceCluster.read_state(paths[0])
        kept.snapshot.not_nil!.index.should eq(3)
        kept.log.map(&.data.as_s).should eq(["four", "five"])
      ensure
        node.stop
      end
    end
  end

  it "takes a snapshot from a leader only when it is newer" do
    node = started(snap_node)
    begin
      tally = Tally.new(node)
      append(node, 1, 0, 0, [entry(1, "one"), entry(1, "two")], 2)
      node.compact(tally.state).should eq(2)
      older = ask_node(node, {"type" => "log_snapshot", "term" => 1, "leader_id" => "a-leader",
                              "last_index" => 1, "last_term" => 1, "data" => ["one"], "atoms" => [] of String})
      older["success"].as_bool.should be_true
      node.snapshot_index.should eq(2)
      tally.restores.should be_empty

      newer = ask_node(node, {"type" => "log_snapshot", "term" => 2, "leader_id" => "a-leader",
                              "last_index" => 9, "last_term" => 2, "data" => %w(one two three), "atoms" => [] of String})
      newer["have"].as_i64.should eq(9)
      node.snapshot_index.should eq(9)
      node.commit_index.should eq(9)
      node.last_applied.should eq(9)
      tally.restores.map(&.[0]).should eq([9_u64])
      tally.seen.should eq(["one", "two", "three"])
      # A leader of an older term is refused.
      ask_node(node, {"type" => "log_snapshot", "term" => 1, "leader_id" => "old", "last_index" => 20,
                      "last_term" => 1, "data" => nil, "atoms" => [] of String})["success"].as_bool.should be_false
    ensure
      node.stop
    end
  end
end
