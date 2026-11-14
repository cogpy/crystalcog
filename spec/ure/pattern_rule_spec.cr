require "spec"
require "../../src/ure/ure"

private def var(name : String) : AtomSpace::Atom
  AtomSpace::VariableNode.new(name).as(AtomSpace::Atom)
end

private def link(type : AtomSpace::AtomType, *children : AtomSpace::Atom) : AtomSpace::Atom
  AtomSpace::Link.new(type, children.to_a.map(&.as(AtomSpace::Atom))).as(AtomSpace::Atom)
end

# (Evaluation predicate (List a b)) beside any AtomSpace, for patterns and goals.
private def relation(predicate : String, a : AtomSpace::Atom, b : AtomSpace::Atom) : AtomSpace::Atom
  link(AtomSpace::AtomType::EVALUATION_LINK,
    AtomSpace::Node.new(AtomSpace::AtomType::PREDICATE_NODE, predicate).as(AtomSpace::Atom),
    link(AtomSpace::AtomType::LIST_LINK, a, b))
end

private def concept(name : String) : AtomSpace::Atom
  AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, name).as(AtomSpace::Atom)
end

private def inherits(a : AtomSpace::Atom, b : AtomSpace::Atom) : AtomSpace::Atom
  link(AtomSpace::AtomType::INHERITANCE_LINK, a, b)
end

private def grandparent_rule : URE::PatternRule
  URE::PatternRule.new("grandparent",
    [relation("parent", var("$X"), var("$Y")), relation("parent", var("$Y"), var("$Z"))],
    relation("grandparent", var("$X"), var("$Z")))
end

# ann -> bob -> cy -> dee, each link with strength 0.9 and confidence 0.8.
private def family : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  parent = space.add_predicate_node("parent")
  people = %w(ann bob cy dee).map { |name| space.add_concept_node(name) }
  3.times do |i|
    space.add_evaluation_link(parent, space.add_list_link([people[i], people[i + 1]] of AtomSpace::Atom),
      AtomSpace::SimpleTruthValue.new(0.9, 0.8))
  end
  space
end

private def pairs(space : AtomSpace::AtomSpace, predicate : String) : Array({String, String})
  space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).compact_map do |atom|
    next unless atom.is_a?(AtomSpace::Link) && atom.outgoing[0].name == predicate
    list = atom.outgoing[1]
    next unless URE::Unifier.ground?(atom)
    {list.outgoing[0].name, list.outgoing[1].name}
  end.sort
end

describe URE::PatternRule do
  it "declares its premises and conclusion as shapes and as types" do
    rule = grandparent_rule
    rule.name.should eq("grandparent")
    rule.premises.should eq([AtomSpace::AtomType::EVALUATION_LINK, AtomSpace::AtomType::EVALUATION_LINK])
    rule.conclusion.should eq(AtomSpace::AtomType::EVALUATION_LINK)
    rule.premise_patterns.size.should eq(2)
    URE::Unifier.variables(rule.conclusion_pattern).should eq(["$X", "$Z"])
  end

  it "refuses shapes it could not apply" do
    expect_raises(ArgumentError, "a rule needs a premise") do
      URE::PatternRule.new("empty", [] of AtomSpace::Atom, relation("p", var("$X"), var("$Y")))
    end
    expect_raises(ArgumentError, "a premise cannot be a bare variable") do
      URE::PatternRule.new("anything", [var("$X")], inherits(var("$X"), concept("thing")))
    end
    expect_raises(ArgumentError, "loose: $Z in the conclusion is in no premise") do
      URE::PatternRule.new("loose", [relation("p", var("$X"), var("$Y"))], relation("q", var("$X"), var("$Z")))
    end
  end

  it "concludes from atoms that fit and from no others" do
    space = family
    rule = grandparent_rule
    parents = space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
    ann_bob, bob_cy, cy_dee = parents[0], parents[1], parents[2]

    conclusion = rule.apply([ann_bob, bob_cy], space).not_nil!
    conclusion.should be(space.find_link(AtomSpace::AtomType::EVALUATION_LINK,
      [space.get_nodes_by_name("grandparent").first, space.find_link(AtomSpace::AtomType::LIST_LINK,
        [space.get_nodes_by_name("ann").first, space.get_nodes_by_name("cy").first]).not_nil!]))
    conclusion.truth_value.strength.should be_close(0.81, 1e-12)
    conclusion.truth_value.confidence.should be_close(0.8 * 0.8 * 0.9, 1e-12)

    # The middle person has to be the same; the order matters.
    rule.apply([ann_bob, cy_dee], space).should be_nil
    rule.apply([bob_cy, ann_bob], space).should be_nil
    rule.apply([ann_bob], space).should be_nil
    rule.fitness([ann_bob, bob_cy]).should be_close(0.8, 1e-12)
  end

  it "takes a formula for the conclusion's truth value" do
    space = family
    cautious = URE::PatternRule.new("cautious grandparent",
      [relation("parent", var("$X"), var("$Y")), relation("parent", var("$Y"), var("$Z"))],
      relation("grandparent", var("$X"), var("$Z"))) do |values|
      AtomSpace::SimpleTruthValue.new(values.min_of(&.strength), 0.25).as(AtomSpace::TruthValue)
    end
    parents = space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
    conclusion = cautious.apply([parents[0], parents[1]], space).not_nil!
    {conclusion.truth_value.strength, conclusion.truth_value.confidence}.should eq({0.9, 0.25})
  end

  it "leaves the truth values of the atoms it builds on alone" do
    space = family
    ann = space.get_nodes_by_name("ann").first
    ann.truth_value = AtomSpace::SimpleTruthValue.new(0.3, 0.4)
    parents = space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
    grandparent_rule.apply([parents[0], parents[1]], space)
    {ann.truth_value.strength, ann.truth_value.confidence}.should eq({0.3, 0.4})
    {parents[0].truth_value.strength, parents[0].truth_value.confidence}.should eq({0.9, 0.8})
  end
