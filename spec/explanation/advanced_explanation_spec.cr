require "spec"
require "../../src/explanation/explanation"

describe ReasoningExplanation::ConfidenceCalibrator do
  it "tracks reliability and ECE" do
    cal = ReasoningExplanation::ConfidenceCalibrator.new(5)
    10.times { cal.observe(0.9, true) }
    10.times { cal.observe(0.2, false) }
    cal.ece.should be >= 0.0
    diagram = cal.reliability_diagram
    diagram.should_not be_empty
    text = cal.explain_confidence(0.9)
    text.should contain("confidence")
  end
end

describe ReasoningExplanation::ExplanationTrace do
  it "exports visualization and graph edges" do
    trace = ReasoningExplanation::ExplanationTrace.new("C")
    trace.add_step(ReasoningExplanation::ReasoningStep.new(
      ReasoningExplanation::StepType::DEDUCTION, "A", "B", 0.9, "r1"
    ))
    trace.add_step(ReasoningExplanation::ReasoningStep.new(
      ReasoningExplanation::StepType::DEDUCTION, "B", "C", 0.8, "r2"
    ))
    viz = trace.to_visualization
    viz["conclusion"].as_s.should eq("C")
    viz["steps"].as_a.size.should eq(2)
    edges = trace.to_graph_edges
    edges.size.should eq(2)
    edges.last[1].should eq("C")
  end
end

describe ReasoningExplanation::ExplanationGenerator do
  it "renders templates and calibrated explanations" do
    atomspace = AtomSpace::AtomSpace.new
    gen = ReasoningExplanation::ExplanationGenerator.new(atomspace)
    gen.record_step("flies", ReasoningExplanation::ReasoningStep.new(
      ReasoningExplanation::StepType::DEDUCTION, "bird", "flies", 0.85, "Inheritance"
    ))
    gen.calibrator.observe(0.85, true)
    gen.calibrator.observe(0.85, true)

    step = ReasoningExplanation::ReasoningStep.new(
      ReasoningExplanation::StepType::LOOKUP, "", "sky is blue", 1.0
    )
    gen.render_step_template(step).should contain("Retrieved")

    text = gen.explain_calibrated("flies")
    text.should contain("flies")
    text.should contain("calibration")

    viz = gen.visualize("flies")
    viz.has_key?("steps").should be_true
  end

  it "includes calibration in contrastive explanations" do
    atomspace = AtomSpace::AtomSpace.new
    gen = ReasoningExplanation::ExplanationGenerator.new(atomspace)
    gen.record_step("A", ReasoningExplanation::ReasoningStep.new(
      ReasoningExplanation::StepType::DEDUCTION, "p", "A", 0.9
    ))
    gen.record_step("B", ReasoningExplanation::ReasoningStep.new(
      ReasoningExplanation::StepType::DEDUCTION, "q", "B", 0.4
    ))
    text = gen.contrastive_explanation("A", "B")
    text.should contain("rather than")
    text.should contain("Calibration")
  end
end
