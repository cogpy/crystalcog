require "spec"
require "../../src/ure/ure"

private def var(name : String) : AtomSpace::Atom
  AtomSpace::VariableNode.new(name).as(AtomSpace::Atom)
end

private def concept(name : String) : AtomSpace::Atom
  AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, name).as(AtomSpace::Atom)
end

# (Evaluation predicate (List arguments...)) beside any AtomSpace, for goals.
private def goal(predicate : String, *arguments : AtomSpace::Atom) : AtomSpace::Atom
  list = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, arguments.to_a.map(&.as(AtomSpace::Atom))).as(AtomSpace::Atom)
  AtomSpace::Link.new(AtomSpace::AtomType::EVALUATION_LINK,
    [AtomSpace::Node.new(AtomSpace::AtomType::PREDICATE_NODE, predicate).as(AtomSpace::Atom), list]).as(AtomSpace::Atom)
end

private def both(*parts : AtomSpace::Atom) : AtomSpace::Atom
  AtomSpace::Link.new(AtomSpace::AtomType::AND_LINK, parts.to_a.map(&.as(AtomSpace::Atom))).as(AtomSpace::Atom)
end

# A fact in the AtomSpace: predicate(names...).
private def fact(space : AtomSpace::AtomSpace, predicate : String, *names : String,
                 strength : Float64 = 0.9, confidence : Float64 = 0.8) : AtomSpace::Atom
  arguments = names.to_a.map { |name| name.starts_with?('$') ? space.add_atom(var(name)) : space.add_concept_node(name) }
  space.add_evaluation_link(space.add_predicate_node(predicate), space.add_list_link(arguments),
    AtomSpace::SimpleTruthValue.new(strength, confidence))
end

# john and mary like each other, john is tall; sue's cat is nobody else's.
private def village : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  fact(space, "likes", "john", "mary")
  fact(space, "likes", "mary", "john", strength: 0.6, confidence: 0.5)
  fact(space, "tall", "john")
  fact(space, "owns", "sue", "cat")
  space
end

private def said(atom : AtomSpace::Atom) : String
  list = atom.as(AtomSpace::Link).outgoing[1].as(AtomSpace::Link)
  "#{atom.as(AtomSpace::Link).outgoing[0].name}(#{list.outgoing.map(&.name).join(",")})"
end

private def conjunctions(space : AtomSpace::AtomSpace) : Array(String)
  space.get_atoms_by_type(AtomSpace::AtomType::AND_LINK).map { |atom| atom.as(AtomSpace::Link).outgoing.map { |part| said(part) }.join(" & ") }.sort
end

private def every : Array(AtomSpace::Atom) -> Bool
  ->(premises : Array(AtomSpace::Atom)) { true }
end

describe URE::ConjunctionRule do
  it "pairs facts that speak of a common atom, each pair once" do
    space = village
    found = URE::ConjunctionRule.new.find_applications(space, 100, every).not_nil!
    found.map { |premises| premises.map { |part| said(part) }.join(" & ") }.sort.should eq([
      "likes(john,mary) & likes(mary,john)",
      "likes(john,mary) & tall(john)",
      "likes(mary,john) & tall(john)",
    ])
    # The fact made earlier comes first.
    found.all? { |premises| premises[0].handle < premises[1].handle }.should be_true
  end

  it "counts only the pairs it is allowed and stops at the limit" do
    space = village
    rule = URE::ConjunctionRule.new
    rule.find_applications(space, 2, every).not_nil!.size.should eq(2)
    tall = ->(premises : Array(AtomSpace::Atom)) { premises.any? { |part| said(part) == "tall(john)" } }
    rule.find_applications(space, 100, tall).not_nil!.size.should eq(2)
    rule.find_applications(space, 100, ->(premises : Array(AtomSpace::Atom)) { false }).not_nil!.should be_empty
  end

  it "takes a lone argument as what a fact speaks of" do
    space = AtomSpace::AtomSpace.new
    rex = space.add_concept_node("rex")
    sure = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
    barks = space.add_evaluation_link(space.add_predicate_node("barks"), rex, sure)
    fact(space, "chases", "rex", "cat")
    fact(space, "sleeps", "cat")
    found = URE::ConjunctionRule.new.find_applications(space, 100, every).not_nil!
    found.size.should eq(2)
    found.count { |premises| premises.includes?(barks) }.should eq(1)
  end

  it "leaves patterns alone" do
    space = village
    fact(space, "likes", "$who", "john")
    fact(space, "tall", "$who")
    URE::ConjunctionRule.new.find_applications(space, 100, every).not_nil!.size.should eq(3)
  end
end

