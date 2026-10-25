require "spec"
require "../../src/opencog/opencog"

describe OpenCog::Query do
  it "binds variables in query_pattern" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("Animal")
    space.add_inheritance_link(space.add_concept_node("Dog"), animal)
    space.add_inheritance_link(space.add_concept_node("Rock"), space.add_concept_node("Mineral"))
    x = space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")

    results = OpenCog::Query.query_pattern(space, AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [x, animal]))
    results.map { |r| r.bindings["x"].name }.should eq(["Dog"])
  end

  it "joins conjunctions on shared variables" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("Animal")
    pet = space.add_concept_node("Pet")
    dog = space.add_concept_node("Dog")
    space.add_inheritance_link(dog, animal)
    space.add_inheritance_link(space.add_concept_node("Wolf"), animal)
    space.add_inheritance_link(dog, pet)
    x = space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")

    results = OpenCog::Query.query_conjunction(space, [
      AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [x, animal]).as(AtomSpace::Atom),
      AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [x, pet]).as(AtomSpace::Atom),
    ])
    results.map { |r| r.bindings["x"].name }.should eq(["Dog"])
  end
end
