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

private def diets : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  animal = space.add_concept_node("animal")
  plant = space.add_concept_node("plant")
  eats = space.add_predicate_node("eats")
  likes = space.add_predicate_node("likes")
  meat = space.add_concept_node("meat")
  water = space.add_concept_node("water")
  %w(dog cat wolf fox).each do |name|
    creature = space.add_concept_node(name)
    space.add_inheritance_link(creature, animal)
    space.add_evaluation_link(eats, space.add_list_link([creature, meat] of AtomSpace::Atom))
  end
  %w(cow sheep).each { |name| space.add_inheritance_link(space.add_concept_node(name), animal) }
  %w(fern moss rose).each do |name|
    growth = space.add_concept_node(name)
    space.add_inheritance_link(growth, plant)
    space.add_evaluation_link(likes, space.add_list_link([growth, water] of AtomSpace::Atom))
  end
  space
end

describe PatternMining::ConjunctionMiner do
  it "joins frequent patterns on a shared variable" do
    miner = PatternMining::PatternMiner.new(diets, min_support: 3, max_patterns: 300, timeout_seconds: 20)
    conjunctions = miner.mine_conjunctions
    found = conjunctions.to_h { |conjunction| {conjunction.to_s, conjunction} }

    meat_eaters = found[%((AND (EVALUATIONLINK (PREDICATENODE "eats") (LISTLINK (VARIABLENODE "$v1") (CONCEPTNODE "meat"))) (INHERITANCELINK (VARIABLENODE "$v1") (CONCEPTNODE "animal"))))]
    meat_eaters.support.should eq(4)
    meat_eaters.variables.should eq(["$v1"])
    meat_eaters.groundings.map { |row| row["$v1"].name }.sort.should eq(["cat", "dog", "fox", "wolf"])
    meat_eaters.meets_minimum_support?(4).should be_true
    meat_eaters.meets_minimum_support?(5).should be_false

    drinkers = found[%((AND (EVALUATIONLINK (PREDICATENODE "likes") (LISTLINK (VARIABLENODE "$v1") (CONCEPTNODE "water"))) (INHERITANCELINK (VARIABLENODE "$v1") (CONCEPTNODE "plant"))))]
    drinkers.support.should eq(3)
    # Three atoms like water and three are plants. Were the two unrelated,
    # a liker of water would be a given plant once in as many tries as
    # there are atoms: 3 * 3 / atoms groundings, not the 3 there are.
    drinkers.surprisingness.should be_close(1 - (3 * 3 / diets.size.to_f) / 3, 1e-12)
    drinkers.surprisingness.should be > 0.9

    # Nothing eats meat and is a plant.
    found.keys.none? { |key| key.includes?("meat") && key.includes?("plant") }.should be_true
    conjunctions.all? { |conjunction| conjunction.support >= 3 && conjunction.clauses.size == 2 }.should be_true
    # Most supported first.
    conjunctions.map(&.support).should eq(conjunctions.map(&.support).sort.reverse)
  end

  it "leaves out clauses that another clause already implies" do
    conjunctions = PatternMining::PatternMiner.new(diets, min_support: 3, max_patterns: 300).mine_conjunctions
    texts = conjunctions.map(&.to_s)
    # A list inside an evaluation clause is not a second fact.
    texts.none? { |text| text.includes?(%[(LISTLINK (VARIABLENODE "$v1") (CONCEPTNODE "meat"))) (LISTLINK]) }.should be_true
    conjunctions.each do |conjunction|
      first, second = conjunction.clauses.map(&.to_s)
      first.should_not eq(second)
      first.includes?(second).should be_false
      second.includes?(first).should be_false
    end
    # "inherits from something" adds nothing to "inherits from animal".
    texts.none? { |text| text.includes?(%[(INHERITANCELINK (VARIABLENODE "$v1") (CONCEPTNODE "animal")) (INHERITANCELINK (VARIABLENODE "$v1") (VARIABLENODE]) }.should be_true
  end

  it "names variables the same way whichever pattern comes first" do
    space = diets
    patterns = PatternMining::PatternMiner.new(space, min_support: 3, max_patterns: 300).mine_patterns.patterns.map(&.pattern)
    forwards = PatternMining::ConjunctionMiner.new(space, min_support: 3).mine(patterns).map(&.to_s).sort
    backwards = PatternMining::ConjunctionMiner.new(space, min_support: 3).mine(patterns.reverse).map(&.to_s).sort
    forwards.should eq(backwards)
    forwards.uniq.size.should eq(forwards.size)
  end

  it "grows to three clauses when asked and respects its limits" do
    space = diets
    carnivore = space.add_concept_node("carnivore")
    %w(dog cat wolf fox).each { |name| space.add_inheritance_link(space.get_nodes_by_name(name).first, carnivore) }
    miner = PatternMining::PatternMiner.new(space, min_support: 4, max_patterns: 300, timeout_seconds: 20)

    triples = miner.mine_conjunctions(max_clauses: 3).select { |conjunction| conjunction.clauses.size == 3 }
    triples.should_not be_empty
    wanted = triples.find do |conjunction|
      text = conjunction.to_s
      text.includes?(%("animal")) && text.includes?(%("carnivore")) && text.includes?(%("eats")) && text.includes?(%("meat"))
    end.not_nil!
    wanted.support.should eq(4)

    # Six animals, four carnivores, four meat eaters, and the same four are
    # all three. The split that comes closest to explaining that keeps
    # "carnivore and eats meat" (4) together and takes "animal" (6) as
    # unrelated: 4 * 6 / atoms. Three unrelated clauses would expect far
    # fewer, 6 * 4 * 4 / atoms squared, and so look more surprising.
    atoms = space.size.to_f
    wanted.surprisingness.should be_close(1 - (4 * 6 / atoms) / 4, 1e-12)
    wanted.surprisingness.should be < 1 - (6 * 4 * 4 / (atoms * atoms)) / 4
    triples.each { |conjunction| (0.0..1.0).includes?(conjunction.surprisingness).should be_true }

    miner.mine_conjunctions(max_conjunctions: 3).size.should eq(3)
    expect_raises(PatternMining::MiningException) { PatternMining::ConjunctionMiner.new(space, max_clauses: 1) }
    # Nothing frequent enough: nothing to join.
    PatternMining::PatternMiner.new(space, min_support: 50).mine_conjunctions.should be_empty
  end
end

describe "PatternMining conjunction surprisingness" do
  it "scores a chain whose clauses share no single variable" do
    space = AtomSpace::AtomSpace.new
    parent = space.add_predicate_node("parent")
    people = %w(ann bob cy dee eve fay).map { |name| space.add_concept_node(name) }
    # ann -> bob -> cy and dee -> eve -> fay: two grandparent chains.
    [{0, 1}, {1, 2}, {3, 4}, {4, 5}].each do |(older, younger)|
      space.add_evaluation_link(parent, space.add_list_link([people[older], people[younger]] of AtomSpace::Atom))
    end
    x, y, z = %w($x $y $z).map { |name| AtomSpace::VariableNode.new(name).as(AtomSpace::Atom) }
    of = ->(a : AtomSpace::Atom, b : AtomSpace::Atom) {
      AtomSpace::Link.new(AtomSpace::AtomType::EVALUATION_LINK,
        [parent.as(AtomSpace::Atom), AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [a, b]).as(AtomSpace::Atom)]).as(AtomSpace::Atom)
    }
    patterns = [PatternMatching::Pattern.new(of.call(x, y))]

    chains = PatternMining::ConjunctionMiner.new(space, min_support: 2).mine(patterns)
    grandparent = chains.find { |conjunction| conjunction.variables.size == 3 }.not_nil!
    grandparent.support.should eq(2)
    grandparent.groundings.map { |row| row.values.map(&.name) }.sort.should eq([%w(ann bob cy), %w(dee eve fay)])
    # Four parent links each way; the middle person is right by chance
    # once in as many tries as there are atoms.
    grandparent.surprisingness.should be_close(1 - (4 * 4 / space.size.to_f) / 2, 1e-12)
  end

  it "measures a deviation as a share of the larger side" do
    scorer = PatternMining::SurprisingnessScorer.new(AtomSpace::AtomSpace.new)
    scorer.deviation(4.0, 4.0).should eq(0.0)
    scorer.deviation(4.0, 1.0).should eq(0.75)
    scorer.deviation(1.0, 4.0).should eq(0.75)
    scorer.deviation(3.0, 0.0).should eq(1.0)
    scorer.deviation(0.0, 0.0).should eq(0.0)
  end
end
