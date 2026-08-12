require "spec"
require "../../src/self_modification/self_modification"

describe SelfModification::SafeModifier do
  it "applies allowed knowledge additions" do
    atomspace = AtomSpace::AtomSpace.new
    mod = SelfModification::SafeModifier.new(atomspace)
    proposal = mod.propose("add cat", SelfModification::Permission::ADD_KNOWLEDGE, "cat",
      {"name" => "cat", "strength" => "0.9"})
    mod.apply(proposal).should be_true
    proposal.status.should eq(SelfModification::ModificationProposal::Status::APPLIED)
    mod.approved_count.should eq(1)
  end

  it "rejects high-risk proposals under policy" do
    atomspace = AtomSpace::AtomSpace.new
    policy = SelfModification::SafetyPolicy.new(max_risk: 0.2)
    mod = SelfModification::SafeModifier.new(atomspace, policy)
    proposal = mod.propose("danger", SelfModification::Permission::ADD_KNOWLEDGE, "x",
      {} of String => String, 0.9)
    mod.apply(proposal).should be_false
    proposal.status.should eq(SelfModification::ModificationProposal::Status::REJECTED)
  end

  it "adds implication rules" do
    atomspace = AtomSpace::AtomSpace.new
    mod = SelfModification::SafeModifier.new(atomspace)
    p = mod.propose("rule", SelfModification::Permission::ADD_RULE, "bird_flies",
      {"antecedent" => "bird", "consequent" => "flies", "strength" => "0.85"})
    mod.apply(p).should be_true
    atomspace.get_atoms_by_type(AtomSpace::AtomType::IMPLICATION_LINK).size.should be > 0
  end

  it "creates checkpoints" do
    atomspace = AtomSpace::AtomSpace.new
    atomspace.add_concept_node("a")
    mod = SelfModification::SafeModifier.new(atomspace)
    cp = mod.checkpoint("test")
    cp.atom_count.should be > 0
    mod.checkpoints.size.should eq(1)
  end
end

describe SelfModification::MetaLearner do
  it "adjusts params from feedback" do
    ml = SelfModification::MetaLearner.new({"learning_rate" => 0.1})
    ml.feedback(0.5)
    ml.params["learning_rate"] = 0.2
    ml.feedback(0.8)
    ml.best_params.should_not be_nil
  end
end

describe SelfModification::RuleLearner do
  it "learns and commits rules" do
    learner = SelfModification::RuleLearner.new
    5.times { learner.observe("smoke", "fire", true) }
    learner.observe("smoke", "fire", false)
    learner.confidence("smoke", "fire").should be > 0.5

    atomspace = AtomSpace::AtomSpace.new
    count = learner.commit(atomspace, 0.7, 3)
    count.should eq(1)
  end
end

describe SelfModification::ArchitectureSearch do
  it "samples and selects best config" do
    search = SelfModification::ArchitectureSearch.new
    configs = search.sample_random({"backend" => ["sqlite", "memory"], "cache" => ["on", "off"]}, 4)
    configs.size.should eq(4)
    search.evaluate(0, 0.5)
    search.evaluate(1, 0.9)
    search.best.should eq(search.candidates[1])
  end
end

describe SelfModification::CognitivePlasticity do
  it "strengthens co-activated concepts" do
    atomspace = AtomSpace::AtomSpace.new
    plastic = SelfModification::CognitivePlasticity.new(atomspace)
    plastic.hebbian_update("dog", "animal")
    plastic.usage["dog"].should eq(1)
    atomspace.get_atoms_by_type(AtomSpace::AtomType::EQUIVALENCE_LINK).size.should be > 0
  end
end
