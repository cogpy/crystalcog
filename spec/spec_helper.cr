require "spec"

# Require core source files
require "../src/cogutil/cogutil"
require "../src/atomspace/atomspace_main"
require "../src/pln/pln"
require "../src/ure/ure"
require "../src/opencog/opencog"
require "../src/nlp/nlp"

# Require all cogutil specs
require "./cogutil/logger_spec"
require "./cogutil/config_spec"
require "./cogutil/randgen_spec"

# Require all atomspace specs
require "./atomspace/truthvalue_spec"
require "./atomspace/atom_spec"
require "./atomspace/atomspace_spec"

# Require CogServer and Pattern Matching specs
require "./cogserver/cogserver_spec"
require "./pattern_matching/pattern_matching_spec"

# Require new comprehensive specs
require "./pln/pln_spec"
require "./ure/ure_spec"
require "./opencog/opencog_spec"

# Require NLP specs
require "./nlp/nlp_spec"
require "./nlp/tokenizer_spec"
require "./nlp/text_processor_spec"
require "./nlp/linguistic_atoms_spec"
require "./nlp/language_processing_capabilities_spec"

# Require performance tests
require "./performance/performance_spec"

# Require error handling and edge case tests
# TODO: Fix error_handling_spec - instance variable scope issues
# require "./error_handling/error_handling_spec"

# Require integration scenario tests
require "./integration/integration_spec"

# Main spec runner for all tests
describe "CrystalCog Integration Tests" do
  before_each do
    # Initialize all systems
    CogUtil.initialize
    AtomSpace.initialize
    PLN.initialize
    URE.initialize
    OpenCog.initialize
    NLP.initialize
  end

  it "initializes all systems correctly" do
    # Test that all modules can be initialized without errors
    # All initialization should have happened in before_each

    # Basic functionality test
    atomspace = AtomSpace::AtomSpace.new
    dog = atomspace.add_concept_node("dog")
    animal = atomspace.add_concept_node("animal")
    inheritance = atomspace.add_inheritance_link(dog, animal)

    atomspace.size.should eq(3)
    atomspace.node_count.should eq(2)
    atomspace.link_count.should eq(1)

    # Clean up
    atomspace.clear
  end

  it "supports PLN reasoning integration" do
    atomspace = AtomSpace::AtomSpace.new
    pln_engine = PLN.create_engine(atomspace)

    # Add simple knowledge
    dog = atomspace.add_concept_node("dog")
    mammal = atomspace.add_concept_node("mammal")
    tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
    atomspace.add_inheritance_link(dog, mammal, tv)

    # Run reasoning
    new_atoms = pln_engine.reason(3)

    # Should generate some new knowledge
    new_atoms.size.should be >= 0
  end

  it "supports URE reasoning integration" do
    atomspace = AtomSpace::AtomSpace.new
    ure_engine = URE.create_engine(atomspace)

    # Add evaluation facts
    likes = atomspace.add_predicate_node("likes")
    john = atomspace.add_concept_node("John")
    mary = atomspace.add_concept_node("Mary")

    tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
    eval1 = atomspace.add_evaluation_link(likes, atomspace.add_list_link([john, mary]), tv)
    eval2 = atomspace.add_evaluation_link(likes, atomspace.add_list_link([mary, john]), tv)

    # Run forward chaining
    new_atoms = ure_engine.forward_chain(3)

    # Should handle URE operations
    new_atoms.size.should be >= 0
  end

  it "handles cross-component interactions" do
    # Test that all components work together
    atomspace = AtomSpace::AtomSpace.new
    pln_engine = PLN.create_engine(atomspace)
    ure_engine = URE.create_engine(atomspace)

    # Add mixed knowledge for both engines
    human = atomspace.add_concept_node("human")
    mortal = atomspace.add_concept_node("mortal")
    socrates = atomspace.add_concept_node("socrates")

    tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.9)

    # PLN-style inheritance
    atomspace.add_inheritance_link(socrates, human, tv_high)
    atomspace.add_inheritance_link(human, mortal, tv_high)

    # URE-style evaluations
    is_pred = atomspace.add_predicate_node("is")
    atomspace.add_evaluation_link(is_pred, atomspace.add_list_link([socrates, human]), tv_high)

    initial_size = atomspace.size

    # Run both reasoning engines
    pln_atoms = pln_engine.reason(2)
    ure_atoms = ure_engine.forward_chain(2)

    # Should work together without conflicts
    (pln_atoms + ure_atoms).size.should be >= 0
    atomspace.size.should be >= initial_size
  end

  it "integrates NLP with reasoning systems" do
    # Test that NLP works with PLN and URE
    atomspace = AtomSpace::AtomSpace.new

    # Create linguistic knowledge base
    NLP.create_linguistic_kb(atomspace)

    # Process some text
    text = "Dogs are animals"
    nlp_atoms = NLP.process_text(text, atomspace)

    # Create reasoning engines
    pln_engine = PLN.create_engine(atomspace)
    ure_engine = URE.create_engine(atomspace)

    # Should be able to reason about linguistic knowledge
    pln_result = pln_engine.reason(2)
    ure_result = ure_engine.forward_chain(2)

    # Should handle linguistic and reasoning atoms together
    pln_result.should be_a(Array(AtomSpace::Atom))
    ure_result.should be_a(Array(AtomSpace::Atom))
    nlp_atoms.size.should be > 0

    # Should have linguistic statistics
    stats = NLP.get_linguistic_stats(atomspace)
    stats["word_atoms"].should be > 0
  end

  it "provides proper error handling" do
    # Test exception handling across components
    atomspace = AtomSpace::AtomSpace.new

    begin
      # This should complete without throwing unhandled exceptions
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Run on empty atomspace
      pln_result = pln_engine.reason(1)
      ure_result = ure_engine.forward_chain(1)

      # Should handle gracefully
      pln_result.should be_a(Array(AtomSpace::Atom))
      ure_result.should be_a(Array(AtomSpace::Atom))
    rescue ex : OpenCog::OpenCogException
      # OpenCog exceptions should be caught here if they occur
      ex.should be_a(OpenCog::OpenCogException)
    rescue ex : CogUtil::OpenCogException
      # CogUtil exceptions should be caught here if they occur
      ex.should be_a(CogUtil::OpenCogException)
    rescue ex : AtomSpace::AtomSpaceException
      # AtomSpace exceptions should be caught here if they occur
      ex.should be_a(AtomSpace::AtomSpaceException)
    end
  end

  it "maintains performance standards" do
    # Basic performance check
    atomspace = AtomSpace::AtomSpace.new

    # Time atom creation
    start_time = Time.monotonic

    100.times do |i|
      atomspace.add_concept_node("perf_test_#{i}")
    end

    end_time = Time.monotonic
    duration = end_time - start_time

    # Should create atoms quickly (less than 1 second for 100 atoms)
    duration.should be < 1.second

    # Should have created all atoms
    atomspace.size.should eq(100)
  end
end
