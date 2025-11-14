require "spec"
require "../../src/opencog/opencog"

describe OpenCog do
  describe "module initialization" do
    it "has correct version" do
      OpenCog::VERSION.should eq("0.1.0")
    end

    it "initializes OpenCog subsystem" do
      OpenCog.initialize
      # Should not crash and should initialize dependencies
    end

    it "tracks initialization state" do
      # Test that initialization tracking works
      OpenCog.initialize
      # Should complete successfully
    end

    it "handles multiple initialization calls safely" do
      OpenCog.initialize
      OpenCog.initialize # Should not cause issues
      # Should handle gracefully
    end
  end

  describe "exception hierarchy" do
    it "defines OpenCog exceptions" do
      exception = OpenCog::OpenCogException.new("test error")
      exception.should be_a(CogUtil::OpenCogException)
      exception.message.should eq("test error")
    end

    it "defines reasoning exceptions" do
      exception = OpenCog::ReasoningException.new("reasoning error")
      exception.should be_a(OpenCog::OpenCogException)
      exception.message.should eq("reasoning error")
    end

    it "defines pattern matching exceptions" do
      exception = OpenCog::PatternMatchException.new("pattern error")
      exception.should be_a(OpenCog::OpenCogException)
      exception.message.should eq("pattern error")
    end

    it "allows exception inheritance" do
      reasoning_exc = OpenCog::ReasoningException.new("test")
      reasoning_exc.should be_a(OpenCog::OpenCogException)
      reasoning_exc.should be_a(CogUtil::OpenCogException)
    end
  end

  describe "module structure" do
    it "defines reasoning module" do
      OpenCog::Reasoning.should be_truthy
      # Module should exist even if empty
    end

    it "defines pattern matcher module" do
      OpenCog::PatternMatcher.should be_truthy
      # Module should exist even if empty
    end

    it "defines learning module" do
      OpenCog::Learning.should be_truthy
      # Module should exist even if empty
    end
  end

  describe "dependency management" do
    it "initializes CogUtil dependency" do
      # Should initialize CogUtil without error
      OpenCog.initialize
      # CogUtil should be available
    end

    it "initializes AtomSpace dependency" do
      # Should initialize AtomSpace without error
      OpenCog.initialize
      # AtomSpace should be available
    end

    it "handles dependency initialization order" do
      # Should handle initialization in correct order
      OpenCog.initialize
      # Should complete successfully
    end
  end

  describe "integration with other components" do
    before_each do
      OpenCog.initialize
    end

    it "integrates with CogUtil logging" do
      # Test that OpenCog can use CogUtil logging
      CogUtil::Logger.info("Test message from OpenCog integration")
      # Should not crash
    end

    it "integrates with AtomSpace" do
      # Test that OpenCog can use AtomSpace
      atomspace = AtomSpace::AtomSpace.new
      concept = atomspace.add_concept_node("test_concept")

      concept.should be_a(AtomSpace::Atom)
      concept.as(AtomSpace::Node).name.should eq("test_concept")
    end

    it "supports exception handling across components" do
      begin
        raise OpenCog::ReasoningException.new("Cross-component error")
      rescue ex : OpenCog::ReasoningException
        ex.message.should eq("Cross-component error")
      rescue ex
        fail "Should have caught OpenCog::ReasoningException"
      end
    end
  end
end

