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

  it "does not load persistence or cluster code" do
    probe = File.join(__DIR__, "core_probe_#{Process.pid}.cr")
    File.write(probe, <<-CR)
      require "../../src/atomspace/atomspace_core"
      {% for name in [:DistributedAtomSpaceCluster, :DistributedStorageNode, :FileStorageNode] %}
        {% if AtomSpace.has_constant?(name) %}
          {% raise "atomspace_core must not load " + name.stringify %}
        {% end %}
      {% end %}
      CR
    begin
      output = IO::Memory.new
      status = Process.run("crystal", ["build", "--no-codegen", probe], output: output, error: output)
      status.success?.should be_true, output.to_s
    ensure
      File.delete?(probe)
    end
  end
end
