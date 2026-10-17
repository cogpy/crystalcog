require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/pln/pln"
require "../../src/explanation/explainer"

describe Explanation do
  describe Explanation::ReasoningStep do
    it "creates reasoning step" do
      step = Explanation::ReasoningStep.new(
        1,
        "Modus Ponens",
        ["A", "A -> B"],
        "B",
        0.9
      )

      step.step_number.should eq(1)
      step.rule_name.should eq("Modus Ponens")
      step.premises.should eq(["A", "A -> B"])
      step.conclusion.should eq("B")
      step.confidence.should eq(0.9)
    end

    it "converts to string" do
      step = Explanation::ReasoningStep.new(1, "Rule", ["P1"], "C", 0.8)
      str = step.to_s

      str.should contain("Step 1")
      str.should contain("Rule")
      str.should contain("P1")
      str.should contain("C")
    end
  end

  describe Explanation::ReasoningTrace do
    it "creates reasoning trace" do
      trace = Explanation::ReasoningTrace.new("Is X a mammal?")

      trace.query.should eq("Is X a mammal?")
      trace.steps.should be_empty
      trace.depth.should eq(0)
    end

    it "adds steps" do
      trace = Explanation::ReasoningTrace.new("query")

      trace.add_step("Rule1", ["P1"], "C1", 0.9)
      trace.add_step("Rule2", ["C1"], "C2", 0.85)

      trace.steps.size.should eq(2)
      trace.depth.should eq(2)
    end

    it "finalizes trace" do
      trace = Explanation::ReasoningTrace.new("query")
      trace.add_step("Rule", ["P"], "C", 0.9)
      trace.finalize("Final conclusion", 0.95)

      trace.final_conclusion.should eq("Final conclusion")
      trace.final_confidence.should eq(0.95)
      trace.end_time.should_not be_nil
    end

    it "tracks rules used" do
      trace = Explanation::ReasoningTrace.new("query")
      trace.add_step("Rule1", ["P1"], "C1", 0.9)
      trace.add_step("Rule2", ["C1"], "C2", 0.85)
      trace.add_step("Rule1", ["C2"], "C3", 0.8)

      rules = trace.rules_used
      rules.should eq(["Rule1", "Rule2"])
    end
  end

  describe Explanation::ExplanationNode do
    it "creates explanation node" do
      node = Explanation::ExplanationNode.new("fact content", :fact, 0.9)

      node.content.should eq("fact content")
      node.node_type.should eq(:fact)
      node.importance.should eq(0.9)
    end

    it "manages children" do
      parent = Explanation::ExplanationNode.new("parent", :conclusion)
      child1 = Explanation::ExplanationNode.new("child1", :premise)
      child2 = Explanation::ExplanationNode.new("child2", :premise)

      parent.add_child(child1)
      parent.add_child(child2)

      parent.children.size.should eq(2)
      parent.leaf?.should be_false
      child1.leaf?.should be_true
    end

    it "stores metadata" do
      node = Explanation::ExplanationNode.new("content", :fact)
      node.set_metadata("source", "observation")

      node.metadata["source"].should eq("observation")
    end
  end

  describe Explanation::ExplanationGraph do
    it "creates explanation graph" do
      graph = Explanation::ExplanationGraph.new
      graph.root.should be_nil
      graph.size.should eq(0)
    end

    it "sets root node" do
      graph = Explanation::ExplanationGraph.new
      root = Explanation::ExplanationNode.new("conclusion", :conclusion)

      graph.set_root(root)

      graph.root.should eq(root)
      graph.size.should eq(1)
    end

    it "adds nodes with parent" do
      graph = Explanation::ExplanationGraph.new
      root = Explanation::ExplanationNode.new("conclusion", :conclusion)
      child = Explanation::ExplanationNode.new("premise", :premise)

      graph.set_root(root)
      graph.add_node(child, root.id)

      graph.size.should eq(2)
      root.children.should contain(child)
    end

    it "calculates depth" do
      graph = Explanation::ExplanationGraph.new
      root = Explanation::ExplanationNode.new("root", :conclusion)
      child = Explanation::ExplanationNode.new("child", :premise)
      grandchild = Explanation::ExplanationNode.new("grandchild", :fact)

      graph.set_root(root)
      graph.add_node(child, root.id)
      graph.add_node(grandchild, child.id)

      graph.depth.should eq(3)
    end

    it "generates natural language" do
      graph = Explanation::ExplanationGraph.new
      root = Explanation::ExplanationNode.new("X is true", :conclusion)
      premise = Explanation::ExplanationNode.new("Y implies X", :premise)

      graph.set_root(root)
      graph.add_node(premise, root.id)

      nl = graph.to_natural_language
      nl.should_not be_empty
    end
  end

  describe Explanation::CausalModel do
    it "creates causal model" do
      model = Explanation::CausalModel.new
      model.variables.should be_empty
      model.edges.should be_empty
    end

    it "adds variables and edges" do
      model = Explanation::CausalModel.new
      model.add_variable("rain", 0.0)
      model.add_variable("wet_grass", 0.0)
      model.add_edge("rain", "wet_grass", 0.9)

      model.variables.size.should eq(2)
      model.edges.size.should eq(1)
    end

    it "finds causes" do
      model = Explanation::CausalModel.new
      model.add_variable("rain")
      model.add_variable("sprinkler")
      model.add_variable("wet_grass")
      model.add_edge("rain", "wet_grass")
      model.add_edge("sprinkler", "wet_grass")

      causes = model.get_causes("wet_grass")
      causes.should contain("rain")
      causes.should contain("sprinkler")
    end

    it "finds effects" do
      model = Explanation::CausalModel.new
      model.add_variable("rain")
      model.add_variable("wet_grass")
      model.add_variable("slippery")
      model.add_edge("rain", "wet_grass")
      model.add_edge("wet_grass", "slippery")

      effects = model.get_effects("rain")
      effects.should eq(["wet_grass"])
    end

    it "performs intervention" do
      model = Explanation::CausalModel.new
      model.add_variable("X", 0.0)
      model.add_variable("Y", 0.0)
      model.add_edge("X", "Y", 2.0)

      result = model.intervene("X", 1.0)

      result["X"].should eq(1.0)
      result["Y"].should eq(2.0)
    end

    it "computes counterfactual" do
      model = Explanation::CausalModel.new
      model.add_variable("X", 0.0)
      model.add_variable("Y", 0.0)
      model.add_edge("X", "Y", 1.0)

      result = model.counterfactual("X", 1.0)

      result["Y"].should eq(1.0)
      # Original values should be restored
      model.variables["X"].value.should eq(0.0)
    end

    it "finds causal path" do
      model = Explanation::CausalModel.new
      model.add_variable("A")
      model.add_variable("B")
      model.add_variable("C")
      model.add_edge("A", "B")
      model.add_edge("B", "C")

      path = model.causal_path("A", "C")
      path.should_not be_nil
      path.not_nil!.should eq(["A", "B", "C"])
    end
  end

  describe Explanation::FeatureImportance do
    it "creates feature importance" do
      importance = Explanation::FeatureImportance.new("positive", 0.9)

      importance.prediction.should eq("positive")
      importance.confidence.should eq(0.9)
    end

    it "tracks feature contributions" do
      importance = Explanation::FeatureImportance.new("positive", 0.9)
      importance.set_importance("feature1", 0.4)
      importance.set_importance("feature2", 0.3)
      importance.set_importance("feature3", -0.2)

      importance.features.size.should eq(3)
    end

    it "gets top features" do
      importance = Explanation::FeatureImportance.new("result", 0.8)
      importance.set_importance("f1", 0.5)
      importance.set_importance("f2", 0.3)
      importance.set_importance("f3", 0.1)

      top = importance.top_features(2)
      top.size.should eq(2)
      top[0][0].should eq("f1")
    end

    it "separates positive and negative features" do
      importance = Explanation::FeatureImportance.new("result", 0.8)
      importance.set_importance("positive1", 0.4)
      importance.set_importance("positive2", 0.2)
      importance.set_importance("negative1", -0.3)

      positive = importance.positive_features
      negative = importance.negative_features

      positive.size.should eq(2)
      negative.size.should eq(1)
    end

    it "generates natural language" do
      importance = Explanation::FeatureImportance.new("positive", 0.85)
      importance.set_importance("feature1", 0.4)
      importance.set_importance("feature2", -0.1)

      nl = importance.to_natural_language

      nl.should contain("positive")
      nl.should contain("85")
      nl.should contain("feature1")
    end
  end

  describe Explanation::Explainer do
    it "creates explainer" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      explainer.traces.should be_empty
    end

    it "records reasoning trace" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      trace_id = explainer.start_trace("Is X a mammal?")
      explainer.record_step("Rule1", ["A"], "B", 0.9)
      explainer.record_step("Rule2", ["B"], "C", 0.85)
      trace = explainer.end_trace("X is a mammal", 0.8)

      trace.should_not be_nil
      trace.not_nil!.steps.size.should eq(2)
      trace.not_nil!.final_conclusion.should eq("X is a mammal")
    end

    it "retrieves trace by ID" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      trace_id = explainer.start_trace("query")
      explainer.end_trace("conclusion", 0.9)

      retrieved = explainer.get_trace(trace_id)
      retrieved.should_not be_nil
    end

    it "builds explanation graph" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      # Create a simple atom structure
      node1 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat")
      node2 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "mammal")
      link = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [node1, node2])

      graph = explainer.build_explanation_graph(link)

      graph.should_not be_nil
      graph.root.should_not be_nil
    end

    it "generates why explanation" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      node1 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat")
      node2 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "mammal")
      link = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [node1, node2])

      explanation = explainer.why(link)
      explanation.should_not be_empty
    end

    it "generates how explanation" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "test")

      explanation = explainer.how(node)
      explanation.should contain("Derivation")
    end

    it "generates what-if explanation" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      explainer.causal_model.add_variable("X")
      explainer.causal_model.add_variable("Y")
      explainer.causal_model.add_edge("X", "Y")

      explanation = explainer.what_if("X", 1.0)
      explanation.should contain("If")
    end

    it "converts atoms to natural language" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      concept = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
      nl = explainer.to_natural_language(concept)

      nl.should contain("concept")
      nl.should contain("dog")
    end

    it "explains inheritance links naturally" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      cat = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat")
      mammal = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "mammal")
      link = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [cat, mammal])

      nl = explainer.to_natural_language(link)
      nl.should contain("type of")
    end

    it "summarizes reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation::Explainer.new(atomspace)

      explainer.start_trace("test query")
      explainer.record_step("Rule", ["P"], "C", 0.9)
      explainer.end_trace("C", 0.9)

      summary = explainer.summarize("test")
      summary.should contain("test")
      summary.should contain("trace")
    end
  end

  describe Explanation::TracedInference do
    it "creates traced inference" do
      atomspace = AtomSpace::AtomSpace.new
      traced = Explanation::TracedInference.new(atomspace)

      traced.should_not be_nil
    end

    it "performs traced forward chaining" do
      atomspace = AtomSpace::AtomSpace.new
      traced = Explanation::TracedInference.new(atomspace)

      results = traced.forward_chain(5)
      # May be empty if no applicable rules
      results.should be_a(Array(AtomSpace::Atom))
    end

    it "explains last inference" do
      atomspace = AtomSpace::AtomSpace.new
      traced = Explanation::TracedInference.new(atomspace)

      traced.forward_chain(5)
      explanation = traced.explain_last_inference

      explanation.should be_a(String)
    end
  end

  describe "Module convenience methods" do
    it "creates explainer" do
      atomspace = AtomSpace::AtomSpace.new
      explainer = Explanation.create_explainer(atomspace)
      explainer.should_not be_nil
    end

    it "creates traced inference" do
      atomspace = AtomSpace::AtomSpace.new
      traced = Explanation.create_traced_inference(atomspace)
      traced.should_not be_nil
    end

    it "creates causal model" do
      model = Explanation.create_causal_model
      model.should_not be_nil
    end

    it "creates explanation graph" do
      graph = Explanation.create_explanation_graph
      graph.should_not be_nil
    end
  end
end
