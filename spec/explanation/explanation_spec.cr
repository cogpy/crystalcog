require "spec"
require "../../src/explanation/explanation"

describe Explanation do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    Explanation.initialize
  end

  describe "initialization" do
    it "initializes the Explanation subsystem without errors" do
      Explanation.initialize
    end

    it "has correct version" do
      Explanation::VERSION.should eq("0.1.0")
    end
  end

  describe "ReasoningStep" do
    it "creates a reasoning step" do
      step = Explanation::ReasoningStep.new(
        Explanation::StepType::DEDUCTION,
        "All birds can fly",
        "Tweety can fly",
        0.9,
        "modus_ponens"
      )
      step.step_type.should eq(Explanation::StepType::DEDUCTION)
      step.premise.should eq("All birds can fly")
      step.conclusion.should eq("Tweety can fly")
      step.confidence.should eq(0.9)
    end

    it "converts to string" do
      step = Explanation::ReasoningStep.new(Explanation::StepType::LOOKUP, "stored_fact", "X is true")
      step.to_s.should contain("LOOKUP")
    end
  end

  describe "ExplanationTrace" do
    it "starts empty" do
      trace = Explanation::ExplanationTrace.new("my conclusion")
      trace.conclusion.should eq("my conclusion")
      trace.empty?.should be_true
      trace.depth.should eq(0)
    end

    it "computes overall confidence as product of step confidences" do
      trace = Explanation::ExplanationTrace.new("result")
      step1 = Explanation::ReasoningStep.new(Explanation::StepType::DEDUCTION, "A", "B", 0.9)
      step2 = Explanation::ReasoningStep.new(Explanation::StepType::DEDUCTION, "B", "C", 0.8)
      trace.add_step(step1)
      trace.add_step(step2)
      trace.overall_confidence.should be_close(0.72, 0.001)
    end

    it "generates natural language explanation" do
      trace = Explanation::ExplanationTrace.new("birds can fly")
      step = Explanation::ReasoningStep.new(
        Explanation::StepType::DEDUCTION,
        "animals with wings flap them to fly",
        "birds can fly",
        1.0,
        "deduction_rule"
      )
      trace.add_step(step)
      explanation = trace.to_natural_language
      explanation.should contain("birds can fly")
      explanation.should contain("deduce")
    end

    it "returns default message for empty trace" do
      trace = Explanation::ExplanationTrace.new("empty")
      trace.to_natural_language.should eq("No explanation available.")
    end

    it "handles different step types in natural language" do
      step_types = [
        Explanation::StepType::INDUCTION,
        Explanation::StepType::ABDUCTION,
        Explanation::StepType::ANALOGY,
        Explanation::StepType::OBSERVATION,
        Explanation::StepType::INFERENCE,
      ]
      step_types.each do |st|
        trace = Explanation::ExplanationTrace.new("conclusion")
        trace.add_step(Explanation::ReasoningStep.new(st, "premise", "conclusion"))
        trace.to_natural_language.should_not be_empty
      end
    end
  end

  describe "ExplanationGenerator" do
    it "initializes with an atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      gen = Explanation::ExplanationGenerator.new(atomspace)
      gen.traces.should be_empty
    end

    it "records manual reasoning steps" do
      atomspace = AtomSpace::AtomSpace.new
      gen = Explanation::ExplanationGenerator.new(atomspace)
      step = Explanation::ReasoningStep.new(
        Explanation::StepType::LOOKUP,
        "knowledge_base",
        "sky is blue",
        1.0
      )
      gen.record_step("sky is blue", step)
      gen.traces["sky is blue"]?.should_not be_nil
    end

    it "explains conclusions using recorded steps" do
      atomspace = AtomSpace::AtomSpace.new
      gen = Explanation::ExplanationGenerator.new(atomspace)
      step = Explanation::ReasoningStep.new(Explanation::StepType::DEDUCTION, "P→Q, P", "Q")
      gen.record_step("Q", step)
      trace = gen.explain("Q")
      trace.conclusion.should eq("Q")
    end

    it "generates contrastive explanation" do
      atomspace = AtomSpace::AtomSpace.new
      gen = Explanation::ExplanationGenerator.new(atomspace)

      step_a = Explanation::ReasoningStep.new(Explanation::StepType::DEDUCTION, "evidence_a", "A", 0.9)
      step_b = Explanation::ReasoningStep.new(Explanation::StepType::DEDUCTION, "evidence_b", "B", 0.5)
      gen.record_step("A", step_a)
      gen.record_step("B", step_b)
      gen.explain("A")
      gen.explain("B")

      contrast = gen.contrastive_explanation("A", "B")
      contrast.should contain("A")
      contrast.should contain("B")
    end

    it "stores explanation traces in atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      gen = Explanation::ExplanationGenerator.new(atomspace)
      step = Explanation::ReasoningStep.new(Explanation::StepType::DEDUCTION, "premise", "result", 0.95, "rule1")
      gen.record_step("result", step)
      gen.to_atomspace
      atomspace.size.should be > 0
    end

    it "explains using AtomSpace implication links" do
      atomspace = AtomSpace::AtomSpace.new
      premise_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "birds_have_wings")
      conclusion_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "birds_can_fly")
      tv = AtomSpace::SimpleTruthValue.new(0.95, 0.9)
      atomspace.add_link(AtomSpace::AtomType::IMPLICATION_LINK, [premise_node, conclusion_node], tv)

      gen = Explanation::ExplanationGenerator.new(atomspace)
      trace = gen.explain("birds_can_fly")
      trace.conclusion.should eq("birds_can_fly")
    end
  end
end
