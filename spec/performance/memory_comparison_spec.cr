require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace"
require "../../src/pln/pln"
require "../../src/ure/ure"
require "../../src/opencog/opencog"

# Enhanced memory comparison tests for CrystalCog vs C++ OpenCog
describe "CrystalCog Memory Usage Comparison Tests" do
  describe "AtomSpace memory efficiency compared to C++" do
    it "benchmarks basic atom creation memory efficiency" do
      atomspace = AtomSpace::AtomSpace.new

      # Test based on C++ AtomSpaceBenchmark parameters
      # C++ benchmark typically creates 256K atoms (1 << 18)
      num_atoms = 3000 # Reduced for testing, but enough for reliable RSS measurement

      result = CogUtil::MemoryProfiler.benchmark_memory("concept_node_creation") do
        atoms = num_atoms.times.map { |i|
          atomspace.add_concept_node("concept_#{i}")
        }.to_a
        atoms.size
      end

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)

      puts "Concept Node Creation Memory Test:"
      puts "  Created #{result.atom_count} atoms"
      puts "  Memory per atom: #{result.memory_per_atom.round(2)} bytes"
      puts "  C++ target met: #{evaluation["meets_cpp_target"]}"
      puts "  Memory efficiency: #{result.memory_efficiency.round(1)}%"

      # Should meet C++ performance targets
      evaluation["meets_cpp_target"].should be_true
      result.memory_per_atom.should be < 1000.0 # Less than 1KB per atom
      result.duration_ms.should be < 1000.0     # Should complete quickly
    end

    it "benchmarks link creation memory vs C++ implementation" do
      atomspace = AtomSpace::AtomSpace.new

      # Pre-create nodes like C++ benchmark
      concepts = 100.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      num_links = 200

      result = CogUtil::MemoryProfiler.benchmark_memory("inheritance_link_creation") do
        links = num_links.times.map { |i|
          source = concepts.sample
          target = concepts.sample
          atomspace.add_inheritance_link(source, target)
        }.to_a
        links.size
      end

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)

      puts "Inheritance Link Creation Memory Test:"
      puts "  Created #{result.atom_count} links"
      puts "  Memory per link: #{result.memory_per_atom.round(2)} bytes"
      puts "  C++ compatible: #{evaluation["meets_cpp_target"]}"

      # Links should use reasonable memory (C++ links are typically larger than nodes)
      result.memory_per_atom.should be < 1500.0 # Allow slightly more for links
      evaluation["meets_cpp_target"].should be_true
    end

    it "tests memory scaling vs C++ AtomSpace scaling" do
      atomspace = AtomSpace::AtomSpace.new

      # Test memory scaling with different AtomSpace sizes.
      # Start at 500 atoms because RSS measurements at 100 atoms are too noisy on CI.
      scale_factors = [500, 1000, 2000]

      results = CogUtil::MemoryProfiler.benchmark_atomspace_scaling(atomspace, scale_factors)

      puts "AtomSpace Memory Scaling Test:"
      results.each do |result|
        evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)
        puts "  Scale #{result.atom_count}: #{result.memory_per_atom.round(2)} bytes/atom, " +
             "efficiency: #{result.memory_efficiency.round(1)}%, " +
             "C++ compatible: #{evaluation["meets_cpp_target"]}"
      end

      # Memory per atom should stay reasonable even with scaling
      results.each do |result|
        evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)
        evaluation["meets_cpp_target"].should be_true
      end

      # Memory efficiency should not degrade significantly with scale
      first_efficiency = results.first.memory_efficiency
      last_efficiency = results.last.memory_efficiency
      efficiency_degradation = first_efficiency - last_efficiency
      efficiency_degradation.should be < 20.0 # Should not lose more than 20% efficiency
    end

    it "compares truth value memory overhead with C++" do
      atomspace = AtomSpace::AtomSpace.new

      # Test memory overhead of truth values (like C++ benchmark)
      base_atoms = 1000

      # Create atoms without truth values
      result_base = CogUtil::MemoryProfiler.benchmark_memory("atoms_without_tv") do
        atoms = base_atoms.times.map { |i|
          atomspace.add_concept_node("base_#{i}")
        }.to_a
        atoms.size
      end

      atomspace.clear

      # Create atoms with truth values
      result_with_tv = CogUtil::MemoryProfiler.benchmark_memory("atoms_with_tv") do
        atoms = base_atoms.times.map { |i|
          atom = atomspace.add_concept_node("tv_#{i}")
          tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
          atom.truth_value = tv
          atom
        }.to_a
        atoms.size
      end

      tv_overhead = result_with_tv.memory_per_atom - result_base.memory_per_atom

      puts "Truth Value Memory Overhead Test:"
      puts "  Base memory per atom: #{result_base.memory_per_atom.round(2)} bytes"
      puts "  With TV memory per atom: #{result_with_tv.memory_per_atom.round(2)} bytes"
      puts "  Truth value overhead: #{tv_overhead.round(2)} bytes"

      # TV overhead should be reasonable (C++ SimpleTruthValue is ~32 bytes)
      # Use generous threshold since RSS-based measurement is unreliable on CI
      tv_overhead.should be < 256.0
    end

    it "tests memory leak detection" do
      atomspace = AtomSpace::AtomSpace.new

      # Test for memory leaks during repeated operations
      puts "Memory Leak Detection Test:"

      has_leak = CogUtil::MemoryProfiler.detect_memory_leaks(50) do
        # Create and destroy atoms repeatedly
        10.times do |i|
          atom = atomspace.add_concept_node("temp_#{i}")
          # AtomSpace should manage memory automatically
        end
      end

      puts "  Memory leak detected: #{has_leak}"
      has_leak.should be_false
    end

    it "generates comprehensive memory comparison report" do
      atomspace = AtomSpace::AtomSpace.new

      # Run multiple benchmarks and generate a report
      results = [] of CogUtil::MemoryProfiler::MemoryBenchmarkResult

      # Basic node creation
      results << CogUtil::MemoryProfiler.benchmark_memory("node_creation_2000") do
        2000.times { |i| atomspace.add_concept_node("report_node_#{i}") }
        2000
      end

      # Link creation
      concepts = 200.times.map { |i| atomspace.add_concept_node("link_concept_#{i}") }.to_a
      results << CogUtil::MemoryProfiler.benchmark_memory("link_creation_1000") do
        1000.times do |i|
          atomspace.add_inheritance_link(concepts.sample, concepts.sample)
        end
        1000
      end

      # Complex structures (each iteration creates 5 atoms: pred + 2 concepts + list + eval link)
      results << CogUtil::MemoryProfiler.benchmark_memory("complex_structures_2500") do
        500.times do |i|
          pred = atomspace.add_predicate_node("pred_#{i}")
          arg1 = atomspace.add_concept_node("arg1_#{i}")
          arg2 = atomspace.add_concept_node("arg2_#{i}")
          list = atomspace.add_list_link([arg1, arg2])
          atomspace.add_evaluation_link(pred, list)
        end
        2500
      end

      report = CogUtil::MemoryProfiler.generate_memory_report(results)

      puts "\n" + "="*60
      puts report
      puts "="*60

      # All operations should meet C++ compatibility
      results.each do |result|
        evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)
        evaluation["meets_cpp_target"].should be_true
      end
    end
  end

  describe "reasoning memory efficiency" do
    it "benchmarks PLN reasoning memory efficiency" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN::PLNEngine.new(atomspace)

      # Create knowledge base
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # Create reasoning chain
      concepts = 10.times.map { |i|
        atomspace.add_concept_node("pln_concept_#{i}")
      }.to_a

      # Add inheritance relationships
      9.times do |i|
        atomspace.add_inheritance_link(concepts[i], concepts[i + 1], tv)
      end

      initial_atoms = atomspace.size

      result = CogUtil::MemoryProfiler.benchmark_memory("pln_reasoning") do
        new_atoms = pln_engine.reason(5)
        new_atoms.size
      end

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)

      puts "PLN Reasoning Memory Test:"
      puts "  Initial atoms: #{initial_atoms}"
      puts "  New inferences: #{result.atom_count}"
      puts "  Memory per inference: #{result.memory_per_atom.round(2)} bytes"
      puts "  Memory efficient: #{evaluation["is_efficient"]}"

      # PLN reasoning should be memory efficient
      result.memory_per_atom.should be < 4096.0 # Allow more for complex reasoning on CI
      evaluation["is_efficient"].should be_true
    end

    it "tests URE memory efficiency vs C++ implementation" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      # Create knowledge base
      predicates = 3.times.map { |i|
        atomspace.add_predicate_node("ure_pred_#{i}")
      }.to_a

      concepts = 20.times.map { |i|
        atomspace.add_concept_node("ure_concept_#{i}")
      }.to_a

      tv = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      # Add facts
      20.times do
        pred = predicates.sample
        arg1, arg2 = concepts.sample(2)
        atomspace.add_evaluation_link(pred, atomspace.add_list_link([arg1, arg2]), tv)
      end

      result = CogUtil::MemoryProfiler.benchmark_memory("ure_forward_chaining") do
        new_atoms = ure_engine.forward_chain(3)
        new_atoms.size
      end

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)

      puts "URE Forward Chaining Memory Test:"
      puts "  New inferences: #{result.atom_count}"
      puts "  Memory per inference: #{result.memory_per_atom.round(2)} bytes"
      puts "  C++ compatible: #{evaluation["meets_cpp_target"]}"

      # URE should be memory efficient
      evaluation["meets_cpp_target"].should be_true
      result.memory_per_atom.should be < 2000.0
    end
  end

  describe "comprehensive system memory comparison" do
    it "performs full system memory benchmark comparable to C++" do
      atomspace = AtomSpace::AtomSpace.new
      OpenCog.initialize

      # This test simulates the C++ AtomSpaceBenchmark comprehensive test
      results = [] of CogUtil::MemoryProfiler::MemoryBenchmarkResult

      puts "\nComprehensive System Memory Benchmark:"
      puts "======================================"

      # 1. Large scale atom creation (similar to C++ 256K atom test)
      results << CogUtil::MemoryProfiler.benchmark_memory("large_scale_atoms") do
        5000.times { |i| atomspace.add_concept_node("large_#{i}") }
        5000
      end

      # 2. Mixed atom types
      results << CogUtil::MemoryProfiler.benchmark_memory("mixed_atom_types") do
        count = 0
        1000.times do |i|
          atomspace.add_concept_node("concept_#{i}")
          atomspace.add_predicate_node("predicate_#{i}")
          count += 2
        end
        count
      end

      # 3. Complex link structures
      concepts = (0..500).map { |i| atomspace.add_concept_node("link_concept_#{i}") }
      results << CogUtil::MemoryProfiler.benchmark_memory("complex_links") do
        2000.times do |i|
          c1, c2, c3 = concepts.sample(3)
          # Create nested link structures
          list = atomspace.add_list_link([c1, c2])
          atomspace.add_inheritance_link(list, c3)
        end
        4000
      end

      # 4. Truth value heavy operations
      results << CogUtil::MemoryProfiler.benchmark_memory("truth_value_operations") do
        2000.times do |i|
          atom = atomspace.add_concept_node("tv_heavy_#{i}")
          tv = AtomSpace::SimpleTruthValue.new(rand, rand)
          atom.truth_value = tv
        end
        2000
      end

      # Generate comprehensive report
      report = CogUtil::MemoryProfiler.generate_memory_report(results)
      puts report

      # System-level validation
      total_atoms = results.sum(&.atom_count)
      avg_memory_per_atom = results.map(&.memory_per_atom).sum / results.size

      puts "\nSystem-Level Memory Analysis:"
      puts "  Total atoms created: #{total_atoms}"
      puts "  Average memory per atom: #{avg_memory_per_atom.round(2)} bytes"
      puts "  Total memory increase: #{results.sum(&.memory_increase_kb)} KB"

      # Final system validation
      total_atoms.should be > 10000          # Should have created substantial atoms
      avg_memory_per_atom.should be < 1200.0 # Average should meet C++ targets

      # All individual tests should pass C++ compatibility
      results.each do |result|
        evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)
        evaluation["meets_cpp_target"].should be_true
      end

      puts "\n✓ Crystal memory usage is comparable to C++ implementation"
    end
  end
end
