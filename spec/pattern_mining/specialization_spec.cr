require "spec"
require "../../src/pattern_mining/pattern_mining"

private def zoo : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  animal = space.add_concept_node("animal")
  %w(dog cat cow).each { |name| space.add_inheritance_link(space.add_concept_node(name), animal) }
  space.add_inheritance_link(space.add_concept_node("rose"), space.add_concept_node("plant"))
  likes = space.add_predicate_node("likes")
  dog = space.add_concept_node("dog")
  %w(bone ball).each do |name|
    space.add_evaluation_link(likes, space.add_list_link([dog, space.add_concept_node(name)] of AtomSpace::Atom))
  end
  space.add_evaluation_link(space.add_predicate_node("fears"),
    space.add_list_link([space.add_concept_node("cat"), dog] of AtomSpace::Atom))
  space
end

private def variable(name : String) : AtomSpace::Atom
  AtomSpace::VariableNode.new(name).as(AtomSpace::Atom)
end

private def link(type : AtomSpace::AtomType, *children : AtomSpace::Atom) : AtomSpace::Atom
  AtomSpace::Link.new(type, children.to_a.map(&.as(AtomSpace::Atom))).as(AtomSpace::Atom)
end

describe PatternMining::PatternSpecializer do
  it "abstracts a variable to link shapes, constants and other variables" do
    space = zoo
    space.add_inheritance_link(space.add_concept_node("thing"), space.add_concept_node("thing"))
    space.add_inheritance_link(space.add_concept_node("stuff"), space.add_concept_node("stuff"))
    calculator = PatternMining::SupportCalculator.new(space)
    specializer = PatternMining::PatternSpecializer.new(space)

    top = PatternMining::Utils.create_top_pattern
    shapes = specializer.determine_shallow_abstractions(calculator.valuations(top))
    shapes.map(&.to_s).should eq([
      %(ShallowAbstraction((VARIABLENODE "$X") := (INHERITANCELINK (VARIABLENODE "$X.1") (VARIABLENODE "$X.2")), freq: 6)),
      %(ShallowAbstraction((VARIABLENODE "$X") := (EVALUATIONLINK (VARIABLENODE "$X.1") (VARIABLENODE "$X.2")), freq: 3)),
      %(ShallowAbstraction((VARIABLENODE "$X") := (LISTLINK (VARIABLENODE "$X.1") (VARIABLENODE "$X.2")), freq: 3)),
    ])

    inheritance = specializer.specialize_pattern(top, shapes.first).not_nil!
    inheritance.variables.map(&.name).sort.should eq(["$X.1", "$X.2"])
    refinements = specializer.determine_shallow_abstractions(calculator.valuations(inheritance))
    refinements.map(&.to_s).should eq([
      # Three animals inherit from "animal"; two links join a node to itself.
      %(ShallowAbstraction((VARIABLENODE "$X.2") := (CONCEPTNODE "animal"), freq: 3)),
      %(ShallowAbstraction((VARIABLENODE "$X.2") := (VARIABLENODE "$X.1"), freq: 2)),
    ])

    reflexive = specializer.specialize_pattern(inheritance, refinements.last).not_nil!
    reflexive.template.to_s.should eq(%((INHERITANCELINK (VARIABLENODE "$X.1") (VARIABLENODE "$X.1"))))
    calculator.calculate_support(reflexive).should eq(2)

    # A lower bar lets rarer abstractions through.
    specializer.determine_shallow_abstractions(calculator.valuations(inheritance), 1).size.should be > refinements.size
  end

  it "replaces every occurrence of the variable, at any depth" do
    specializer = PatternMining::PatternSpecializer.new(AtomSpace::AtomSpace.new)
    x, y = variable("$X"), variable("$Y")
    base = PatternMatching::Pattern.new(
      link(AtomSpace::AtomType::EVALUATION_LINK, x, link(AtomSpace::AtomType::LIST_LINK, y, x)))

    dog = AtomSpace::ConceptNode.new("dog")
    specialized = specializer.specialize_pattern(base, PatternMining::ShallowAbstraction.new(dog, 2, x)).not_nil!
    specialized.template.to_s.should eq(
      %((EVALUATIONLINK (CONCEPTNODE "dog") (LISTLINK (VARIABLENODE "$Y") (CONCEPTNODE "dog"))))
    )
    specialized.variables.map(&.name).should eq(["$Y"])

    # A different link type than the pattern's own is no obstacle.
    shape = link(AtomSpace::AtomType::INHERITANCE_LINK, variable("$Y.1"), variable("$Y.2"))
    nested = specializer.specialize_pattern(base, PatternMining::ShallowAbstraction.new(shape, 2, y)).not_nil!
    nested.template.to_s.should eq(
      %((EVALUATIONLINK (VARIABLENODE "$X") (LISTLINK (INHERITANCELINK (VARIABLENODE "$Y.1") (VARIABLENODE "$Y.2")) (VARIABLENODE "$X"))))
    )

    # A variable the pattern does not use.
    specializer.specialize_pattern(base, PatternMining::ShallowAbstraction.new(dog, 2, variable("$Z"))).should be_nil
    # No variable named and two to choose from: nothing is refined.
    specializer.specialize_pattern(base, PatternMining::ShallowAbstraction.new(dog, 2)).not_nil!.template.to_s.should eq(base.template.to_s)
  end
end

describe PatternMining::PatternMiner do
  it "specializes from the top pattern down to the frequent structures" do
    result = PatternMining::PatternMiner.new(zoo, min_support: 2, max_patterns: 200, timeout_seconds: 20).mine_patterns
    found = result.patterns.to_h { |entry| {entry.pattern.template.to_s, entry.support} }

    found[%((INHERITANCELINK (VARIABLENODE "$X.1") (CONCEPTNODE "animal")))].should eq(3)
    found[%((EVALUATIONLINK (PREDICATENODE "likes") (LISTLINK (CONCEPTNODE "dog") (VARIABLENODE "$X.2.2"))))].should eq(2)
    found[%((EVALUATIONLINK (VARIABLENODE "$X.1") (LISTLINK (VARIABLENODE "$X.2.1") (VARIABLENODE "$X.2.2"))))].should eq(3)
    # "fears" and "plant" occur once each.
    found.keys.none?(&.includes?("fears")).should be_true
    found.keys.none?(&.includes?("plant")).should be_true
    # Every pattern reported has the support asked for and at least one variable.
    result.patterns.all? { |entry| entry.support >= 2 && !entry.pattern.variables.empty? }.should be_true
    result.total_patterns_explored.should eq(result.patterns.size)
  end

  it "stops at the pattern limit" do
    result = PatternMining::PatternMiner.new(zoo, min_support: 1, max_patterns: 5, timeout_seconds: 20).mine_patterns
    result.total_patterns_explored.should eq(5)
  end
end
