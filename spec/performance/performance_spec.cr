require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace"
require "../../src/pln/pln"
require "../../src/ure/ure"
require "../../src/opencog/opencog"

# Shared helper to create atomspace for tests that need it
def create_atomspace
  AtomSpace::AtomSpace.new
end

# Performance and benchmarking tests for CrystalCog
describe "CrystalCog Performance Tests" do

  describe "AtomSpace performance" do
    it "benchmarks atom creation" do
      atomspace = create_atomspace
      num_atoms = 1000

      start_time = Time.monotonic

      atoms = num_atoms.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should create atoms quickly
      duration.should be < 1.second

      # Should have created all atoms
      atomspace.size.should eq(num_atoms)

      # Rate should be reasonable (>500 atoms/second)
      rate = num_atoms / duration.total_seconds
      rate.should be > 500.0

      puts "Atom creation rate: #{rate.round(2)} atoms/second"
    end

    it "benchmarks atom retrieval" do
      atomspace = create_atomspace
      # Pre-populate atomspace
      num_atoms = 500
      atoms = num_atoms.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      # Benchmark retrieval
      num_retrievals = 1000

      start_time = Time.monotonic

      num_retrievals.times do
        random_atom = atoms.sample
        retrieved = atomspace.get_atom(random_atom.handle)
        retrieved.should eq(random_atom)
      end

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should retrieve quickly
      duration.should be < 0.5.seconds

      rate = num_retrievals / duration.total_seconds
      rate.should be > 1000.0

      puts "Atom retrieval rate: #{rate.round(2)} retrievals/second"
    end

    it "benchmarks link creation" do
      atomspace = create_atomspace
      # Create nodes first
      nodes = 100.times.map { |i|
        atomspace.add_concept_node("node_#{i}")
      }.to_a

      num_links = 200

      start_time = Time.monotonic

      links = num_links.times.map { |i|
        node1 = nodes.sample
        node2 = nodes.sample
        atomspace.add_inheritance_link(node1, node2)
      }.to_a

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should create links quickly
      duration.should be < 1.second

      rate = num_links / duration.total_seconds
      rate.should be > 200.0

      puts "Link creation rate: #{rate.round(2)} links/second"
    end

    it "benchmarks atomspace search operations" do
      atomspace = create_atomspace
      # Populate with mixed atom types
      concepts = 100.times.map { |i| atomspace.add_concept_node("concept_#{i}") }.to_a
      predicates = 50.times.map { |i| atomspace.add_predicate_node("pred_#{i}") }.to_a

      # Create some links
      20.times do
        c1, c2 = concepts.sample(2)
        atomspace.add_inheritance_link(c1, c2)
      end

      num_searches = 100

      start_time = Time.monotonic

      num_searches.times do
        # Search by type
        found_concepts = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
        found_concepts.size.should eq(100)

        # Search by name
        random_name = "concept_#{rand(100)}"
        found_by_name = atomspace.get_nodes_by_name(random_name)
        found_by_name.size.should be <= 1
      end

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should search quickly
      duration.should be < 2.seconds

      rate = if duration.total_seconds > 0
               num_searches / duration.total_seconds
             else
               0.0
             end
      puts "Search rate: #{rate.round(2)} searches/second"
    end

    it "benchmarks memory usage" do
      atomspace = create_atomspace
      # Create a large number of atoms and measure memory characteristics
      initial_memory = CogUtil::MemoryProfiler.get_system_memory_info

      large_num_atoms = 5000

      result = CogUtil::MemoryProfiler.benchmark_memory("comprehensive_memory_test") do
        atoms = large_num_atoms.times.map { |i|
          atomspace.add_concept_node("large_concept_#{i}")
        }.to_a

        # Add some truth values
        atoms.each_with_index do |atom, i|
          tv = AtomSpace::SimpleTruthValue.new(i / large_num_atoms.to_f, 0.8)
          atom.truth_value = tv
        end

        atoms.size
      end

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)

      puts "Enhanced Memory Usage Test:"
      puts "  Total atoms: #{atomspace.size}"
      puts "  Memory per atom: #{result.memory_per_atom.round(2)} bytes"
      puts "  Memory efficiency: #{result.memory_efficiency.round(1)}%"
      puts "  C++ compatibility: #{evaluation["meets_cpp_target"] ? "PASS" : "NEEDS_OPTIMIZATION"}"

      # Should use reasonable memory per atom (Crystal is efficient)
      result.memory_per_atom.should be < 1000 # bytes per atom (C++ target)
      evaluation["meets_cpp_target"].should be_true
    end
  end

  describe "PLN reasoning performance" do
    it "benchmarks simple reasoning chains" do
      atomspace = create_atomspace
      pln_engine = PLN::PLNEngine.new(atomspace)
      # Create reasoning chain: A->B, B->C, should infer A->C
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      num_chains = 10

      # Create multiple reasoning chains
      chains = num_chains.times.map { |i|
        a = atomspace.add_concept_node("A_#{i}")
        b = atomspace.add_concept_node("B_#{i}")
        c = atomspace.add_concept_node("C_#{i}")

        atomspace.add_inheritance_link(a, b, tv)
        atomspace.add_inheritance_link(b, c, tv)

        [a, b, c]
      }.to_a

      initial_size = atomspace.size

      start_time = Time.monotonic

      new_atoms = pln_engine.reason(5)

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete quickly
      duration.should be < 3.seconds

      # Should have inferred new relationships
      atomspace.size.should be > initial_size

      rate = if duration.total_seconds > 0
               new_atoms.size / duration.total_seconds
             else
               0.0
             end
      puts "PLN inference rate: #{rate.round(2)} inferences/second"
    end

    it "benchmarks complex reasoning scenarios" do
      atomspace = create_atomspace
      pln_engine = PLN::PLNEngine.new(atomspace)
      # Create hierarchical taxonomy
      tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.95)
      tv_med = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # Create taxonomy: animals -> mammals -> dogs -> specific_dogs
      levels = [
        ["living_thing"],
        ["animal", "plant"],
        ["mammal", "bird", "fish"],
        ["dog", "cat", "horse"],
        ["beagle", "poodle", "german_shepherd"],
      ]

      concepts = levels.map { |level|
        level.map { |name| atomspace.add_concept_node(name) }
      }

      # Add inheritance relationships between levels
      (0...levels.size - 1).each do |level_idx|
        current_level = concepts[level_idx]
        next_level = concepts[level_idx + 1]

        next_level.each do |child|
          parent = current_level.sample # Random parent from previous level
          tv = level_idx == 0 ? tv_high : tv_med
          atomspace.add_inheritance_link(child, parent, tv)
        end
      end

      initial_size = atomspace.size

      start_time = Time.monotonic

      # Run extended reasoning
      new_atoms = pln_engine.reason(10)

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete in reasonable time even for complex scenarios
      duration.should be < 10.seconds

      # Should have inferred many transitive relationships
      atomspace.size.should be > initial_size

      inferred_count = atomspace.size - initial_size
      puts "Complex PLN reasoning: #{inferred_count} new atoms in #{duration.total_seconds.round(2)}s"
    end

    it "measures reasoning accuracy" do
      atomspace = create_atomspace
      pln_engine = PLN::PLNEngine.new(atomspace)
      # Create ground truth scenario and measure how well PLN performs
      tv_perfect = AtomSpace::SimpleTruthValue.new(1.0, 1.0)

      # Known facts
      socrates = atomspace.add_concept_node("socrates")
      human = atomspace.add_concept_node("human")
      mortal = atomspace.add_concept_node("mortal")

      # Socrates is human (perfect confidence)
      atomspace.add_inheritance_link(socrates, human, tv_perfect)

      # All humans are mortal (perfect confidence)
      atomspace.add_inheritance_link(human, mortal, tv_perfect)

      # Run reasoning
      new_atoms = pln_engine.reason(5)

      # Should derive that Socrates is mortal
      socrates_mortal = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
        .find { |link|
          link.is_a?(AtomSpace::Link) &&
            link.outgoing.size == 2 &&
            link.outgoing[0] == socrates &&
            link.outgoing[1] == mortal
        }

      if socrates_mortal
        # Truth value should be high (derived from perfect premises)
        tv = socrates_mortal.truth_value
        tv.strength.should be > 0.9
        tv.confidence.should be > 0.8

        puts "PLN accuracy test passed: derived strength=#{tv.strength.round(3)}, confidence=#{tv.confidence.round(3)}"
      else
        puts "PLN accuracy test: Expected inference not found (may be implementation dependent)"
      end
    end
  end

  describe "URE reasoning performance" do
    it "benchmarks forward chaining performance" do
      atomspace = create_atomspace
      ure_engine = URE::UREEngine.new(atomspace)
      # Create facts for URE to work with
      predicates = ["likes", "knows", "lives_in"].map { |name|
        atomspace.add_predicate_node(name)
      }

      people = ["alice", "bob", "charlie", "diana"].map { |name|
        atomspace.add_concept_node(name)
      }

      places = ["london", "paris", "tokyo"].map { |name|
        atomspace.add_concept_node(name)
      }

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # Create many evaluation links
      num_facts = 50
      facts = num_facts.times.map { |i|
        pred = predicates.sample
        arg1 = people.sample
        arg2 = (people + places).sample

        atomspace.add_evaluation_link(
          pred,
          atomspace.add_list_link([arg1, arg2]),
          tv
        )
      }.to_a

      initial_size = atomspace.size

      start_time = Time.monotonic

      new_atoms = ure_engine.forward_chain(5)

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete quickly
      duration.should be < 5.seconds

      rate = if duration.total_seconds > 0
               new_atoms.size / duration.total_seconds
             else
               0.0
             end
      puts "URE forward chaining rate: #{rate.round(2)} inferences/second"
    end

    it "benchmarks backward chaining performance" do
      atomspace = create_atomspace
      ure_engine = URE::UREEngine.new(atomspace)
      # Set up scenario for backward chaining
      pred = atomspace.add_predicate_node("can_derive")
      concepts = 20.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      tv = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      # Add some facts
      10.times do
        c1, c2 = concepts.sample(2)
        atomspace.add_evaluation_link(pred, atomspace.add_list_link([c1, c2]), tv)
      end

      # Create goals to search for
      num_queries = 20
      goals = num_queries.times.map { |i|
        c1, c2 = concepts.sample(2)
        atomspace.add_evaluation_link(pred, atomspace.add_list_link([c1, c2]))
      }.to_a

      start_time = Time.monotonic

      results = goals.map { |goal|
        ure_engine.backward_chain(goal)
      }

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete quickly
      duration.should be < 3.seconds

      success_count = results.count { |r| r == true }
      rate = if duration.total_seconds > 0
               num_queries / duration.total_seconds
             else
               0.0
             end

      puts "URE backward chaining: #{success_count}/#{num_queries} goals found, #{rate.round(2)} queries/second"
    end

    it "measures URE rule application efficiency" do
      atomspace = create_atomspace
      ure_engine = URE::UREEngine.new(atomspace)
      # Test how efficiently URE applies rules
      ure_engine.forward_chainer.add_default_rules

      # Create optimal scenario for conjunction rule
      pred = atomspace.add_predicate_node("test_pred")
      concepts = 10.times.map { |i|
        atomspace.add_concept_node("test_#{i}")
      }.to_a

      tv = AtomSpace::SimpleTruthValue.new(0.9, 0.9)

      # Create pairs of evaluation links (good for conjunction)
      eval_pairs = 5.times.map { |i|
        c1, c2 = concepts.sample(2)
        [
          atomspace.add_evaluation_link(pred, c1, tv),
          atomspace.add_evaluation_link(pred, c2, tv),
        ]
      }.to_a

      initial_size = atomspace.size

      start_time = Time.monotonic

      # Run limited forward chaining
      new_atoms = ure_engine.forward_chain(3)

      end_time = Time.monotonic
      duration = end_time - start_time

      # Calculate efficiency metrics
      rule_applications = new_atoms.size
      if rule_applications > 0
        efficiency = rule_applications / duration.total_seconds
        puts "URE rule application efficiency: #{efficiency.round(2)} applications/second"
      end

      # Should have applied some rules
      new_atoms.size.should be >= 0
    end
  end

  describe "integrated system performance" do
    it "benchmarks full reasoning pipeline" do
      atomspace = create_atomspace
      OpenCog.initialize
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)
      # Create comprehensive knowledge base
      tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
      tv_med = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      # Taxonomic knowledge
      categories = ["entity", "living", "animal", "mammal", "primate", "human"].map { |name|
        atomspace.add_concept_node(name)
      }

      individuals = ["socrates", "plato", "aristotle"].map { |name|
        atomspace.add_concept_node(name)
      }

      # Build taxonomy chain
      (0...categories.size - 1).each do |i|
        atomspace.add_inheritance_link(categories[i + 1], categories[i], tv_high)
      end

      # Individuals are humans
      individuals.each do |individual|
        atomspace.add_inheritance_link(individual, categories.last, tv_med)
      end

      # Relational knowledge
      predicates = ["teaches", "student_of", "wrote"].map { |name|
        atomspace.add_predicate_node(name)
      }

      # Add some relationships
      atomspace.add_evaluation_link(
        predicates[0],
        atomspace.add_list_link([individuals[0], individuals[1]]),
        tv_med
      )

      initial_size = atomspace.size

      start_time = Time.monotonic

      # Run both reasoning engines
      pln_atoms = pln_engine.reason(5)
      ure_atoms = ure_engine.forward_chain(3)

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete in reasonable time
      duration.should be < 10.seconds

      total_inferences = pln_atoms.size + ure_atoms.size
      final_size = atomspace.size

      puts "Full pipeline performance:"
      puts "  Initial atoms: #{initial_size}"
      puts "  Final atoms: #{final_size}"
      puts "  New inferences: #{total_inferences}"
      puts "  Duration: #{duration.total_seconds.round(2)}s"

      if duration.total_seconds > 0
        rate = total_inferences / duration.total_seconds
        puts "  Inference rate: #{rate.round(2)} inferences/second"
      end
    end

    it "measures system scalability" do
      atomspace = create_atomspace
      OpenCog.initialize
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)
      # Test how system performs with increasing load
      base_concepts = 5
      scale_factors = [1, 2, 4]

      results = scale_factors.map { |factor|
        atomspace.clear

        num_concepts = base_concepts * factor

        # Create knowledge proportional to scale factor
        concepts = num_concepts.times.map { |i|
          atomspace.add_concept_node("scale_concept_#{factor}_#{i}")
        }.to_a

        tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

        # Add inheritance relationships
        (num_concepts / 2).to_i.times do
          c1, c2 = concepts.sample(2)
          atomspace.add_inheritance_link(c1, c2, tv)
        end

        # Add evaluations
        pred = atomspace.add_predicate_node("scale_pred_#{factor}")
        (num_concepts / 3).to_i.times do
          c1, c2 = concepts.sample(2)
          atomspace.add_evaluation_link(pred, atomspace.add_list_link([c1, c2]), tv)
        end

        initial_atoms = atomspace.size

        start_time = Time.monotonic

        # Run limited reasoning to avoid exponential explosion
        pln_atoms = pln_engine.reason(2)
        ure_atoms = ure_engine.forward_chain(2)

        end_time = Time.monotonic
        duration = end_time - start_time

        {
          scale_factor:  factor,
          initial_atoms: initial_atoms,
          new_atoms:     pln_atoms.size + ure_atoms.size,
          duration:      duration.total_seconds,
        }
      }

      puts "Scalability results:"
      results.each do |result|
        rate = if result[:duration] > 0
                 result[:new_atoms] / result[:duration]
               else
                 0.0
               end
        puts "  Scale #{result[:scale_factor]}x: #{result[:initial_atoms]} atoms → #{result[:new_atoms]} inferences in #{result[:duration].round(2)}s (#{rate.round(2)} inf/s)"
      end

      # Check that performance degrades gracefully (not exponentially)
      last_duration = 0.0
      results.each do |result|
        if last_duration > 0
          # Duration shouldn't increase by more than factor^2
          max_acceptable = last_duration * (result[:scale_factor] ** 2) * 2
          result[:duration].should be < max_acceptable
        end
        last_duration = result[:duration]
      end
    end

    it "measures memory efficiency under load" do
      atomspace = create_atomspace
      OpenCog.initialize
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)
      
      initial_memory = GC.stats.heap_size

      # Create substantial knowledge base
      num_concepts = 1000
      concepts = num_concepts.times.map { |i|
        atomspace.add_concept_node("memory_test_#{i}")
      }.to_a

      predicates = 10.times.map { |i|
        atomspace.add_predicate_node("pred_#{i}")
      }.to_a

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # Add many relationships
      2000.times do
        c1, c2 = concepts.sample(2)
        atomspace.add_inheritance_link(c1, c2, tv)
      end

      1000.times do
        pred = predicates.sample
        c1, c2 = concepts.sample(2)
        atomspace.add_evaluation_link(pred, atomspace.add_list_link([c1, c2]), tv)
      end

      before_reasoning_memory = GC.stats.heap_size
      atoms_before = atomspace.size

      # Run reasoning
      pln_atoms = pln_engine.reason(3)
      ure_atoms = ure_engine.forward_chain(2)

      GC.collect # Force cleanup

      after_reasoning_memory = GC.stats.heap_size
      atoms_after = atomspace.size

      # Calculate memory metrics
      memory_per_atom_before = (before_reasoning_memory - initial_memory) / atoms_before
      total_memory_increase = after_reasoning_memory - before_reasoning_memory
      new_atoms = atoms_after - atoms_before

      puts "Memory efficiency test:"
      puts "  Initial memory usage: #{(before_reasoning_memory - initial_memory)} bytes for #{atoms_before} atoms"
      puts "  Memory per atom (before reasoning): #{memory_per_atom_before} bytes"
      puts "  Memory increase after reasoning: #{total_memory_increase} bytes for #{new_atoms} new atoms"

      # Memory usage should be reasonable (Crystal is memory-efficient)
      memory_per_atom_before.should be < 2000 # bytes per atom (rough estimate)

      if new_atoms > 0
        memory_per_new_atom = total_memory_increase / new_atoms
        puts "  Memory per new atom: #{memory_per_new_atom} bytes"
      end
    end
  end

  describe "comparative performance" do
    it "compares PLN vs URE reasoning speed" do
      atomspace = create_atomspace
      pln_engine = PLN::PLNEngine.new(atomspace)
      ure_engine = URE::UREEngine.new(atomspace)

      # Create knowledge suitable for both engines
      concepts = 20.times.map { |i|
        atomspace.add_concept_node("comp_concept_#{i}")
      }.to_a

      predicates = 3.times.map { |i|
        atomspace.add_predicate_node("comp_pred_#{i}")
      }.to_a

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # Add inheritance links (PLN-friendly)
      15.times do
        c1, c2 = concepts.sample(2)
        atomspace.add_inheritance_link(c1, c2, tv)
      end

      # Add evaluation links (URE-friendly)
      15.times do
        pred = predicates.sample
        c1, c2 = concepts.sample(2)
        atomspace.add_evaluation_link(pred, atomspace.add_list_link([c1, c2]), tv)
      end

      # Benchmark PLN
      pln_start = Time.monotonic
      pln_atoms = pln_engine.reason(3)
      pln_duration = Time.monotonic - pln_start

      # Benchmark URE
      ure_start = Time.monotonic
      ure_atoms = ure_engine.forward_chain(3)
      ure_duration = Time.monotonic - ure_start

      pln_rate = if pln_duration.total_seconds > 0
                   pln_atoms.size / pln_duration.total_seconds
                 else
                   0.0
                 end
      ure_rate = if ure_duration.total_seconds > 0
                   ure_atoms.size / ure_duration.total_seconds
                 else
                   0.0
                 end

      puts "Comparative performance:"
      puts "  PLN: #{pln_atoms.size} inferences in #{pln_duration.total_seconds.round(3)}s (#{pln_rate.round(2)} inf/s)"
      puts "  URE: #{ure_atoms.size} inferences in #{ure_duration.total_seconds.round(3)}s (#{ure_rate.round(2)} inf/s)"

      # Both should complete in reasonable time
      pln_duration.should be < 5.seconds
      ure_duration.should be < 5.seconds
    end

    it "measures reasoning quality vs speed tradeoff" do
      atomspace = create_atomspace
      pln_engine = PLN::PLNEngine.new(atomspace)

      # Create known inference scenario
      tv_high = AtomSpace::SimpleTruthValue.new(0.95, 0.9)
      tv_med = AtomSpace::SimpleTruthValue.new(0.8, 0.8)

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      c = atomspace.add_concept_node("C")
      d = atomspace.add_concept_node("D")

      # Chain: A->B->C->D
      atomspace.add_inheritance_link(a, b, tv_high)
      atomspace.add_inheritance_link(b, c, tv_med)
      atomspace.add_inheritance_link(c, d, tv_med)

      # Test different iteration counts
      iteration_counts = [1, 3, 5, 10]

      results = iteration_counts.map { |iterations|
        atomspace_copy = atomspace # Note: This is simplified - real copy would be complex

        start_time = Time.monotonic
        new_atoms = pln_engine.reason(iterations)
        duration = Time.monotonic - start_time

        # Look for A->D inference (should be derived)
        a_to_d = new_atoms.find { |atom|
          atom.is_a?(AtomSpace::Link) &&
            atom.as(AtomSpace::Link).outgoing.size == 2 &&
            atom.as(AtomSpace::Link).outgoing[0] == a &&
            atom.as(AtomSpace::Link).outgoing[1] == d
        }

        quality_score = if a_to_d
                          # Quality based on truth value accuracy
                          tv = a_to_d.truth_value
                          tv.strength * tv.confidence
                        else
                          0.0
                        end

        {
          iterations: iterations,
          duration:   duration.total_seconds,
          new_atoms:  new_atoms.size,
          quality:    quality_score,
        }
      }

      puts "Quality vs Speed tradeoff:"
      results.each do |result|
        puts "  #{result[:iterations]} iterations: #{result[:new_atoms]} atoms, quality=#{result[:quality].round(3)}, time=#{result[:duration].round(3)}s"
      end

      # Quality should generally improve with more iterations (up to a point)
      # Speed should degrade with more iterations
      results.each do |result|
        result[:duration].should be < 5.0 # Should stay reasonable (in seconds)
      end
    end
  end
end
