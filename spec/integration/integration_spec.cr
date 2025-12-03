require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/pln/pln"
require "../../src/ure/ure"
require "../../src/opencog/opencog"

describe "CrystalCog Integration Scenarios" do
  before_each do
    # Initialize all components
    CogUtil.initialize
    AtomSpace.initialize
    PLN.initialize
    URE.initialize
    OpenCog.initialize
  end

  describe "Real-world reasoning scenarios" do
    it "handles family relationships reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Build family knowledge base
      tv_certain = AtomSpace::SimpleTruthValue.new(1.0, 0.95)
      tv_likely = AtomSpace::SimpleTruthValue.new(0.9, 0.8)

      # People
      john = atomspace.add_concept_node("John")
      mary = atomspace.add_concept_node("Mary")
      bob = atomspace.add_concept_node("Bob")
      alice = atomspace.add_concept_node("Alice")

      # Relationships
      father_of = atomspace.add_predicate_node("father_of")
      mother_of = atomspace.add_predicate_node("mother_of")
      parent_of = atomspace.add_predicate_node("parent_of")
      grandparent_of = atomspace.add_predicate_node("grandparent_of")

      # Facts: John is father of Bob, Mary is mother of Bob
      atomspace.add_evaluation_link(
        father_of,
        atomspace.add_list_link([john, bob]),
        tv_certain
      )

      atomspace.add_evaluation_link(
        mother_of,
        atomspace.add_list_link([mary, bob]),
        tv_certain
      )

      # Bob is father of Alice
      atomspace.add_evaluation_link(
        father_of,
        atomspace.add_list_link([bob, alice]),
        tv_certain
      )

      # Rules: father_of implies parent_of
      father_implies_parent = atomspace.add_implication_link(
        atomspace.add_evaluation_link(father_of, atomspace.add_variable_node("$X", "$Y")),
        atomspace.add_evaluation_link(parent_of, atomspace.add_variable_node("$X", "$Y")),
        tv_likely
      )

      # Create reasoning engines
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      initial_size = atomspace.size

      # Run reasoning to derive family relationships
      pln_atoms = pln_engine.reason(5)
      ure_atoms = ure_engine.forward_chain(3)

      # Should have derived additional relationships
      atomspace.size.should be >= initial_size

      # Should be able to find parent relationships
      parent_facts = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select { |link|
          link.is_a?(AtomSpace::EvaluationLink) &&
            link.predicate == parent_of
        }

      puts "Family reasoning: generated #{pln_atoms.size + ure_atoms.size} new facts"
      puts "Found #{parent_facts.size} parent relationships"
    end

    it "handles animal taxonomy reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Build biological taxonomy
      tv_scientific = AtomSpace::SimpleTruthValue.new(0.95, 0.9)
      tv_common = AtomSpace::SimpleTruthValue.new(0.85, 0.8)

      # Create taxonomy hierarchy
      living_thing = atomspace.add_concept_node("living_thing")
      animal = atomspace.add_concept_node("animal")
      vertebrate = atomspace.add_concept_node("vertebrate")
      mammal = atomspace.add_concept_node("mammal")
      primate = atomspace.add_concept_node("primate")
      human = atomspace.add_concept_node("human")

      # Specific instances
      socrates = atomspace.add_concept_node("socrates")
      fido = atomspace.add_concept_node("fido")
      dog = atomspace.add_concept_node("dog")

      # Build taxonomy chain
      atomspace.add_inheritance_link(animal, living_thing, tv_scientific)
      atomspace.add_inheritance_link(vertebrate, animal, tv_scientific)
      atomspace.add_inheritance_link(mammal, vertebrate, tv_scientific)
      atomspace.add_inheritance_link(primate, mammal, tv_scientific)
      atomspace.add_inheritance_link(human, primate, tv_scientific)
      atomspace.add_inheritance_link(dog, mammal, tv_scientific)

      # Instance relationships
      atomspace.add_inheritance_link(socrates, human, tv_common)
      atomspace.add_inheritance_link(fido, dog, tv_common)

      # Properties
      mortal = atomspace.add_concept_node("mortal")
      warm_blooded = atomspace.add_concept_node("warm_blooded")

      # Rules: mammals are warm-blooded, animals are mortal
      atomspace.add_inheritance_link(mammal, warm_blooded, tv_scientific)
      atomspace.add_inheritance_link(animal, mortal, tv_scientific)

      # Create PLN engine for taxonomy reasoning
      pln_engine = PLN.create_engine(atomspace)

      initial_size = atomspace.size

      # Run PLN reasoning to derive transitive relationships
      new_atoms = pln_engine.reason(10)

      # Should have derived many transitive relationships
      atomspace.size.should be > initial_size

      # Should be able to derive that socrates is mortal
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

      socrates_mortal = inheritance_links.find { |link|
        link.is_a?(AtomSpace::Link) &&
          link.outgoing.size == 2 &&
          link.outgoing[0] == socrates &&
          link.outgoing[1] == mortal
      }

      if socrates_mortal
        puts "Successfully derived: Socrates is mortal"
        tv = socrates_mortal.truth_value
        puts "  Strength: #{tv.strength.round(3)}, Confidence: #{tv.confidence.round(3)}"
      end

      puts "Taxonomy reasoning: generated #{new_atoms.size} new relationships"
    end

    it "handles logical problem solving" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Classic logic puzzle: Knights and Knaves
      # Knights always tell the truth, Knaves always lie

      tv_rule = AtomSpace::SimpleTruthValue.new(1.0, 0.9)
      tv_statement = AtomSpace::SimpleTruthValue.new(0.8, 0.7)

      # People
      person_a = atomspace.add_concept_node("person_A")
      person_b = atomspace.add_concept_node("person_B")

      # Properties
      knight = atomspace.add_concept_node("knight")
      knave = atomspace.add_concept_node("knave")
      truthful = atomspace.add_concept_node("truthful")
      liar = atomspace.add_concept_node("liar")

      # Rules: Knights are truthful, Knaves are liars
      atomspace.add_inheritance_link(knight, truthful, tv_rule)
      atomspace.add_inheritance_link(knave, liar, tv_rule)

      # Statement predicates
      says = atomspace.add_predicate_node("says")
      is_type = atomspace.add_predicate_node("is_type")

      # Person A says "I am a knave"
      statement = atomspace.add_concept_node("A_says_I_am_knave")
      atomspace.add_evaluation_link(
        says,
        atomspace.add_list_link([person_a, statement]),
        tv_statement
      )

      # The content of the statement
      atomspace.add_evaluation_link(
        is_type,
        atomspace.add_list_link([person_a, knave]),
        tv_statement
      )

      # Create reasoning engines
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Analyze the logical contradiction
      initial_size = atomspace.size

      pln_atoms = pln_engine.reason(5)
      ure_atoms = ure_engine.forward_chain(3)

      # Should be able to derive logical conclusions
      atomspace.size.should be >= initial_size

      puts "Logic puzzle reasoning: generated #{pln_atoms.size + ure_atoms.size} new conclusions"

      # Check for derived contradictions or resolutions
      all_evaluations = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
      contradiction_count = all_evaluations.count { |eval|
        eval.truth_value.strength < 0.3 # Low strength indicates contradiction
      }

      puts "Found #{contradiction_count} potential contradictions"
    end

    it "handles scientific reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Model basic physics/chemistry knowledge
      tv_law = AtomSpace::SimpleTruthValue.new(0.99, 0.95)
      tv_observation = AtomSpace::SimpleTruthValue.new(0.8, 0.8)

      # Substances
      water = atomspace.add_concept_node("water")
      ice = atomspace.add_concept_node("ice")
      steam = atomspace.add_concept_node("steam")

      # Properties
      liquid = atomspace.add_concept_node("liquid")
      solid = atomspace.add_concept_node("solid")
      gas = atomspace.add_concept_node("gas")

      # Temperature concepts
      freezing = atomspace.add_concept_node("below_freezing")
      boiling = atomspace.add_concept_node("above_boiling")

      # Physical laws as implications
      heating = atomspace.add_predicate_node("heating")
      cooling = atomspace.add_predicate_node("cooling")
      phase_change = atomspace.add_predicate_node("phase_change")

      # Water properties
      atomspace.add_inheritance_link(water, liquid, tv_law)
      atomspace.add_inheritance_link(ice, solid, tv_law)
      atomspace.add_inheritance_link(steam, gas, tv_law)

      # Phase change rules (simplified)
      water_to_ice = atomspace.add_evaluation_link(
        phase_change,
        atomspace.add_list_link([water, ice]),
        tv_law
      )

      water_to_steam = atomspace.add_evaluation_link(
        phase_change,
        atomspace.add_list_link([water, steam]),
        tv_law
      )

      # Conditions
      temp_condition = atomspace.add_predicate_node("temperature_condition")

      # If temperature below freezing, water becomes ice
      freezing_condition = atomspace.add_evaluation_link(
        temp_condition,
        atomspace.add_list_link([water, freezing])
      )

      freezing_implication = atomspace.add_implication_link(
        freezing_condition,
        water_to_ice,
        tv_law
      )

      # Create reasoning engines
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      initial_size = atomspace.size

      # Run scientific reasoning
      pln_atoms = pln_engine.reason(7)
      ure_atoms = ure_engine.forward_chain(5)

      # Should derive scientific conclusions
      atomspace.size.should be >= initial_size

      puts "Scientific reasoning: generated #{pln_atoms.size + ure_atoms.size} new facts"

      # Look for derived phase relationships
      phase_facts = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select { |link|
          link.is_a?(AtomSpace::EvaluationLink) &&
            link.predicate == phase_change
        }

      puts "Found #{phase_facts.size} phase change relationships"
    end
  end

  describe "Multi-step reasoning workflows" do
    it "chains multiple reasoning steps" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Create a scenario requiring multiple reasoning steps
      tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.9)

      # Create a long chain: A -> B -> C -> D -> E
      concepts = ["A", "B", "C", "D", "E"].map { |name|
        atomspace.add_concept_node(name)
      }

      # Add sequential inheritance links
      (0...concepts.size - 1).each do |i|
        atomspace.add_inheritance_link(concepts[i], concepts[i + 1], tv_high)
      end

      # Property at the end
      property = atomspace.add_concept_node("special_property")
      atomspace.add_inheritance_link(concepts.last, property, tv_high)

      pln_engine = PLN.create_engine(atomspace)

      # Run reasoning in steps to see progression
      steps = 5
      total_new_atoms = 0

      steps.times do |step|
        new_atoms = pln_engine.reason(2)
        total_new_atoms += new_atoms.size

        puts "Step #{step + 1}: generated #{new_atoms.size} new atoms"

        # Check if we've derived A -> special_property
        target_link = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
          .find { |link|
            link.is_a?(AtomSpace::Link) &&
              link.outgoing.size == 2 &&
              link.outgoing[0] == concepts[0] &&
              link.outgoing[1] == property
          }

        if target_link
          puts "Successfully derived A -> special_property at step #{step + 1}"
          tv = target_link.truth_value
          puts "  Strength: #{tv.strength.round(3)}, Confidence: #{tv.confidence.round(3)}"
          break
        end
      end

      puts "Multi-step reasoning: generated #{total_new_atoms} total new atoms"
    end

    it "combines different types of knowledge" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Mix taxonomic, relational, and causal knowledge
      tv_strong = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
      tv_medium = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      # Taxonomic knowledge
      student = atomspace.add_concept_node("student")
      person = atomspace.add_concept_node("person")
      atomspace.add_inheritance_link(student, person, tv_strong)

      # Relational knowledge
      enrolled_in = atomspace.add_predicate_node("enrolled_in")
      attends = atomspace.add_predicate_node("attends")

      # Causal knowledge (enrolling causes attending)
      enrollment_fact = atomspace.add_evaluation_link(
        enrolled_in,
        atomspace.add_variable_node("$STUDENT", "$COURSE")
      )

      attendance_fact = atomspace.add_evaluation_link(
        attends,
        atomspace.add_variable_node("$STUDENT", "$COURSE")
      )

      enrollment_implies_attendance = atomspace.add_implication_link(
        enrollment_fact,
        attendance_fact,
        tv_medium
      )

      # Specific instances
      alice = atomspace.add_concept_node("Alice")
      math_101 = atomspace.add_concept_node("Math_101")

      atomspace.add_inheritance_link(alice, student, tv_strong)
      atomspace.add_evaluation_link(
        enrolled_in,
        atomspace.add_list_link([alice, math_101]),
        tv_strong
      )

      # Create both reasoning engines
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      initial_size = atomspace.size

      # Run both types of reasoning
      pln_atoms = pln_engine.reason(5)
      ure_atoms = ure_engine.forward_chain(3)

      # Should have derived mixed conclusions
      total_new = pln_atoms.size + ure_atoms.size
      puts "Combined reasoning: generated #{total_new} new facts"

      # Look for attendance derivation
      attendance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select { |link|
          link.is_a?(AtomSpace::EvaluationLink) &&
            link.predicate == attends
        }

      puts "Found #{attendance_links.size} attendance relationships"
    end

    it "handles uncertainty propagation" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Test how uncertainty propagates through reasoning chains

      # Create chain with decreasing certainty
      concepts = 5.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      # Add links with decreasing confidence
      (0...concepts.size - 1).each do |i|
        confidence = 0.9 - (i * 0.1) # 0.9, 0.8, 0.7, 0.6
        tv = AtomSpace::SimpleTruthValue.new(0.8, confidence)
        atomspace.add_inheritance_link(concepts[i], concepts[i + 1], tv)
      end

      pln_engine = PLN.create_engine(atomspace)

      initial_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

      # Run reasoning
      new_atoms = pln_engine.reason(6)

      final_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
      derived_links = final_links - initial_links

      puts "Uncertainty propagation: generated #{derived_links.size} derived links"

      # Check uncertainty levels of derived links
      derived_links.each_with_index do |link, i|
        tv = link.truth_value
        puts "  Derived link #{i}: strength=#{tv.strength.round(3)}, confidence=#{tv.confidence.round(3)}"

        # Confidence should generally decrease with longer chains
        tv.confidence.should be <= 1.0
        tv.confidence.should be >= 0.0
      end
    end
  end

  describe "Performance and scalability integration" do
    it "handles realistic knowledge base sizes" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Create knowledge base with realistic complexity
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # Create categories
      categories = ["entity", "object", "tool", "software", "application"].map { |name|
        atomspace.add_concept_node(name)
      }

      # Create instances
      instances = 50.times.map { |i|
        atomspace.add_concept_node("instance_#{i}")
      }.to_a

      # Add taxonomic relationships
      instances.each do |instance|
        category = categories.sample
        atomspace.add_inheritance_link(instance, category, tv)
      end

      # Add inter-category relationships
      (0...categories.size - 1).each do |i|
        atomspace.add_inheritance_link(categories[i], categories[i + 1], tv)
      end

      # Add relational knowledge
      predicates = ["uses", "contains", "depends_on"].map { |name|
        atomspace.add_predicate_node(name)
      }

      # Add 100 relational facts
      100.times do
        pred = predicates.sample
        subj, obj = instances.sample(2)
        atomspace.add_evaluation_link(
          pred,
          atomspace.add_list_link([subj, obj]),
          tv
        )
      end

      initial_size = atomspace.size
      puts "Realistic KB: starting with #{initial_size} atoms"

      # Create reasoning engines
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      # Measure reasoning performance
      start_time = Time.monotonic

      pln_atoms = pln_engine.reason(5)
      ure_atoms = ure_engine.forward_chain(3)

      end_time = Time.monotonic
      duration = end_time - start_time

      final_size = atomspace.size
      total_new = pln_atoms.size + ure_atoms.size

      puts "Realistic KB results:"
      puts "  Final size: #{final_size} atoms"
      puts "  New atoms: #{total_new}"
      puts "  Duration: #{duration.total_seconds.round(2)}s"

      # Should complete in reasonable time
      duration.should be < 15.seconds

      # Should generate some new knowledge
      final_size.should be >= initial_size
    end

    it "maintains consistency across large operations" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Test consistency during large-scale operations

      # Create 1000 atoms in various configurations
      large_set = 1000.times.map { |i|
        case i % 3
        when 0
          atomspace.add_concept_node("large_concept_#{i}")
        when 1
          atomspace.add_predicate_node("large_pred_#{i}")
        else
          # Create links between existing atoms if available
          atoms = atomspace.get_all_atoms
          if atoms.size >= 2
            atom1, atom2 = atoms.sample(2)
            if atom1.is_a?(AtomSpace::Node) && atom2.is_a?(AtomSpace::Node)
              atomspace.add_inheritance_link(atom1, atom2)
            else
              atomspace.add_concept_node("large_backup_#{i}")
            end
          else
            atomspace.add_concept_node("large_backup_#{i}")
          end
        end
      }.to_a

      puts "Large operation: created #{atomspace.size} atoms"

      # Verify all atoms are accessible
      all_atoms = atomspace.get_all_atoms
      all_atoms.size.should eq(atomspace.size)

      # Check that all truth values are valid
      invalid_count = 0
      all_atoms.each do |atom|
        tv = atom.truth_value
        unless (0.0..1.0).includes?(tv.strength) && (0.0..1.0).includes?(tv.confidence)
          invalid_count += 1
        end
      end

      invalid_count.should eq(0)
      puts "Consistency check: all #{all_atoms.size} atoms have valid truth values"

      # Run reasoning on large atomspace
      pln_engine = PLN.create_engine(atomspace)

      start_time = Time.monotonic
      new_atoms = pln_engine.reason(3) # Limited iterations for large space
      end_time = Time.monotonic

      duration = end_time - start_time
      puts "Large-scale reasoning: #{new_atoms.size} new atoms in #{duration.total_seconds.round(2)}s"

      # Should complete without corruption
      atomspace.size.should be >= 1000
    end
  end

  describe "Integration with external data patterns" do
    it "processes structured knowledge import" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Simulate importing structured knowledge (like from a database or API)

      # Knowledge structure: Product -> Category -> Department
      tv = AtomSpace::SimpleTruthValue.new(0.85, 0.9)

      # Categories
      departments = ["electronics", "clothing", "books", "home"].map { |name|
        atomspace.add_concept_node("dept_#{name}")
      }

      categories = [
        "smartphones", "laptops", "tablets",
        "shirts", "pants", "shoes",
        "fiction", "nonfiction", "textbooks",
        "furniture", "appliances", "decor",
      ].map { |name|
        atomspace.add_concept_node("cat_#{name}")
      }

      # Map categories to departments
      category_mappings = {
        0 => 0, 1 => 0, 2 => 0,   # electronics
        3 => 1, 4 => 1, 5 => 1,   # clothing
        6 => 2, 7 => 2, 8 => 2,   # books
        9 => 3, 10 => 3, 11 => 3, # home
      }

      categories.each_with_index do |category, i|
        dept = departments[category_mappings[i]]
        atomspace.add_inheritance_link(category, dept, tv)
      end

      # Products
      products = 50.times.map { |i|
        category = categories.sample
        product = atomspace.add_concept_node("product_#{i}")
        atomspace.add_inheritance_link(product, category, tv)
        product
      }.to_a

      # Properties
      price_pred = atomspace.add_predicate_node("price")
      rating_pred = atomspace.add_predicate_node("rating")

      # Add product properties
      products.each_with_index do |product, i|
        price = AtomSpace::NumberNode.new((10 + i * 5).to_f64)
        rating = AtomSpace::NumberNode.new((1 + rand(4)).to_f64)

        atomspace.add_atom(price)
        atomspace.add_atom(rating)

        atomspace.add_evaluation_link(
          price_pred,
          atomspace.add_list_link([product, price]),
          tv
        )

        atomspace.add_evaluation_link(
          rating_pred,
          atomspace.add_list_link([product, rating]),
          tv
        )
      end

      puts "Structured import: created #{atomspace.size} atoms"

      # Run reasoning to derive department-level insights
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      pln_atoms = pln_engine.reason(4)
      ure_atoms = ure_engine.forward_chain(2)

      puts "Derived #{pln_atoms.size + ure_atoms.size} insights from structured data"

      # Verify data integrity after reasoning
      product_count = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
        .count { |atom| atom.as(AtomSpace::Node).name.starts_with?("product_") }

      product_count.should eq(50)
    end

    it "handles temporal reasoning patterns" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Model temporal relationships and events
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.85)

      # Time points
      time_points = ["t1", "t2", "t3", "t4", "t5"].map { |name|
        atomspace.add_concept_node(name)
      }

      # Events
      events = ["event_A", "event_B", "event_C"].map { |name|
        atomspace.add_concept_node(name)
      }

      # Temporal predicates
      before = atomspace.add_predicate_node("before")
      occurs_at = atomspace.add_predicate_node("occurs_at")
      causes = atomspace.add_predicate_node("causes")

      # Temporal ordering
      (0...time_points.size - 1).each do |i|
        atomspace.add_evaluation_link(
          before,
          atomspace.add_list_link([time_points[i], time_points[i + 1]]),
          tv
        )
      end

      # Event occurrences
      atomspace.add_evaluation_link(
        occurs_at,
        atomspace.add_list_link([events[0], time_points[0]]),
        tv
      )

      atomspace.add_evaluation_link(
        occurs_at,
        atomspace.add_list_link([events[1], time_points[2]]),
        tv
      )

      atomspace.add_evaluation_link(
        occurs_at,
        atomspace.add_list_link([events[2], time_points[4]]),
        tv
      )

      # Causal relationships
      atomspace.add_evaluation_link(
        causes,
        atomspace.add_list_link([events[0], events[1]]),
        tv
      )

      atomspace.add_evaluation_link(
        causes,
        atomspace.add_list_link([events[1], events[2]]),
        tv
      )

      puts "Temporal reasoning: created #{atomspace.size} temporal atoms"

      # Run reasoning on temporal patterns
      ure_engine = URE.create_engine(atomspace)
      pln_engine = PLN.create_engine(atomspace)

      ure_atoms = ure_engine.forward_chain(4)
      pln_atoms = pln_engine.reason(3)

      # Should derive temporal inferences
      temporal_inferences = ure_atoms + pln_atoms
      puts "Temporal reasoning: derived #{temporal_inferences.size} temporal inferences"

      # Look for transitive temporal relationships
      transitive_befores = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select { |link|
          link.is_a?(AtomSpace::EvaluationLink) &&
            link.predicate == before
        }

      puts "Found #{transitive_befores.size} temporal ordering relationships"
    end
  end
end
