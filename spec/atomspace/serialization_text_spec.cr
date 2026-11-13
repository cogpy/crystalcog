require "spec"
require "../../src/opencog/opencog"

describe AtomSpace::Serialization do
  it "round-trips nodes and links of any type with their truth values" do
    space = AtomSpace::AtomSpace.new
    tom = space.add_concept_node(%(my cat "Tom"\\ the 1st), AtomSpace::SimpleTruthValue.new(0.9, 0.8))
    animal = space.add_concept_node("animal")
    inherits = space.add_inheritance_link(tom, animal, AtomSpace::SimpleTruthValue.new(0.7, 0.6))
    space.add_list_link([inherits, tom] of AtomSpace::Atom)
    space.add_evaluation_link(space.add_predicate_node("likes"), space.add_list_link([tom, animal] of AtomSpace::Atom),
      AtomSpace::CountTruthValue.new(0.5, 0.4, 12.0))
    space.add_node(AtomSpace::AtomType::NUMBER_NODE, "3.5")
    space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$X")
    space.add_concept_node("multi\nline")

    text = AtomSpace::Serialization.to_text(space)
    text.should contain(%((CONCEPTNODE "my cat \\"Tom\\"\\\\ the 1st") (0.9, 0.8)))
    text.lines.size.should eq(space.size)

    copy = AtomSpace::AtomSpace.new
    AtomSpace::Serialization.from_text(copy, "# exported\n\n" + text).should eq(space.size)
    copy.size.should eq(space.size)
    AtomSpace::Serialization.to_text(copy).lines.sort.should eq(text.lines.sort)

    copied_link = copy.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).first
    copied_link.truth_value.strength.should eq(0.7)
    copied_link.outgoing[0].name.should eq(%(my cat "Tom"\\ the 1st))
    copied_link.outgoing[0].truth_value.confidence.should eq(0.8)
    evaluation = copy.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).first
    evaluation.truth_value.should be_a(AtomSpace::CountTruthValue)
    copy.get_nodes_by_name("multi\nline").size.should eq(1)
  end

  it "reads the older unescaped node lines and reports malformed ones" do
    space = AtomSpace::AtomSpace.new
    AtomSpace::Serialization.from_text(space, %((ConceptNode "dog") (0.8, 0.9)\n(PREDICATENODE "barks") (1.0, 0.0))).should eq(2)
    space.get_nodes_by_name("dog").first.truth_value.strength.should eq(0.8)

    expect_raises(AtomSpace::Serialization::ParseError, /line 2: unknown atom type "WIBBLENODE"/) do
      AtomSpace::Serialization.from_text(space, %((CONCEPTNODE "ok") (1.0, 0.0)\n(WIBBLENODE "x") (1.0, 0.0)))
    end
    expect_raises(AtomSpace::Serialization::ParseError, /line 1: unterminated/) do
      AtomSpace::Serialization.from_text(space, "(LISTLINK (CONCEPTNODE \"a\")")
    end
  end
end

describe OpenCog::PatternMatcher do
  it "binds variables instead of only finding equal atoms" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("animal")
    cat = space.add_concept_node("cat")
    dog = space.add_concept_node("dog")
    space.add_inheritance_link(cat, animal)
    space.add_inheritance_link(dog, animal)
    space.add_inheritance_link(animal, space.add_concept_node("thing"))

    pattern = AtomSpace::InheritanceLink.new(AtomSpace::VariableNode.new("$X"), animal)
    bindings = OpenCog::PatternMatcher.match(space, pattern)
    bindings.map(&.["$X"].name).sort.should eq(["cat", "dog"])

    OpenCog::PatternMatcher.match(space, AtomSpace::InheritanceLink.new(cat, animal)).size.should eq(1)
    OpenCog::PatternMatcher.match(space, AtomSpace::InheritanceLink.new(cat, dog)).should be_empty
  end
end
