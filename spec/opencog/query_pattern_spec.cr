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

  it "uses the pattern's detached variable for type constraints" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("Animal")
    space.add_inheritance_link(space.add_concept_node("Dog"), animal)
    space.add_inheritance_link(space.add_predicate_node("Runs"), animal)
    x = AtomSpace::VariableNode.new("$x")
    pattern = AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [x, animal])

    results = OpenCog::Query.query_pattern(space, pattern,
      [OpenCog::Query::Variable.new("x", AtomSpace::AtomType::CONCEPT_NODE)])
    results.map { |r| r.bindings["x"].name }.should eq(["Dog"])
  end

  it "matches a detached concrete node by content" do
    space = AtomSpace::AtomSpace.new
    cat = space.add_concept_node("cat")
    detached = AtomSpace::ConceptNode.new("cat")

    OpenCog::PatternMatcher.match(space, detached).should eq([{} of String => AtomSpace::Atom])
    OpenCog::PatternMatcher.match(space, AtomSpace::ConceptNode.new("dog")).should be_empty
    cat.should_not be(detached)
  end
end
