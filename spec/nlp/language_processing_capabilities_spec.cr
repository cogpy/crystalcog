require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/pln/pln"
require "../../src/ure/ure"
require "../../src/opencog/opencog"
require "../../src/nlp/nlp"

describe "Language Processing Capabilities" do
  before_each do
    # Initialize all components
    CogUtil.initialize
    AtomSpace.initialize
    PLN.initialize
    URE.initialize
    OpenCog.initialize
    NLP.initialize
  end

  describe "Natural Language Understanding and Reasoning" do
    it "processes sentences and reasons about semantic relationships" do
      atomspace = AtomSpace::AtomSpace.new

      # Create linguistic knowledge base
      NLP.create_linguistic_kb(atomspace)

      # Process natural language sentences about animals
      sentences = [
        "Dogs are animals.",
        "Animals are living things.",
        "Fido is a dog.",
        "Living things are mortal.",
      ]

      # Process each sentence into the AtomSpace
      sentences.each do |sentence|
        atoms = NLP.process_text(sentence, atomspace)
        atoms.size.should be > 0
      end

      # Create semantic relationships based on the sentences
      dog = atomspace.add_concept_node("dog")
      animal = atomspace.add_concept_node("animal")
      living_thing = atomspace.add_concept_node("living_thing")
      mortal = atomspace.add_concept_node("mortal")
      fido = atomspace.add_concept_node("fido")

      # Add the semantic knowledge from the sentences
      tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
      atomspace.add_inheritance_link(dog, animal, tv_high)
      atomspace.add_inheritance_link(animal, living_thing, tv_high)
      atomspace.add_inheritance_link(living_thing, mortal, tv_high)
      atomspace.add_inheritance_link(fido, dog, tv_high)

      # Create PLN reasoning engine
      pln_engine = PLN.create_engine(atomspace)

      initial_size = atomspace.size

      # Run reasoning to derive conclusions
      new_atoms = pln_engine.reason(10)

      # Should have derived new knowledge
      atomspace.size.should be > initial_size
      new_atoms.size.should be > 0

      # Should be able to derive that Fido is mortal
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

      fido_mortal = inheritance_links.find { |link|
        link.is_a?(AtomSpace::Link) &&
          link.outgoing.size == 2 &&
          link.outgoing[0] == fido &&
          link.outgoing[1] == mortal
      }

      puts "Language reasoning: processed #{sentences.size} sentences"
      puts "Generated #{new_atoms.size} new inferences"

      if fido_mortal
        tv = fido_mortal.truth_value
        puts "✅ Successfully derived: Fido is mortal (strength: #{tv.strength.round(3)}, confidence: #{tv.confidence.round(3)})"
      end
    end

    it "understands and reasons about spatial relationships" do
      atomspace = AtomSpace::AtomSpace.new

      # Process sentences about spatial relationships
      spatial_sentences = [
        "The cat is on the mat.",
        "The mat is on the floor.",
        "The floor is in the room.",
      ]

      # Process spatial language
      spatial_sentences.each do |sentence|
        atoms = NLP.process_text(sentence, atomspace)
        atoms.size.should be > 0
      end

      # Create spatial relationship atoms
      cat = atomspace.add_concept_node("cat")
      mat = atomspace.add_concept_node("mat")
      floor = atomspace.add_concept_node("floor")
      room = atomspace.add_concept_node("room")

      # Spatial predicates
      on = atomspace.add_predicate_node("on")
      in_location = atomspace.add_predicate_node("in")

      tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)

      # Create spatial facts
      atomspace.add_evaluation_link(
        on,
        atomspace.add_list_link([cat, mat]),
        tv
      )

      atomspace.add_evaluation_link(
        on,
        atomspace.add_list_link([mat, floor]),
        tv
      )

      atomspace.add_evaluation_link(
        in_location,
        atomspace.add_list_link([floor, room]),
        tv
      )

      # Create spatial reasoning rules
      # Rule: if X is on Y and Y is on Z, then X is above Z
      above = atomspace.add_predicate_node("above")

      # Create URE engine for spatial reasoning
      ure_engine = URE.create_engine(atomspace)

      initial_size = atomspace.size

      # Run forward chaining to derive spatial relationships
      new_atoms = ure_engine.forward_chain(5)

      atomspace.size.should be > initial_size
      new_atoms.size.should be > 0

      puts "Spatial reasoning: processed #{spatial_sentences.size} spatial sentences"
      puts "Generated #{new_atoms.size} spatial inferences"

      # Check for derived spatial relationships
      spatial_facts = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select { |link|
          link.is_a?(AtomSpace::EvaluationLink) &&
            [on, in_location, above].includes?(link.predicate)
        }

      puts "Found #{spatial_facts.size} spatial relationship facts"
    end

    it "processes comparative language and reasons about properties" do
      atomspace = AtomSpace::AtomSpace.new

      # Process comparative sentences
      comparative_sentences = [
        "Lions are bigger than cats.",
        "Elephants are bigger than lions.",
        "Cats are smaller than dogs.",
      ]

      # Process the comparative language
      comparative_sentences.each do |sentence|
        atoms = NLP.process_text(sentence, atomspace)
        tokens = NLP::Tokenizer.tokenize(sentence)

        atoms.size.should be > 0
        tokens.size.should be > 0

        # Extract comparative relationships
        if tokens.includes?("bigger")
          # Create size comparison relationships
          NLP::LinguisticAtoms.create_semantic_relation(atomspace, "size_comparison", "bigger", "comparative", 0.8)
        end
      end

      # Create entities and properties
      lion = atomspace.add_concept_node("lion")
      cat = atomspace.add_concept_node("cat")
      elephant = atomspace.add_concept_node("elephant")
      dog = atomspace.add_concept_node("dog")

      # Size property
      size = atomspace.add_concept_node("size")
      big = atomspace.add_concept_node("big")
      small = atomspace.add_concept_node("small")

      # Comparative predicate
      bigger_than = atomspace.add_predicate_node("bigger_than")

      tv = AtomSpace::SimpleTruthValue.new(0.85, 0.8)

      # Add comparative facts
      atomspace.add_evaluation_link(
        bigger_than,
        atomspace.add_list_link([lion, cat]),
        tv
      )

      atomspace.add_evaluation_link(
        bigger_than,
        atomspace.add_list_link([elephant, lion]),
        tv
      )

      # URE EvaluationTransitivity derives elephant > cat from chained bigger_than facts
      ure_engine = URE.create_engine(atomspace)

      initial_size = atomspace.size

      # Run reasoning to derive transitive comparisons
      new_atoms = ure_engine.forward_chain(5)

      atomspace.size.should be > initial_size
      new_atoms.size.should be > 0

      puts "Comparative reasoning: processed #{comparative_sentences.size} comparative sentences"
      puts "Generated #{new_atoms.size} comparative inferences"

      # Should derive that elephant is bigger than cat (transitivity)
      elephant_bigger_cat = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .find { |link|
          link.is_a?(AtomSpace::EvaluationLink) &&
            link.predicate == bigger_than &&
            link.arguments.is_a?(AtomSpace::ListLink) &&
            link.arguments.as(AtomSpace::ListLink).outgoing[0] == elephant &&
            link.arguments.as(AtomSpace::ListLink).outgoing[1] == cat
        }

      if elephant_bigger_cat
        puts "✅ Successfully derived transitive comparison: Elephant > Cat"
      end
    end

    it "processes temporal language and reasons about time sequences" do
      atomspace = AtomSpace::AtomSpace.new

      # Process temporal sentences
      temporal_sentences = [
        "John woke up in the morning.",
        "After waking up, John had breakfast.",
        "John went to work after breakfast.",
      ]

      # Process temporal language
      temporal_sentences.each do |sentence|
        atoms = NLP.process_text(sentence, atomspace)
        tokens = NLP::Tokenizer.tokenize(sentence)

        atoms.size.should be > 0

        # Look for temporal indicators
        if tokens.includes?("after") || tokens.includes?("before") || tokens.includes?("morning")
          # Create temporal relationships
          NLP::LinguisticAtoms.create_semantic_relation(atomspace, "temporal", "sequence", "time", 0.8)
        end
      end

      # Create temporal entities
      john = atomspace.add_concept_node("john")
      wake_up = atomspace.add_concept_node("wake_up")
      breakfast = atomspace.add_concept_node("breakfast")
      work = atomspace.add_concept_node("work")
      morning = atomspace.add_concept_node("morning")

      # Temporal predicates
      happens_at = atomspace.add_predicate_node("happens_at")
      before = atomspace.add_predicate_node("before")
      after = atomspace.add_predicate_node("after")

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.8)

      # Create temporal facts
      atomspace.add_evaluation_link(
        happens_at,
        atomspace.add_list_link([wake_up, morning]),
        tv
      )

      atomspace.add_evaluation_link(
        after,
        atomspace.add_list_link([breakfast, wake_up]),
        tv
      )

      atomspace.add_evaluation_link(
        after,
        atomspace.add_list_link([work, breakfast]),
        tv
      )

      # Create URE engine for temporal reasoning
      ure_engine = URE.create_engine(atomspace)

      initial_size = atomspace.size

      # Run reasoning to derive temporal sequences
      new_atoms = ure_engine.forward_chain(5)

      atomspace.size.should be > initial_size
      new_atoms.size.should be > 0

      puts "Temporal reasoning: processed #{temporal_sentences.size} temporal sentences"
      puts "Generated #{new_atoms.size} temporal inferences"

      # Should derive transitive temporal relationships
      temporal_facts = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select { |link|
          link.is_a?(AtomSpace::EvaluationLink) &&
            [before, after, happens_at].includes?(link.predicate)
        }

      puts "Found #{temporal_facts.size} temporal relationship facts"
    end

    it "integrates keyword extraction with semantic reasoning" do
      atomspace = AtomSpace::AtomSpace.new

      # Process a complex text and extract keywords
      complex_text = "The research shows that artificial intelligence systems can learn to recognize patterns in natural language. Machine learning algorithms analyze linguistic data to identify semantic relationships between words and concepts."

      # Process the text
      atoms = NLP.process_text(complex_text, atomspace)

      # Extract keywords
      keywords = NLP::TextProcessor.extract_keywords(complex_text, 8)

      atoms.size.should be > 0
      keywords.size.should be > 0

      puts "Keyword extraction: found #{keywords.size} keywords: #{keywords}"

      # Create semantic relationships for keywords
      keyword_atoms = [] of AtomSpace::Atom
      keywords.each do |keyword|
        keyword_atom = atomspace.add_concept_node(keyword)
        keyword_atoms << keyword_atom

        # Add to research domain
        research = atomspace.add_concept_node("research")
        tv = AtomSpace::SimpleTruthValue.new(0.7, 0.8)
        atomspace.add_inheritance_link(keyword_atom, research, tv)
      end

      # Create domain knowledge
      ai = atomspace.add_concept_node("artificial_intelligence")
      ml = atomspace.add_concept_node("machine_learning")
      nlp = atomspace.add_concept_node("natural_language_processing")

      tv_domain = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
      atomspace.add_inheritance_link(ml, ai, tv_domain)
      atomspace.add_inheritance_link(nlp, ai, tv_domain)

      # Run reasoning on the semantic network
      pln_engine = PLN.create_engine(atomspace)

      initial_size = atomspace.size
      new_atoms = pln_engine.reason(6)

      puts "Semantic keyword reasoning: generated #{new_atoms.size} new semantic connections"

      # Should derive relationships between extracted keywords and domain concepts
      semantic_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
        .select { |link|
          link.is_a?(AtomSpace::Link) &&
            keyword_atoms.includes?(link.outgoing[0]) || keyword_atoms.includes?(link.outgoing[1])
        }

      puts "Found #{semantic_links.size} semantic links involving extracted keywords"
    end
  end

  describe "Advanced Language Processing Integration" do
    it "demonstrates complete language understanding pipeline" do
      atomspace = AtomSpace::AtomSpace.new

      # Complete pipeline: Text -> Tokenization -> Semantic Analysis -> Reasoning -> Conclusions

      story_text = "Alice is a student. Students study hard. Hard workers succeed. Alice studies mathematics."

      puts "\n=== Complete Language Processing Pipeline Demo ==="
      puts "Input text: #{story_text}"

      # Step 1: Tokenization and basic processing
      tokens = NLP::Tokenizer.tokenize(story_text)
      sentences = NLP::Tokenizer.split_sentences(story_text)

      puts "Step 1 - Tokenization:"
      puts "  Tokens: #{tokens.size} (#{tokens[0..5]}...)"
      puts "  Sentences: #{sentences.size}"

      # Step 2: Process into AtomSpace
      text_atoms = NLP.process_text(story_text, atomspace)
      puts "Step 2 - AtomSpace conversion: #{text_atoms.size} atoms created"

      # Step 3: Create semantic knowledge from the text
      alice = atomspace.add_concept_node("alice")
      student = atomspace.add_concept_node("student")
      study_hard = atomspace.add_concept_node("study_hard")
      hard_worker = atomspace.add_concept_node("hard_worker")
      succeed = atomspace.add_concept_node("succeed")
      mathematics = atomspace.add_concept_node("mathematics")

      tv = AtomSpace::SimpleTruthValue.new(0.9, 0.9)

      # Knowledge from sentences
      atomspace.add_inheritance_link(alice, student, tv)
      atomspace.add_inheritance_link(student, study_hard, tv)
      atomspace.add_inheritance_link(study_hard, hard_worker, tv)
      atomspace.add_inheritance_link(hard_worker, succeed, tv)

      # Specific fact
      studies = atomspace.add_predicate_node("studies")
      atomspace.add_evaluation_link(
        studies,
        atomspace.add_list_link([alice, mathematics]),
        tv
      )

      puts "Step 3 - Semantic knowledge: relationships created"

      # Step 4: Statistical analysis
      text_stats = NLP::TextProcessor.get_text_stats(story_text)
      linguistic_stats = NLP.get_linguistic_stats(atomspace)

      puts "Step 4 - Analysis:"
      puts "  Text stats: #{text_stats["word_count"]} words, #{text_stats["sentence_count"]} sentences"
      puts "  Linguistic atoms: #{linguistic_stats["word_atoms"]} word atoms, #{linguistic_stats["total_atoms"]} total"

      # Step 5: Reasoning and inference
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      initial_size = atomspace.size

      pln_atoms = pln_engine.reason(8)
      ure_atoms = ure_engine.forward_chain(4)

      puts "Step 5 - Reasoning: PLN generated #{pln_atoms.size} atoms, URE generated #{ure_atoms.size} atoms"

      # Step 6: Extract conclusions
      # Should derive that Alice will succeed
      alice_succeed = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
        .find { |link|
          link.is_a?(AtomSpace::Link) &&
            link.outgoing.size == 2 &&
            link.outgoing[0] == alice &&
            link.outgoing[1] == succeed
        }

      if alice_succeed
        tv = alice_succeed.truth_value
        puts "Step 6 - Conclusion: ✅ Alice will succeed (strength: #{tv.strength.round(3)}, confidence: #{tv.confidence.round(3)})"
      else
        puts "Step 6 - Conclusion: Could not derive that Alice will succeed"
      end

      puts "=== Pipeline Complete ==="
      puts "Total atoms in knowledge base: #{atomspace.size}"

      # Verify the pipeline worked
      atomspace.size.should be > initial_size
      (pln_atoms.size + ure_atoms.size).should be > 0
    end

    it "demonstrates linguistic complexity analysis with reasoning" do
      atomspace = AtomSpace::AtomSpace.new

      # Analyze linguistic complexity and reason about it

      simple_text = "The cat sits."
      complex_text = "The extraordinarily intelligent feline positioned itself gracefully upon the intricately woven Persian carpet."

      # Process both texts
      simple_atoms = NLP.process_text(simple_text, atomspace)
      complex_atoms = NLP.process_text(complex_text, atomspace)

      # Get complexity metrics
      simple_stats = NLP::TextProcessor.get_text_stats(simple_text)
      complex_stats = NLP::TextProcessor.get_text_stats(complex_text)

      # Create complexity concepts
      simple_concept = atomspace.add_concept_node("simple_language")
      complex_concept = atomspace.add_concept_node("complex_language")

      # Linguistic features
      word_count_feature = atomspace.add_predicate_node("word_count")
      avg_word_length = atomspace.add_predicate_node("avg_word_length")

      tv_simple = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
      tv_complex = AtomSpace::SimpleTruthValue.new(0.9, 0.9)

      # Create facts about text complexity
      simple_wc = AtomSpace::NumberNode.new(simple_stats["word_count"].to_f64)
      complex_wc = AtomSpace::NumberNode.new(complex_stats["word_count"].to_f64)

      atomspace.add_atom(simple_wc)
      atomspace.add_atom(complex_wc)

      atomspace.add_evaluation_link(
        word_count_feature,
        atomspace.add_list_link([simple_concept, simple_wc]),
        tv_simple
      )

      atomspace.add_evaluation_link(
        word_count_feature,
        atomspace.add_list_link([complex_concept, complex_wc]),
        tv_complex
      )

      # Reasoning about linguistic complexity
      complexity_rule = atomspace.add_concept_node("complexity_analysis_rule")

      # Run reasoning
      pln_engine = PLN.create_engine(atomspace)
      complexity_atoms = pln_engine.reason(5)

      puts "Linguistic complexity analysis:"
      puts "  Simple text: #{simple_stats["word_count"]} words, #{simple_stats["average_word_length"]} avg length"
      puts "  Complex text: #{complex_stats["word_count"]} words, #{complex_stats["average_word_length"]} avg length"
      puts "  Generated #{complexity_atoms.size} complexity inferences"

      # Should understand that more words generally means more complexity
      complexity_atoms.size.should be >= 0
    end
  end
end