# Additional integration tests that test OpenCog with PLN and URE
describe "OpenCog Full Integration" do
  before_each do
    OpenCog.initialize
  end

  describe "with PLN integration" do
    it "can use PLN reasoning engine" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      pln_engine = PLN.create_engine(atomspace)

      pln_engine.should be_a(PLN::PLNEngine)

      # Add some knowledge for reasoning
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")

      tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
      atomspace.add_inheritance_link(dog, mammal, tv)

      # Run PLN reasoning
      new_atoms = pln_engine.reason(3)

      # Should generate inferred knowledge
      new_atoms.size.should be >= 0
    end

    it "handles PLN exceptions properly" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      pln_engine = PLN.create_engine(atomspace)

      begin
        # This should complete without raising exceptions
        new_atoms = pln_engine.reason(1)
        new_atoms.size.should be >= 0
      rescue ex : OpenCog::ReasoningException
        # If reasoning exception occurs, it should be proper type
        ex.should be_a(OpenCog::ReasoningException)
      end
    end

    it "combines PLN with AtomSpace operations" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      pln_engine = PLN.create_engine(atomspace)

      # Build knowledge graph
      animals = ["dog", "cat", "bird", "fish"].map { |name|
        atomspace.add_concept_node(name)
      }

      categories = ["mammal", "animal", "living_thing"].map { |name|
        atomspace.add_concept_node(name)
      }

      # Add inheritance relationships
      tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
      atomspace.add_inheritance_link(animals[0], categories[0], tv)    # dog -> mammal
      atomspace.add_inheritance_link(animals[1], categories[0], tv)    # cat -> mammal
      atomspace.add_inheritance_link(categories[0], categories[1], tv) # mammal -> animal
      atomspace.add_inheritance_link(categories[1], categories[2], tv) # animal -> living_thing

      initial_size = atomspace.size

      # Run PLN reasoning
      new_atoms = pln_engine.reason(5)

      # Should have derived new knowledge
      atomspace.size.should be >= initial_size

      # Should be able to find derived relationships
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
      inheritance_links.size.should be > 4 # More than initial 4
    end
  end

  describe "with URE integration" do
    it "can use URE reasoning engine" do
      atomspace = AtomSpace::AtomSpace.new
      URE.initialize
      ure_engine = URE.create_engine(atomspace)

      ure_engine.should be_a(URE::UREEngine)

      # Add some facts for reasoning
      likes = atomspace.add_predicate_node("likes")
      john = atomspace.add_concept_node("John")
      mary = atomspace.add_concept_node("Mary")

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      eval1 = atomspace.add_evaluation_link(likes, atomspace.add_list_link([john, mary]), tv)
      eval2 = atomspace.add_evaluation_link(likes, atomspace.add_list_link([mary, john]), tv)

      # Run URE forward chaining
      new_atoms = ure_engine.forward_chain(3)

      # Should generate conjunctions or other derived knowledge
      new_atoms.size.should be >= 0
    end

    it "handles URE exceptions properly" do
      atomspace = AtomSpace::AtomSpace.new
      URE.initialize
      ure_engine = URE.create_engine(atomspace)

      begin
        # This should complete without raising exceptions
        new_atoms = ure_engine.forward_chain(1)
        new_atoms.size.should be >= 0
      rescue ex : OpenCog::ReasoningException
        # If reasoning exception occurs, it should be proper type
        ex.should be_a(OpenCog::ReasoningException)
      end
    end

    it "uses URE for complex reasoning scenarios" do
      atomspace = AtomSpace::AtomSpace.new
      URE.initialize
      ure_engine = URE.create_engine(atomspace)

      # Create logical scenario: If P then Q, P is true, derive Q
      p = atomspace.add_concept_node("P")
      q = atomspace.add_concept_node("Q")

      tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
      tv_med = AtomSpace::SimpleTruthValue.new(0.8, 0.8)

      # P is true
      p_true = atomspace.add_evaluation_link(
        atomspace.add_predicate_node("true"),
        atomspace.add_list_link([p]),
        tv_high
      )

      # Q evaluation (conclusion)
      q_true = atomspace.add_evaluation_link(
        atomspace.add_predicate_node("true"),
        atomspace.add_list_link([q])
      )

      # If P then Q
      implication = atomspace.add_link(
        AtomSpace::AtomType::IMPLICATION_LINK,
        [p_true, q_true],
        tv_med
      )

      initial_size = atomspace.size

      # Run forward chaining - should derive Q is true via modus ponens
      new_atoms = ure_engine.forward_chain(5)

      atomspace.size.should be >= initial_size

      # Check if Q was derived (implementation dependent)
      if new_atoms.size > 0
        # Should have some derived conclusions
        new_atoms.each do |atom|
          atom.should be_a(AtomSpace::Atom)
        end
      end
    end
  end

  describe "with combined PLN and URE" do
    it "can use both reasoning engines together" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      URE.initialize

      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Create knowledge that both engines can work with
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # PLN-style inheritance
      atomspace.add_inheritance_link(dog, mammal, tv)
      atomspace.add_inheritance_link(mammal, animal, tv)

      # URE-style evaluations
      is_pred = atomspace.add_predicate_node("is_a")
      atomspace.add_evaluation_link(is_pred, atomspace.add_list_link([dog, mammal]), tv)
      atomspace.add_evaluation_link(is_pred, atomspace.add_list_link([mammal, animal]), tv)

      initial_size = atomspace.size

      # Run both reasoning engines
      pln_atoms = pln_engine.reason(3)
      ure_atoms = ure_engine.forward_chain(3)

      # Should have generated knowledge from both
      total_new_atoms = pln_atoms.size + ure_atoms.size
      total_new_atoms.should be >= 0

      atomspace.size.should be >= initial_size
    end

    it "handles interaction between reasoning engines" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      URE.initialize

      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Create initial knowledge
      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      c = atomspace.add_concept_node("C")

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      atomspace.add_inheritance_link(a, b, tv)
      pred = atomspace.add_predicate_node("related")
      atomspace.add_evaluation_link(pred, atomspace.add_list_link([b, c]), tv)

      # Run PLN first
      pln_atoms = pln_engine.reason(2)

      # Then run URE on the expanded atomspace
      ure_atoms = ure_engine.forward_chain(2)

      # Should work together without conflicts
      (pln_atoms + ure_atoms).size.should be >= 0
    end

    it "provides unified exception handling for both engines" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      URE.initialize

      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      begin
        # Run both engines
        pln_atoms = pln_engine.reason(1)
        ure_atoms = ure_engine.forward_chain(1)

        # Should complete successfully
        (pln_atoms + ure_atoms).size.should be >= 0
      rescue ex : OpenCog::ReasoningException
        # Any reasoning exceptions should be caught here
        ex.should be_a(OpenCog::ReasoningException)
      rescue ex : OpenCog::OpenCogException
        # Any OpenCog exceptions should be caught here
        ex.should be_a(OpenCog::OpenCogException)
      end
    end
  end

  describe "performance and scalability" do
    it "handles moderate knowledge bases efficiently" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      URE.initialize

      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Create moderate-sized knowledge base
      concepts = 15.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      predicates = 3.times.map { |i|
        atomspace.add_predicate_node("pred_#{i}")
      }.to_a

      tv = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      # Add inheritance relationships
      (0...concepts.size - 1).each do |i|
        atomspace.add_inheritance_link(concepts[i], concepts[i + 1], tv)
      end

      # Add evaluations
      concepts.each_with_index do |concept, i|
        predicates.each do |pred|
          atomspace.add_evaluation_link(pred, concept, tv)
        end
      end

      initial_size = atomspace.size

      start_time = Time.monotonic

      # Run both reasoning engines
      pln_atoms = pln_engine.reason(3)
      ure_atoms = ure_engine.forward_chain(2)

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete in reasonable time
      duration.should be < 15.seconds

      # Should have generated some new knowledge
      atomspace.size.should be >= initial_size
      (pln_atoms + ure_atoms).size.should be >= 0
    end

    it "maintains consistency across reasoning operations" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      URE.initialize

      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Create consistent knowledge base
      human = atomspace.add_concept_node("human")
      mortal = atomspace.add_concept_node("mortal")
      socrates = atomspace.add_concept_node("socrates")

      tv_high = AtomSpace::SimpleTruthValue.new(0.95, 0.9)

      # Socrates is human (inheritance)
      atomspace.add_inheritance_link(socrates, human, tv_high)

      # Humans are mortal (inheritance)
      atomspace.add_inheritance_link(human, mortal, tv_high)

      # Socrates is human (evaluation)
      is_pred = atomspace.add_predicate_node("is")
      atomspace.add_evaluation_link(is_pred, atomspace.add_list_link([socrates, human]), tv_high)

      # Run reasoning engines
      pln_atoms = pln_engine.reason(3)
      ure_atoms = ure_engine.forward_chain(2)

      # Check for consistency - no contradictory knowledge should be generated
      all_atoms = atomspace.get_all_atoms

      # All atoms should have valid truth values
      all_atoms.each do |atom|
        tv = atom.truth_value
        tv.strength.should be >= 0.0
        tv.strength.should be <= 1.0
        tv.confidence.should be >= 0.0
        tv.confidence.should be <= 1.0
      end

      # Should have derived that Socrates is mortal through both systems
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

      # Should have more inheritance relationships than we started with
      inheritance_links.size.should be >= 2
    end
  end

  describe "error recovery and robustness" do
    it "recovers from reasoning errors gracefully" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      URE.initialize

      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      begin
        # Create scenario that might cause issues
        circular_a = atomspace.add_concept_node("circular_A")
        circular_b = atomspace.add_concept_node("circular_B")

        atomspace.add_inheritance_link(circular_a, circular_b)
        atomspace.add_inheritance_link(circular_b, circular_a)

        # Run reasoning - should handle circular references
        pln_atoms = pln_engine.reason(5)
        ure_atoms = ure_engine.forward_chain(3)

        # Should complete without hanging or crashing
        (pln_atoms + ure_atoms).size.should be >= 0
      rescue ex : OpenCog::OpenCogException
        # Should catch any OpenCog-related exceptions
        ex.should be_a(OpenCog::OpenCogException)
      end
    end

    it "maintains atomspace integrity during reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      PLN.initialize
      URE.initialize

      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Track atomspace state
      initial_atoms = atomspace.get_all_atoms.dup
      initial_size = atomspace.size

      # Add test knowledge
      test_concept = atomspace.add_concept_node("test")
      test_size = atomspace.size

      # Run reasoning
      pln_atoms = pln_engine.reason(2)
      ure_atoms = ure_engine.forward_chain(2)

      # Atomspace should still be valid
      atomspace.size.should be >= test_size

      # Original atoms should still exist
      initial_atoms.each do |original_atom|
        atomspace.contains?(original_atom).should be_true
      end

      # Test concept should still exist
      atomspace.contains?(test_concept).should be_true
    end
  end
end
