require "spec"
require "../../src/pattern_matching/pattern_matching"

describe "PatternMatching constraint substitution" do
  it "PresentConstraint sees links rebuilt from bound variables" do
    space = AtomSpace::AtomSpace.new
    dog = space.add_concept_node("Dog")
    animal = space.add_concept_node("Animal")
    space.add_inheritance_link(dog, animal)
    x = space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
    pattern_link = AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [x, animal])

    present = PatternMatching::PresentConstraint.new(pattern_link)
    absent = PatternMatching::AbsentConstraint.new(pattern_link)
    bound = PatternMatching::VariableBinding{x => dog.as(AtomSpace::Atom)}
    unbound_cat = PatternMatching::VariableBinding{x => space.add_concept_node("Cat").as(AtomSpace::Atom)}

    present.satisfied?(bound, space).should be_true
    absent.satisfied?(bound, space).should be_false
    present.satisfied?(unbound_cat, space).should be_false
    absent.satisfied?(unbound_cat, space).should be_true
  end

  it "EqualityConstraint compares substituted nested links" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("A")
    b = space.add_concept_node("B")
    x = space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
    left = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [x, b])
    right = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [a, b])
    eq = PatternMatching::EqualityConstraint.new(left, right)

    eq.satisfied?(PatternMatching::VariableBinding{x => a.as(AtomSpace::Atom)}, space).should be_true
    eq.satisfied?(PatternMatching::VariableBinding{x => b.as(AtomSpace::Atom)}, space).should be_false
  end
end

describe AtomSpace::AtomSpace do
  it "finds content-equivalent atoms through nested fresh links" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("A")
    b = space.add_concept_node("B")
    inner = space.add_link(AtomSpace::AtomType::LIST_LINK, [a, b])
    outer = space.add_link(AtomSpace::AtomType::LIST_LINK, [inner, a])

    fresh_inner = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [AtomSpace::ConceptNode.new("A"), b])
    fresh_outer = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [fresh_inner, a])

    space.contains?(fresh_outer).should be_false # handle identity only
    space.find_equivalent(fresh_outer).should_not be_nil
    space.find_equivalent(fresh_outer).not_nil!.handle.should eq(outer.handle)
    space.find_equivalent(AtomSpace::Link.new(AtomSpace::AtomType::SET_LINK, [a, b])).should be_nil
  end
end