describe "URE forward chaining with the conjunction rule" do
  it "draws each conjunction once and then has nothing left to do" do
    space = village
    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    chainer.step_forward.size.should eq(3)
    conjunctions(space).should eq([
      "likes(john,mary) & likes(mary,john)",
      "likes(john,mary) & tall(john)",
      "likes(mary,john) & tall(john)",
    ])
    chainer.step_forward.should be_empty

    # As strong as the weaker fact, and less sure than the less sure one.
    weak = space.get_atoms_by_type(AtomSpace::AtomType::AND_LINK).find! { |atom| atom.as(AtomSpace::Link).outgoing.map { |part| said(part) } == ["likes(mary,john)", "tall(john)"] }
    weak.truth_value.strength.should be_close(0.6, 1e-9)
    weak.truth_value.confidence.should be_close(0.45, 1e-9)
  end

  it "moves on to the pairs a new fact makes" do
    space = village
    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    chainer.step_forward.size.should eq(3)
    fact(space, "feeds", "mary", "cat")
    drawn = chainer.step_forward
    drawn.map { |atom| atom.as(AtomSpace::Link).outgoing.map { |part| said(part) }.join(" & ") }.sort.should eq([
      "likes(john,mary) & feeds(mary,cat)",
      "likes(mary,john) & feeds(mary,cat)",
      "owns(sue,cat) & feeds(mary,cat)",
    ])
    chainer.step_forward.should be_empty
  end

  it "gets through more pairs than one step takes" do
    space = AtomSpace::AtomSpace.new
    40.times { |i| fact(space, "knows", "hub", "p#{i}") }
    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    # 40 facts about one atom make 780 pairs; a step takes 500.
    chainer.step_forward.size.should eq(500)
    chainer.step_forward.size.should eq(280)
    chainer.step_forward.should be_empty
    space.get_atoms_by_type(AtomSpace::AtomType::AND_LINK).size.should eq(780)

    again = AtomSpace::AtomSpace.new
    40.times { |i| fact(again, "knows", "hub", "p#{i}") }
    runner = URE::ForwardChainer.new(again)
    runner.add_rule(URE::ConjunctionRule.new)
    runner.run.size.should eq(780)
  end

  it "does not join facts that have nothing in common" do
    space = AtomSpace::AtomSpace.new
    fact(space, "likes", "john", "mary")
    fact(space, "owns", "sue", "cat")
    fact(space, "likes", "bob", "ann")
    chainer = URE::ForwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    chainer.run.should be_empty
    # Given the two facts outright, the rule still joins them.
    facts = space.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
    URE::ConjunctionRule.new.apply([facts[0], facts[1]], space).should_not be_nil
  end
end

describe "URE proof search for a conjunction" do
  it "proves the parts in order, each with what the ones before settled" do
    space = village
    fact(space, "likes", "sue", "mary")
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)

    # Who likes mary and is tall? john and sue like her; only john is tall.
    proofs = chainer.prove(both(goal("likes", var("$x"), concept("mary")), goal("tall", var("$x"))))
    proofs.map { |(_, bindings)| bindings["$x"].name }.should eq(["john"])
    proved = proofs.first[0]
    proved.type.should eq(AtomSpace::AtomType::AND_LINK)
    space.contains?(proved).should be_true
    proved.as(AtomSpace::Link).outgoing.map { |part| said(part) }.should eq(["likes(john,mary)", "tall(john)"])
    proved.truth_value.strength.should be_close(0.9, 1e-9)
    proved.truth_value.confidence.should be_close(0.72, 1e-9)
  end

  it "finds every way the parts fit together" do
    space = village
    fact(space, "likes", "sue", "john")
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    # Pairs who like each other.
    proofs = chainer.prove(both(goal("likes", var("$a"), var("$b")), goal("likes", var("$b"), var("$a"))))
    proofs.map { |(_, bindings)| {bindings["$a"].name, bindings["$b"].name} }.sort.should eq([{"john", "mary"}, {"mary", "john"}])
  end

  it "proves a part with the other rules" do
    space = AtomSpace::AtomSpace.new
    %w(ann bob cy dee).each_cons_pair { |parent, child| fact(space, "parent", parent, child) }
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    chainer.add_rule(URE::PatternRule.new("grandparent",
      [goal("parent", var("$X"), var("$Y")), goal("parent", var("$Y"), var("$Z"))],
      goal("grandparent", var("$X"), var("$Z"))))

    # Whose grandparent is ann, and who is that one's child?
    proofs = chainer.prove(both(goal("grandparent", concept("ann"), var("$z")), goal("parent", var("$z"), var("$w"))))
    proofs.map { |(_, bindings)| {bindings["$z"].name, bindings["$w"].name} }.should eq([{"cy", "dee"}])
  end

  it "does not prove a conjunction with a part that fails, and adds nothing" do
    space = village
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    before = space.size
    chainer.prove(both(goal("likes", concept("john"), concept("mary")), goal("tall", concept("mary")))).should be_empty
    chainer.prove(both(goal("owns", var("$x"), concept("cat")), goal("tall", var("$x")))).should be_empty
    space.size.should eq(before)
  end

  it "proves a conjunction without variables once" do
    space = village
    chainer = URE::BackwardChainer.new(space)
    chainer.add_rule(URE::ConjunctionRule.new)
    wanted = both(goal("likes", concept("john"), concept("mary")), goal("tall", concept("john")))
    chainer.prove(wanted).size.should eq(1)
    size = space.size
    3.times { chainer.prove(wanted).size.should eq(1) }
    space.size.should eq(size)
    chainer.do_chain(wanted).should_not be_empty
  end
end
