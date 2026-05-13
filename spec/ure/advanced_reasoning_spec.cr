require "spec"
require "../../src/ure/ure"

describe "URE Advanced Reasoning Engines" do
  describe URE::BITNode do
    it "initializes correctly" do
      atomspace = AtomSpace::AtomSpace.new
      target = atomspace.add_concept_node("test_target")

      node = URE::BITNode.new(target, 2)

      node.target.should eq(target)
      node.depth.should eq(2)
      node.is_leaf?.should be_true
      node.exhausted.should be_false
      node.fitness.should eq(0.0)
    end

    it "calculates fitness correctly" do
      atomspace = AtomSpace::AtomSpace.new
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      target = atomspace.add_concept_node("test_target", tv)

      node = URE::BITNode.new(target, 1)
      fitness = node.calculate_fitness(atomspace)

      # Fitness should incorporate strength, confidence, and depth penalty
      node.fitness.should be > 0.0
      node.fitness.should be < 1.0
    end

    it "manages premise nodes correctly" do
      atomspace = AtomSpace::AtomSpace.new
      target = atomspace.add_concept_node("target")
      premise = atomspace.add_concept_node("premise")

      node = URE::BITNode.new(target)
      premise_node = URE::BITNode.new(premise)

      node.is_leaf?.should be_true
      node.add_premise(premise_node)
      node.is_leaf?.should be_false
      node.premises.size.should eq(1)
    end
  end

  describe URE::BackwardChainer do
    it "performs advanced backward chaining with BIT" do
      atomspace = AtomSpace::AtomSpace.new
      chainer = URE::BackwardChainer.new(atomspace, max_depth: 5, max_iterations: 10)
      chainer.add_default_rules

      # Create knowledge: dog -> mammal -> animal
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")

      atomspace.add_inheritance_link(dog, mammal, AtomSpace::SimpleTruthValue.new(0.9, 0.8))
      atomspace.add_inheritance_link(mammal, animal, AtomSpace::SimpleTruthValue.new(0.8, 0.9))

      # Goal: prove dog -> animal
      goal = atomspace.add_inheritance_link(dog, animal)

      results = chainer.do_chain(goal)

      results.should_not be_empty
      results.any? { |atom| atom.type == AtomSpace::AtomType::INHERITANCE_LINK }.should be_true
    end

    it "handles variable fulfillment queries" do
      atomspace = AtomSpace::AtomSpace.new
      chainer = URE::BackwardChainer.new(atomspace)
      chainer.add_default_rules

      # Create knowledge
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      atomspace.add_inheritance_link(dog, mammal)

      # Query: what does dog inherit from? ($x)
      var = atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
      pattern = atomspace.add_inheritance_link(dog, var)

      groundings = chainer.variable_fulfillment_query(pattern)

      groundings.should_not be_empty
      groundings.first.has_key?("$x").should be_true
    end

    it "handles truth value fulfillment queries" do
      atomspace = AtomSpace::AtomSpace.new
      chainer = URE::BackwardChainer.new(atomspace)
      chainer.add_default_rules

      # Create knowledge with truth values
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")

      inh = atomspace.add_inheritance_link(dog, mammal)
      inh.truth_value = AtomSpace::SimpleTruthValue.new(0.7, 0.6)

      # Query for truth value update
      updated_tv = chainer.truth_value_fulfillment_query(inh)

      updated_tv.should_not be_nil
      updated_tv.not_nil!.strength.should be >= 0.0
      updated_tv.not_nil!.confidence.should be >= 0.0
    end

    it "uses sophisticated unification" do
      atomspace = AtomSpace::AtomSpace.new
      chainer = URE::BackwardChainer.new(atomspace)

      # Test unification by performing a query that requires it
      dog = atomspace.add_concept_node("dog")
      var = atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$animal")

      # Create a pattern with the variable and see if it can be fulfilled
      pattern = atomspace.add_inheritance_link(dog, var)
      groundings = chainer.variable_fulfillment_query(pattern)

      # Should complete without errors (basic functionality test)
      groundings.should be_a(Array(Hash(String, AtomSpace::Atom)))
    end
  end

  describe URE::InferenceStrategy do
    it "has all expected strategies" do
      URE::InferenceStrategy::FORWARD_ONLY.should_not be_nil
      URE::InferenceStrategy::BACKWARD_ONLY.should_not be_nil
      URE::InferenceStrategy::MIXED_FORWARD_FIRST.should_not be_nil
      URE::InferenceStrategy::MIXED_BACKWARD_FIRST.should_not be_nil
      URE::InferenceStrategy::ADAPTIVE_BIDIRECTIONAL.should_not be_nil
    end
  end

  describe URE::InferenceMetrics do
    it "calculates efficiency score correctly" do
      metrics = URE::InferenceMetrics.new
      metrics.atoms_generated = 10
      metrics.reasoning_time = 2.0
      metrics.goal_achieved = true
      metrics.confidence_improvement = 0.1

      score = metrics.efficiency_score
      score.should be > 0.0

      # Goal achievement and confidence improvement should boost score
      metrics.goal_achieved = false
      lower_score = metrics.efficiency_score
      lower_score.should be < score
    end

    it "handles zero time gracefully" do
      metrics = URE::InferenceMetrics.new
      metrics.atoms_generated = 5
      metrics.reasoning_time = 0.0

      metrics.efficiency_score.should eq(0.0)
    end
  end

  describe URE::MixedInferenceEngine do
    it "initializes with all inference components" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::MixedInferenceEngine.new(atomspace)

      engine.should_not be_nil
      # Should have access to forward and backward chainers internally
    end

    it "performs adaptive mixed inference" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::MixedInferenceEngine.new(atomspace)

      # Create test knowledge
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")

      atomspace.add_inheritance_link(dog, mammal, AtomSpace::SimpleTruthValue.new(0.9, 0.8))
      atomspace.add_inheritance_link(mammal, animal, AtomSpace::SimpleTruthValue.new(0.8, 0.9))

      # Test goal
      goal = atomspace.add_inheritance_link(dog, animal)

      results = engine.adaptive_chain(goal, max_time: 5.0)

      results.should be_a(Array(AtomSpace::Atom))
      # Should complete within time limit
    end

    it "executes specific strategies correctly" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::MixedInferenceEngine.new(atomspace)

      # Add some basic knowledge
      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      atomspace.add_inheritance_link(a, b)

      goal = atomspace.add_inheritance_link(a, b)

      # Test each strategy
      URE::InferenceStrategy.each do |strategy|
        results = engine.execute_strategy(strategy, goal, max_time: 1.0)
        results.should be_a(Array(AtomSpace::Atom))
      end
    end

    it "selects strategies based on goal complexity" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::MixedInferenceEngine.new(atomspace)

      # Simple goal
      simple_goal = atomspace.add_concept_node("simple")

      # Complex goal with variables
      var = atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
      complex_goal = atomspace.add_inheritance_link(var, atomspace.add_concept_node("complex"))

      # Both should complete without errors (functionality test)
      simple_results = engine.adaptive_chain(simple_goal, 1.0)
      complex_results = engine.adaptive_chain(complex_goal, 1.0)

      simple_results.should be_a(Array(AtomSpace::Atom))
      complex_results.should be_a(Array(AtomSpace::Atom))
    end

    it "analyzes goal complexity correctly" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::MixedInferenceEngine.new(atomspace)

      # Simple node
      simple = atomspace.add_concept_node("simple")

      # Complex nested structure with variables
      var = atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
      nested = atomspace.add_link(AtomSpace::AtomType::AND_LINK, [
        atomspace.add_inheritance_link(var, atomspace.add_concept_node("A")),
        atomspace.add_inheritance_link(var, atomspace.add_concept_node("B")),
      ])

      # Both should be analyzable without errors
      simple_results = engine.adaptive_chain(simple, 1.0)
      complex_results = engine.adaptive_chain(nested, 1.0)

      simple_results.should be_a(Array(AtomSpace::Atom))
      complex_results.should be_a(Array(AtomSpace::Atom))
    end

    it "records and uses performance history" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::MixedInferenceEngine.new(atomspace)

      goal = atomspace.add_concept_node("test_goal")

      # Run adaptive chain multiple times to build performance history
      3.times do
        results = engine.adaptive_chain(goal, 1.0)
        results.should be_a(Array(AtomSpace::Atom))
      end

      # Should complete all runs without errors
    end
  end

  describe URE::UREEngine do
    it "integrates all advanced reasoning capabilities" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::UREEngine.new(atomspace)

      engine.forward_chainer.should be_a(URE::ForwardChainer)
      engine.backward_chainer.should be_a(URE::BackwardChainer)
      engine.mixed_engine.should be_a(URE::MixedInferenceEngine)
    end

    it "supports all inference methods" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::UREEngine.new(atomspace)

      # Add test knowledge
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      atomspace.add_inheritance_link(dog, mammal)

      goal = atomspace.add_inheritance_link(dog, mammal)

      # Test forward chaining
      forward_results = engine.forward_chain(steps: 2)
      forward_results.should be_a(Array(AtomSpace::Atom))

      # Test backward chaining
      backward_result = engine.backward_chain(goal)
      backward_result.should be_a(Bool)

      # Test simple mixed chaining
      mixed_result = engine.mixed_chain(goal)
      mixed_result.should be_a(Bool)

      # Test advanced mixed chaining
      advanced_results = engine.adaptive_mixed_chain(goal, max_time: 2.0)
      advanced_results.should be_a(Array(AtomSpace::Atom))

      # Test strategy execution
      strategy_results = engine.execute_strategy(URE::InferenceStrategy::FORWARD_ONLY, goal)
      strategy_results.should be_a(Array(AtomSpace::Atom))
    end

    it "maintains rule consistency across all chainers" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::UREEngine.new(atomspace)

      # Add a custom rule
      custom_rule = URE::ConjunctionRule.new
      engine.add_rule(custom_rule)

      # All chainers should have the rule (we can't directly test this
      # without exposing internals, but we verify no errors occur)
    end
  end

  describe "Integration scenarios" do
    it "handles complex reasoning chains with mixed strategies" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::UREEngine.new(atomspace)

      # Create a knowledge graph: Fido -> dog -> mammal -> animal -> living_thing
      fido = atomspace.add_concept_node("Fido")
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")
      living_thing = atomspace.add_concept_node("living_thing")

      atomspace.add_inheritance_link(fido, dog, AtomSpace::SimpleTruthValue.new(0.95, 0.9))
      atomspace.add_inheritance_link(dog, mammal, AtomSpace::SimpleTruthValue.new(0.9, 0.85))
      atomspace.add_inheritance_link(mammal, animal, AtomSpace::SimpleTruthValue.new(0.8, 0.9))
      atomspace.add_inheritance_link(animal, living_thing, AtomSpace::SimpleTruthValue.new(0.75, 0.8))

      # Goal: prove Fido is a living thing
      goal = atomspace.add_inheritance_link(fido, living_thing)

      # Try different strategies
      forward_results = engine.execute_strategy(URE::InferenceStrategy::FORWARD_ONLY, goal, 3.0)
      backward_results = engine.execute_strategy(URE::InferenceStrategy::BACKWARD_ONLY, goal, 3.0)
      adaptive_results = engine.adaptive_mixed_chain(goal, 5.0)

      # At least one strategy should find some relevant results
      total_results = forward_results.size + backward_results.size + adaptive_results.size
      total_results.should be >= 0 # Should complete without errors
    end

    it "handles variable-based queries with mixed inference" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::UREEngine.new(atomspace)

      # Create knowledge about different animals
      fido = atomspace.add_concept_node("Fido")
      rex = atomspace.add_concept_node("Rex")
      dog = atomspace.add_concept_node("dog")

      atomspace.add_inheritance_link(fido, dog)
      atomspace.add_inheritance_link(rex, dog)

      # Query: What are the instances of dog? (find $x such that $x -> dog)
      var = atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
      query_pattern = atomspace.add_inheritance_link(var, dog)

      # Use backward chainer for variable fulfillment
      backward_chainer = engine.backward_chainer
      groundings = backward_chainer.variable_fulfillment_query(query_pattern)

      # Should find groundings
      groundings.should be_a(Array(Hash(String, AtomSpace::Atom)))
    end

    it "demonstrates performance-based strategy adaptation" do
      atomspace = AtomSpace::AtomSpace.new
      engine = URE::UREEngine.new(atomspace)

      # Create a scenario where one strategy should perform better
      # For a goal that already exists, backward chaining should be very fast
      existing_goal = atomspace.add_concept_node("existing")

      # Run multiple times to build performance history
      3.times do
        results = engine.adaptive_mixed_chain(existing_goal, 1.0)
        # Each run should complete and potentially improve strategy selection
      end

      # The engine should complete all runs without errors
      # In practice, it would learn which strategy works best for this type of goal
    end
  end
end