end

describe URE::RuleMatcher do
  it "finds every way atoms satisfy the premises together" do
    space = family
    patterns = grandparent_rule.premise_patterns
    found = URE::RuleMatcher.applications(patterns, space, 100) { true }
    found.map { |premises| premises.map { |atom| atom.outgoing[1].outgoing.map(&.name).join(">") } }.should eq(
      [["ann>bob", "bob>cy"], ["bob>cy", "cy>dee"]])

    URE::RuleMatcher.applications(patterns, space, 1) { true }.size.should eq(1)
    # What the block turns down does not count toward the limit.
    wanted = URE::RuleMatcher.applications(patterns, space, 1) { |premises| premises[0].outgoing[1].outgoing[0].name == "bob" }
    wanted.size.should eq(1)
    wanted.first[1].outgoing[1].outgoing[1].name.should eq("dee")
  end

  it "does not offer a stored pattern as a premise, or one atom twice" do
    space = AtomSpace::AtomSpace.new
    loop_node = space.add_concept_node("loop")
    space.add_inheritance_link(loop_node, loop_node)
    space.add_inheritance_link(space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$any"), loop_node)
    patterns = URE::InheritanceTransitivityRule.new.premise_patterns.not_nil!
    URE::RuleMatcher.applications(patterns, space, 100) { true }.should be_empty
  end

  it "says how given atoms fit the patterns" do
    space = family
    parents = space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
    bindings = URE::RuleMatcher.match(grandparent_rule.premise_patterns, [parents[1], parents[2]]).not_nil!
    bindings.transform_values(&.name).should eq({"$X" => "bob", "$Y" => "cy", "$Z" => "dee"})
    URE::RuleMatcher.match(grandparent_rule.premise_patterns, [parents[2], parents[1]]).should be_nil
  end
end

describe "URE forward chaining with pattern rules" do
  it "applies a rule wherever its premises fit" do
    space = family
    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(grandparent_rule)
    produced = chainer.run
    produced.size.should eq(2)
    pairs(space, "grandparent").should eq([{"ann", "cy"}, {"bob", "dee"}])
  end

  it "makes each application once, so running on does not pile up confidence" do
    space = family
    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(grandparent_rule)
    chainer.step_forward.size.should eq(2)
    conclusion = space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).find! { |atom| atom.outgoing[0].name == "grandparent" }
    settled = {conclusion.truth_value.strength, conclusion.truth_value.confidence}
    3.times { chainer.step_forward.should be_empty }
    {conclusion.truth_value.strength, conclusion.truth_value.confidence}.should eq(settled)
  end

  it "finds the premises that fit among many that do not" do
    space = AtomSpace::AtomSpace.new
    # Forty unrelated links make 1,560 ordered pairs, none a chain.
    sure = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
    40.times { |i| space.add_inheritance_link(space.add_concept_node("left-#{i}"), space.add_concept_node("right-#{i}"), sure) }
    a, b, c = %w(a b c).map { |name| space.add_concept_node(name) }
    space.add_inheritance_link(a, b, sure)
    space.add_inheritance_link(b, c, sure)

    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(URE::InheritanceTransitivityRule.new)
    chainer.run.size.should eq(1)
    space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, c]).should_not be_nil
  end

  it "closes a chain under transitivity" do
    space = AtomSpace::AtomSpace.new
    nodes = Array.new(12) { |i| space.add_concept_node("n#{i}") }
    11.times { |i| space.add_inheritance_link(nodes[i], nodes[i + 1], AtomSpace::SimpleTruthValue.new(1.0, 1.0)) }
    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(URE::InheritanceTransitivityRule.new)
    chainer.run
    # Every earlier node inherits from every later one: 12 * 11 / 2 links.
    space.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).size.should eq(66)
  end
end

