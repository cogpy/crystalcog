require "spec"
require "../../src/pln/pln"

describe PLN::FuzzyMembership do
  it "computes triangular membership" do
    PLN::FuzzyMembership.triangular(5.0, 5.0, 2.0).should be_close(1.0, 0.001)
    PLN::FuzzyMembership.triangular(6.0, 5.0, 2.0).should be_close(0.5, 0.001)
    PLN::FuzzyMembership.triangular(8.0, 5.0, 2.0).should eq(0.0)
  end

  it "computes gaussian membership" do
    PLN::FuzzyMembership.gaussian(0.0, 0.0, 1.0).should be_close(1.0, 0.001)
    PLN::FuzzyMembership.gaussian(100.0, 0.0, 1.0).should be_close(0.0, 0.01)
  end

  it "converts membership to truth value" do
    tv = PLN::FuzzyMembership.to_truth_value(0.75)
    tv.strength.should be_close(0.75, 0.001)
  end
end

describe PLN::JointProbability do
  it "computes independent joint" do
    a = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
    b = AtomSpace::SimpleTruthValue.new(0.5, 0.9)
    joint = PLN::JointProbability.independent(a, b)
    joint.strength.should be_close(0.4, 0.001)
  end

  it "computes noisy-OR" do
    a = AtomSpace::SimpleTruthValue.new(0.5, 0.9)
    b = AtomSpace::SimpleTruthValue.new(0.5, 0.9)
    result = PLN::JointProbability.noisy_or(a, b)
    result.strength.should be_close(0.75, 0.001)
  end

  it "computes conditional joint" do
    a_given_b = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
    b = AtomSpace::SimpleTruthValue.new(0.5, 0.9)
    result = PLN::JointProbability.conditional(a_given_b, b)
    result.strength.should be_close(0.4, 0.001)
  end
end

describe "PLN.revise_truth_values" do
  it "revises two truth values with confidence weighting" do
    tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.5)
    tv2 = AtomSpace::SimpleTruthValue.new(0.4, 0.5)
    revised = PLN.revise_truth_values(tv1, tv2)
    revised.strength.should be_close(0.6, 0.001)
    revised.confidence.should be > 0.5
  end
end

describe PLN::RevisionRule do
  it "has correct name" do
    PLN::RevisionRule.new.name.should eq("RevisionRule")
  end
end

describe PLN::ConditionalRule do
  it "applies conditional reasoning to inheritance" do
    atomspace = AtomSpace::AtomSpace.new
    bird = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "bird",
      AtomSpace::SimpleTruthValue.new(0.9, 0.9))
    flies = atomspace.add_concept_node("flies")
    impl = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [bird, flies],
      AtomSpace::SimpleTruthValue.new(0.85, 0.9))

    rule = PLN::ConditionalRule.new
    rule.applies_to?(impl).should be_true
    result = rule.apply(impl, atomspace)
    result.should_not be_nil
  end
end

describe PLN::EvaluationRule do
  it "estimates TV from similar evaluations" do
    atomspace = AtomSpace::AtomSpace.new
    pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "likes")
    a = atomspace.add_concept_node("alice")
    b = atomspace.add_concept_node("bob")
    c = atomspace.add_concept_node("carol")

    list1 = atomspace.add_list_link([a, b])
    eval1 = atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [pred, list1],
      AtomSpace::SimpleTruthValue.new(0.9, 0.9))

    list2 = atomspace.add_list_link([a, c])
    eval2 = atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [pred, list2],
      AtomSpace::SimpleTruthValue.new(0.3, 0.2))

    rule = PLN::EvaluationRule.new
    rule.applies_to?(eval2).should be_true
    result = rule.apply(eval2, atomspace)
    # May or may not update depending on confidence comparison
    result.should_not be_nil if eval2.truth_value.confidence < 0.9 * 0.7
  end
end

describe PLN::HigherOrderRule do
  it "detects higher-order premises" do
    atomspace = AtomSpace::AtomSpace.new
    a = atomspace.add_concept_node("a")
    b = atomspace.add_concept_node("b")
    c = atomspace.add_concept_node("c")
    ab = atomspace.add_inheritance_link(a, b)
    bc = atomspace.add_inheritance_link(b, c)
    meta = atomspace.add_link(AtomSpace::AtomType::IMPLICATION_LINK, [ab, bc],
      AtomSpace::SimpleTruthValue.new(0.8, 0.8))

    rule = PLN::HigherOrderRule.new
    rule.applies_to?(meta).should be_true
    result = rule.apply(meta, atomspace)
    result.should_not be_nil
  end
end

describe "PLNEngine with advanced rules" do
  it "includes advanced rules by default" do
    atomspace = AtomSpace::AtomSpace.new
    engine = PLN.create_engine(atomspace)
    # Smoke test: reason without crashing
    results = engine.reason(2)
    results.should be_a(Array(AtomSpace::Atom))
  end
end
