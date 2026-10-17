require "spec"
require "../../src/atomspace/atomspace_main"

describe "AtomSpace canonical link reuse" do
  it "does not allocate discarded atom handles for duplicate proposals" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("reuse-a")
    b = space.add_concept_node("reuse-b")
    first = space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, b])
    before = AtomSpace::ConceptNode.new("handle-probe-before").handle
    100.times do
      space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, b]).same?(first).should be_true
    end
    after = AtomSpace::ConceptNode.new("handle-probe-after").handle
    (after - before).should eq(1)
    space.size.should eq(3)
    space.get_incoming(a).map(&.handle).should eq([first.handle])
  end

  it "merges truth values exactly as add_atom and dispatches after unlocking" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("merge-a")
    b = space.add_concept_node("merge-b")
    original = AtomSpace::CountTruthValue.new(0.8, 0.6, 4.0)
    proposal = AtomSpace::CountTruthValue.new(0.5, 0.9, 7.0)
    canonical = space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, b], original)
    expected = original.merge(proposal)
    notifications = [] of AtomSpace::AtomSpaceEvent
    space.add_observer(->(event : AtomSpace::AtomSpaceEvent, atom : AtomSpace::Atom) {
      space.get_atom(atom.handle).should_not be_nil
      notifications << event
      nil
    })
    actual = space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, b], proposal)
    actual.same?(canonical).should be_true
    actual.truth_value.should eq(expected)
    actual.truth_value.count.should eq(expected.count)
    notifications.should eq([AtomSpace::AtomSpaceEvent::TRUTH_VALUE_CHANGED])
  end

  it "keeps relationship type and outgoing order in the canonical key" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("order-a")
    b = space.add_concept_node("order-b")
    forward = space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, b])
    reverse = space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [b, a])
    implication = space.add_link(AtomSpace::AtomType::IMPLICATION_LINK, [a, b])
    [forward.handle, reverse.handle, implication.handle].to_set.size.should eq(3)
    space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [b, a]).same?(reverse).should be_true
  end
end