describe "URE backward chaining with pattern rules" do
  it "proves a goal by working back through a rule's premises" do
    space = family
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(grandparent_rule)
    before = space.size

    proofs = chainer.prove(relation("grandparent", concept("ann"), concept("cy")))
    proofs.size.should eq(1)
    atom, bindings = proofs.first
    bindings.should be_empty
    atom.should be(space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).find! { |link| link.outgoing[0].name == "grandparent" })
    atom.truth_value.confidence.should be_close(0.8 * 0.8 * 0.9, 1e-12)
    # Only what the goal needed was concluded: bob is dee's grandparent too.
    pairs(space, "grandparent").should eq([{"ann", "cy"}])
    space.size.should eq(before + 3) # the predicate, the list and the link
  end

  it "answers a goal with variables" do
    space = family
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(grandparent_rule)

    proofs = chainer.prove(relation("grandparent", var("$who"), concept("dee")))
    proofs.map { |(_, bindings)| bindings.transform_values(&.name) }.should eq([{"$who" => "bob"}])

    everyone = chainer.prove(relation("grandparent", var("$old"), var("$young")))
    everyone.map { |(_, bindings)| {bindings["$old"].name, bindings["$young"].name} }.sort.should eq([{"ann", "cy"}, {"bob", "dee"}])
  end

  it "keeps a goal's variables apart from the rule's of the same name" do
    space = family
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(grandparent_rule)
    # The rule calls the grandparent $X and the grandchild $Z.
    proofs = chainer.prove(relation("grandparent", var("$Z"), var("$X")))
    proofs.map { |(_, bindings)| {bindings["$Z"].name, bindings["$X"].name} }.sort.should eq([{"ann", "cy"}, {"bob", "dee"}])
    proofs.all? { |(_, bindings)| bindings.keys.sort == ["$X", "$Z"] }.should be_true
  end

  it "does not try a rule whose conclusion cannot be the goal" do
    space = family
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(grandparent_rule)
    before = space.size
    chainer.prove(relation("cousin", concept("ann"), concept("cy"))).should be_empty
    chainer.prove(relation("grandparent", concept("ann"), concept("dee"))).should be_empty
    chainer.prove(relation("grandparent", concept("ann"), concept("nobody"))).should be_empty
    space.size.should eq(before)
  end

  it "chains rules: a great-grandparent needs a grandparent first" do
    space = family
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(grandparent_rule)
    chainer.add_rule(URE::PatternRule.new("great-grandparent",
      [relation("grandparent", var("$A"), var("$B")), relation("parent", var("$B"), var("$C"))],
      relation("great-grandparent", var("$A"), var("$C"))))

    proofs = chainer.prove(relation("great-grandparent", var("$elder"), var("$child")))
    proofs.map { |(_, bindings)| {bindings["$elder"].name, bindings["$child"].name} }.should eq([{"ann", "dee"}])
    pairs(space, "great-grandparent").should eq([{"ann", "dee"}])
  end

  it "proves through a recursive rule without going round for ever" do
    space = AtomSpace::AtomSpace.new
    dog, mammal, animal, living = %w(dog mammal animal living).map { |name| space.add_concept_node(name) }
    space.add_inheritance_link(dog, mammal, AtomSpace::SimpleTruthValue.new(0.9, 0.9))
    space.add_inheritance_link(mammal, animal, AtomSpace::SimpleTruthValue.new(0.9, 0.9))
    space.add_inheritance_link(animal, living, AtomSpace::SimpleTruthValue.new(0.9, 0.9))
    # A circle as well: living things are, loosely, animals.
    space.add_inheritance_link(living, animal, AtomSpace::SimpleTruthValue.new(0.2, 0.9))
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(URE::InheritanceTransitivityRule.new)

    proofs = chainer.prove(inherits(concept("dog"), concept("living")))
    proofs.size.should eq(1)
    proofs.first[0].should be(space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [dog, living]))
    chainer.prove(inherits(concept("living"), concept("dog"))).should be_empty

    above = chainer.prove(inherits(concept("dog"), var("$kind"))).map { |(_, bindings)| bindings["$kind"].name }.sort
    above.should eq(["animal", "living", "mammal"])
  end

  it "lets do_chain and the queries use what the rules can prove" do
    space = family
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(grandparent_rule)
    goal = relation("grandparent", concept("ann"), concept("cy"))
    pairs(space, "grandparent").should be_empty
    chainer.do_chain(goal).should_not be_empty
    pairs(space, "grandparent").should eq([{"ann", "cy"}])

    pattern = relation("grandparent", var("$old"), var("$young"))
    # ann and cy were concluded above; bob and dee have not been yet.
    chainer.variable_fulfillment_query(pattern).map { |row| row["$old"].name }.should eq(["ann"])
    chainer.variable_fulfillment_query(pattern, derive: true).map { |row| row["$old"].name }.sort.should eq(["ann", "bob"])
  end
end

describe "URE::Unifier.rename" do
  it "renames every variable and nothing else" do
    atom = relation("parent", var("$X"), link(AtomSpace::AtomType::LIST_LINK, var("$Y"), concept("cy")))
    renamed = URE::Unifier.rename(atom, "~1")
    URE::Unifier.variables(renamed).should eq(["$X~1", "$Y~1"])
    renamed.to_s.should eq(atom.to_s.gsub("$X", "$X~1").gsub("$Y", "$Y~1"))
    ground = relation("parent", concept("ann"), concept("bob"))
    URE::Unifier.rename(ground, "~1").should be(ground)
  end
end
