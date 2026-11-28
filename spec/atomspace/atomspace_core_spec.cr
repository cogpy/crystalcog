require "spec"
require "../../src/atomspace/atomspace_core"

# Direct coverage for src/atomspace/atomspace_core.cr, the lightweight entry
# point that loads the in-memory graph without persistence or cluster code.
describe "AtomSpace core entry point (atomspace_core.cr)" do
  it "provides a working in-memory AtomSpace on its own" do
    space = AtomSpace::AtomSpace.new
    dog = space.add_concept_node("dog")
    animal = space.add_concept_node("animal")
    link = space.add_inheritance_link(dog, animal, AtomSpace::SimpleTruthValue.new(0.9, 0.8))

    space.size.should eq(3)
    space.get_nodes_by_name("dog").first.should eq(dog)
    space.get_atom(link.handle).should eq(link)
    link.truth_value.strength.should eq(0.9)
    space.get_incoming(dog).map(&.handle).should eq([link.handle])
    space.remove_atom(link).should be_true
    space.size.should eq(2)
  end

  it "exposes truth values and atom types" do
    AtomSpace::SimpleTruthValue.new(0.5, 0.25).confidence.should eq(0.25)
    AtomSpace::AtomSpace.new.add_predicate_node("likes").type.should eq(AtomSpace::AtomType::PREDICATE_NODE)
  end

  # The examples above share the whole suite's requires, so they cannot see a
  # graph method that silently depends on atomspace_main. This probe compiles
  # and runs a program that requires only atomspace_core.
  it "builds and runs the graph API without persistence or cluster code" do
    probe = File.join(__DIR__, "core_probe_#{Process.pid}.cr")
    File.write(probe, <<-CR)
      require "../../src/atomspace/atomspace_core"
      {% for name in [:DistributedAtomSpaceCluster, :DistributedStorageNode, :FileStorageNode] %}
        {% if AtomSpace.has_constant?(name) %}
          {% raise "atomspace_core must not load " + name.stringify %}
        {% end %}
      {% end %}
      space = AtomSpace::AtomSpace.new
      dog = space.add_concept_node("dog")
      animal = space.add_concept_node("animal")
      likes = space.add_predicate_node("likes")
      link = space.add_inheritance_link(dog, animal, AtomSpace::SimpleTruthValue.new(0.9, 0.8))
      checks = {
        "size"     => space.size == 4,
        "by_name"  => space.get_nodes_by_name("dog") == [dog],
        "get_atom" => space.get_atom(link.handle) == link,
        "tv"       => link.truth_value.strength == 0.9 && link.truth_value.confidence == 0.8,
        "incoming" => space.get_incoming(dog).map(&.handle) == [link.handle],
        "type"     => likes.type == AtomSpace::AtomType::PREDICATE_NODE,
        "remove"   => space.remove_atom(link) && space.size == 3,
      }
      failed = checks.reject { |_, ok| ok }.keys
      abort "failed: \#{failed.join(", ")}" unless failed.empty?
      puts "core probe ok"
      CR
    begin
      output = IO::Memory.new
      status = Process.run("crystal", ["run", probe], output: output, error: output)
      status.success?.should be_true, output.to_s
      output.to_s.should contain("core probe ok")
    ensure
      File.delete?(probe)
    end
  end
end
