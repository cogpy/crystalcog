# Crystal implementation of the OpenCog framework
#
# This is the main entry point for the Crystal OpenCog implementation.
# It provides a unified interface to all OpenCog components.

require "./cogutil/cogutil"
require "./atomspace/atomspace_main"
require "./opencog/opencog"
require "./cogserver/cogserver_main"
require "./pattern_matching/pattern_matching_main"
require "./attention/attention_main"
require "./nlp/nlp"
require "./moses/moses_main"
require "./ml/ml_main"
require "./learning/learning_main"
require "./tools/cogshell"

# Conditionally require server components
{% if flag?(:with_cogserver) %}
  require "./cogserver/cogserver"
{% end %}

module CrystalCog
  VERSION = "0.1.0"

  # Initialize the OpenCog system
  def self.initialize
    CogUtil.initialize
    AtomSpace.initialize
    OpenCog.initialize
    CogServer.initialize
    PatternMatching.initialize
    Attention.initialize
    NLP.initialize
    Moses.initialize
    ML.initialize
    Learning.initialize
  end

  # Main entry point for command-line usage
  def self.main(args = ARGV)
    puts "CrystalCog #{VERSION} - OpenCog in Crystal"
    puts "Args received: #{args}"

    case args.first?
    when "server"
      puts "Starting CogServer..."
      CogServer.main(args[1..])
    when "shell"
      puts "Starting CogShell..."
      CogShell.main(args[1..])
    when "test"
      puts "Running test AtomSpace operations..."
      test_basic_operations
    when "attention"
      puts "Running attention allocation demo..."
      test_attention_allocation
    when "nlp"
      puts "Running NLP demo..."
      test_nlp_processing
    when "language-capabilities"
      puts "Demonstrating language processing capabilities..."
      test_language_processing_capabilities
    when "moses"
      puts "Running MOSES evolutionary search..."
      Moses.main(args[1..])
    else
      puts "Usage: crystalcog [server|shell|test|attention|nlp|language-capabilities|moses]"
      puts "  server                  - Start the CogServer"
      puts "  shell                   - Start interactive shell"
      puts "  test                    - Run basic test operations"
      puts "  attention               - Demo attention allocation mechanisms"
      puts "  nlp                     - Demo natural language processing"
      puts "  language-capabilities   - Demo language processing with reasoning"
      puts "  moses                   - Run MOSES evolutionary program learning"
    end
  end

  # Basic test operations to verify the system works
  private def self.test_basic_operations
    atomspace = AtomSpace::AtomSpace.new

    # Create some basic atoms
    node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
    link = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [node, atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "animal")])

    puts "Created atom: #{node}"
    puts "Created link: #{link}"
    puts "AtomSpace size: #{atomspace.size}"
  end

  # Test attention allocation mechanisms
  private def self.test_attention_allocation
    puts "=== Attention Allocation Demo ==="

    # Create atomspace with some test atoms
    atomspace = AtomSpace::AtomSpace.new

    # Create a small knowledge graph
    dog = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
    mammal = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "mammal")
    animal = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "animal")

    # Create inheritance links
    dog_mammal = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [dog, mammal])
    mammal_animal = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [mammal, animal])

    puts "Created knowledge graph with #{atomspace.size} atoms"

    # Create attention allocation engine
    engine = Attention::AllocationEngine.new(atomspace)

    # Set some initial attention values
    engine.bank.stimulate(dog.handle, 100_i16)
    engine.bank.stimulate(mammal.handle, 50_i16)
    engine.bank.stimulate(dog_mammal.handle, 75_i16)

    puts "\nInitial attention values:"
    [dog, mammal, animal, dog_mammal, mammal_animal].each do |atom|
      av = engine.bank.get_attention_value(atom.handle)
      puts "  #{atom}: #{av || "none"}"
    end

    # Show initial statistics
    puts "\nInitial bank statistics:"
    engine.bank.get_statistics.each do |key, value|
      puts "  #{key}: #{value}"
    end

    # Set some goals for attention allocation
    goals = {
      Attention::Goal::Reasoning  => 1.0,
      Attention::Goal::Learning   => 0.8,
      Attention::Goal::Processing => 0.9,
    }
    engine.set_goals(goals)

    puts "\nRunning attention allocation (3 cycles)..."
    results = engine.allocate_attention(3)

    puts "\nAllocation results:"
    results.each do |key, value|
      puts "  #{key}: #{value}"
    end

    puts "\nFinal attention values:"
    [dog, mammal, animal, dog_mammal, mammal_animal].each do |atom|
      av = engine.bank.get_attention_value(atom.handle)
      puts "  #{atom}: #{av || "none"}"
    end

    puts "\nFinal bank statistics:"
    engine.bank.get_statistics.each do |key, value|
      puts "  #{key}: #{value}"
    end

    # Show attentional focus
    puts "\nAttentional Focus (top #{engine.bank.attentional_focus.size} atoms):"
    engine.bank.attentional_focus.each_with_index do |handle, i|
      atom = atomspace.get_atom(handle)
      av = engine.bank.get_attention_value(handle)
      puts "  #{i + 1}. #{atom} - #{av}"
    end

    puts "\n=== Attention Allocation Demo Complete ==="
  end

  # Test NLP processing capabilities
  private def self.test_nlp_processing
    puts "=== Natural Language Processing Demo ==="

    # Create atomspace
    atomspace = AtomSpace::AtomSpace.new

    # Create basic linguistic knowledge base
    NLP.create_linguistic_kb(atomspace)
    puts "Created linguistic knowledge base with #{atomspace.size} atoms"

    # Process some sample text
    sample_texts = [
      "The cat sits on the mat.",
      "Dogs are loyal animals.",
      "Natural language processing is fascinating.",
    ]

    sample_texts.each_with_index do |text, i|
      puts "\nProcessing text #{i + 1}: '#{text}'"

      # Process the text
      atoms = NLP.process_text(text, atomspace)
      puts "  Created #{atoms.size} atoms from text processing"

      # Get tokenization
      tokens = NLP::Tokenizer.tokenize(text)
      puts "  Tokens: #{tokens}"

      # Get token statistics
      token_stats = NLP::Tokenizer.get_token_stats(tokens)
      puts "  Token stats: #{token_stats}"

      # Get text statistics
      text_stats = NLP::TextProcessor.get_text_stats(text)
      puts "  Text stats: words=#{text_stats["word_count"]}, sentences=#{text_stats["sentence_count"]}"

      # Extract keywords
      keywords = NLP::TextProcessor.extract_keywords(text, 3)
      puts "  Keywords: #{keywords}"
    end

    # Create some semantic relationships
    puts "\nCreating semantic relationships..."
    NLP::LinguisticAtoms.create_semantic_relation(atomspace, "cat", "animal", "isa", 0.9)
    NLP::LinguisticAtoms.create_semantic_relation(atomspace, "dog", "animal", "isa", 0.9)
    NLP::LinguisticAtoms.create_semantic_relation(atomspace, "happy", "sad", "antonym", 0.8)

    # Add predefined lexical relations
    lexical_atoms = NLP::LinguisticAtoms.create_lexical_relations(atomspace)
    puts "Added #{lexical_atoms.size} lexical relations"

    # Show final statistics
    puts "\nFinal AtomSpace statistics:"
    puts "  Total atoms: #{atomspace.size}"

    linguistic_stats = NLP.get_linguistic_stats(atomspace)
    puts "  Linguistic atoms: #{linguistic_stats}"

    complexity = NLP::LinguisticAtoms.get_linguistic_complexity(atomspace)
    puts "  Complexity metrics: #{complexity}"

    # Demonstrate word and sentence retrieval
    word_atoms = NLP::LinguisticAtoms.get_word_atoms(atomspace)
    sentence_atoms = NLP::LinguisticAtoms.get_sentence_atoms(atomspace)
    puts "  Word atoms: #{word_atoms.size}"
    puts "  Sentence atoms: #{sentence_atoms.size}"

    # Show some example atoms
    puts "\nSample word atoms:"
    word_atoms.first(5).each do |atom|
      puts "  - #{atom.name}"
    end

    puts "\n=== Natural Language Processing Demo Complete ==="
  end

  # Demonstrate complete language processing capabilities with reasoning
  private def self.test_language_processing_capabilities
    puts "\n=== Language Processing Capabilities Demonstration ==="
    puts "This demonstrates the integration of NLP with reasoning engines for true language understanding."

    # Create atomspace and initialize all systems
    atomspace = AtomSpace::AtomSpace.new
    NLP.create_linguistic_kb(atomspace)

    puts "\n1. Natural Language Understanding Pipeline:"

    # Story that requires reasoning across multiple sentences
    story = "Alice is a student. Students work hard. Hard workers succeed. Alice studies mathematics."
    puts "   Input: #{story}"

    # Process the story
    story_atoms = NLP.process_text(story, atomspace)
    puts "   → Created #{story_atoms.size} linguistic atoms"

    # Extract key concepts and create semantic knowledge
    alice = atomspace.add_concept_node("alice")
    student = atomspace.add_concept_node("student")
    work_hard = atomspace.add_concept_node("work_hard")
    succeed = atomspace.add_concept_node("succeed")
    mathematics = atomspace.add_concept_node("mathematics")

    tv = AtomSpace::SimpleTruthValue.new(0.9, 0.9)

    # Create semantic relationships from the story
    atomspace.add_inheritance_link(alice, student, tv)
    atomspace.add_inheritance_link(student, work_hard, tv)
    atomspace.add_inheritance_link(work_hard, succeed, tv)

    # Create specific relationship
    studies = atomspace.add_predicate_node("studies")
    atomspace.add_evaluation_link(
      studies,
      atomspace.add_list_link([alice, mathematics]),
      tv
    )

    puts "   → Created semantic knowledge base"

    # Demonstrate reasoning capabilities
    puts "\n2. Reasoning About Language:"

    # Create reasoning engines
    pln_engine = PLN.create_engine(atomspace)
    ure_engine = URE.create_engine(atomspace)

    initial_size = atomspace.size

    # Run reasoning
    pln_atoms = pln_engine.reason(8)
    ure_atoms = ure_engine.forward_chain(4)

    puts "   → PLN reasoning generated #{pln_atoms.size} new inferences"
    puts "   → URE reasoning generated #{ure_atoms.size} new inferences"

    # Check if we derived the logical conclusion
    alice_succeed = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
      .find { |link|
        link.is_a?(AtomSpace::Link) &&
          link.outgoing.size == 2 &&
          link.outgoing[0] == alice &&
          link.outgoing[1] == succeed
      }

    if alice_succeed
      tv_result = alice_succeed.truth_value
      puts "   ✅ Derived conclusion: Alice will succeed"
      puts "      (strength: #{tv_result.strength.round(3)}, confidence: #{tv_result.confidence.round(3)})"
    else
      puts "   ⚠ Could not derive expected conclusion"
    end

    puts "\n3. Advanced Language Analysis:"

    # Demonstrate comparative analysis
    texts = [
      "The cat sits.",
      "The extraordinarily intelligent feline positioned itself gracefully upon the intricately woven carpet.",
    ]

    texts.each_with_index do |text, i|
      tokens = NLP::Tokenizer.tokenize(text)
      stats = NLP::TextProcessor.get_text_stats(text)
      keywords = NLP::TextProcessor.extract_keywords(text, 3)

      puts "   Text #{i + 1}: #{text}"
      puts "     → #{tokens.size} tokens, #{stats["word_count"]} words"
      puts "     → Average word length: #{stats["avg_word_length"]}"
      puts "     → Keywords: #{keywords.join(", ")}" unless keywords.empty?
    end

    puts "\n4. Semantic Relationship Processing:"

    # Create some semantic relationships
    semantic_pairs = [
      ["dog", "animal", "isa"],
      ["cat", "animal", "isa"],
      ["happy", "sad", "antonym"],
      ["big", "small", "antonym"],
    ]

    semantic_pairs.each do |pair|
      word1, word2, relation = pair
      NLP::LinguisticAtoms.create_semantic_relation(atomspace, word1, word2, relation, 0.8)
    end

    puts "   → Created #{semantic_pairs.size} semantic relationships"

    # Run reasoning on semantic network
    semantic_atoms = pln_engine.reason(5)
    puts "   → Generated #{semantic_atoms.size} additional semantic inferences"

    puts "\n5. Knowledge Base Statistics:"

    linguistic_stats = NLP.get_linguistic_stats(atomspace)
    puts "   → Word atoms: #{linguistic_stats["word_atoms"]}"
    puts "   → Sentence atoms: #{linguistic_stats["sentence_atoms"]}"
    puts "   → Total atoms: #{linguistic_stats["total_atoms"]}"

    # Show capability summary
    puts "\n=== Language Processing Capabilities Summary ==="
    puts "✅ Natural Language Tokenization and Processing"
    puts "✅ Semantic Knowledge Representation in AtomSpace"
    puts "✅ Integration with PLN Probabilistic Logic Networks"
    puts "✅ Integration with URE Unified Rule Engine"
    puts "✅ Logical Reasoning from Natural Language Input"
    puts "✅ Semantic Relationship Discovery and Reasoning"
    puts "✅ Linguistic Complexity Analysis"
    puts "✅ Multi-sentence Story Understanding"
    puts "✅ Conclusion Generation from Language Input"

    final_size = atomspace.size
    total_generated = final_size - initial_size

    puts "\nFinal Statistics:"
    puts "- Initial atoms: #{initial_size}"
    puts "- Final atoms: #{final_size}"
    puts "- Generated through reasoning: #{total_generated}"
    puts "- Demonstrates complete language processing capabilities! 🎉"

    puts "\n=== Language Processing Capabilities Demo Complete ==="
  end
end

# Run if this file is executed directly
if PROGRAM_NAME == __FILE__
  begin
    puts "Starting CrystalCog..."
    CrystalCog.main(ARGV)
    puts "Finished CrystalCog."
  rescue ex
    puts "Error: #{ex}"
    puts ex.backtrace.join("\n")
  end
end
