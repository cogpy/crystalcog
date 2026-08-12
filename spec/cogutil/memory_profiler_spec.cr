require "spec"
require "../../src/cogutil/memory_profiler"
require "../../src/atomspace/atomspace"

# Unit coverage for CogUtil::MemoryProfiler
describe CogUtil::MemoryProfiler do
  describe "SystemMemoryInfo" do
    it "stores memory fields and computes efficiency" do
      info = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        rss_kb: 1000_i64,
        vsize_kb: 2000_i64,
        heap_size: 500_i64,
        heap_used: 250_i64,
        total_allocations: 250_i64,
        free_bytes: 250_i64
      )

      info.rss_kb.should eq(1000)
      info.vsize_kb.should eq(2000)
      info.heap_size.should eq(500)
      info.heap_used.should eq(250)
      info.memory_efficiency.should eq(50.0)
    end

    it "returns zero efficiency when heap size is zero" do
      info = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        0_i64, 0_i64, 0_i64, 0_i64, 0_i64, 0_i64
      )
      info.memory_efficiency.should eq(0.0)
    end
  end

  describe "AtomMemoryInfo" do
    it "sums component sizes into total_size" do
      info = CogUtil::MemoryProfiler::AtomMemoryInfo.new(64, 32, 16, 8)
      info.atom_size.should eq(64)
      info.truth_value_size.should eq(32)
      info.name_size.should eq(16)
      info.outgoing_size.should eq(8)
      info.total_size.should eq(120)
    end
  end

  describe "MemoryBenchmarkResult" do
    it "computes memory_per_atom and memory_increase_kb" do
      initial = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        1000_i64, 2000_i64, 100_i64, 80_i64, 80_i64, 20_i64
      )
      final = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        1002_i64, 2000_i64, 100_i64, 90_i64, 90_i64, 10_i64
      )

      result = CogUtil::MemoryProfiler::MemoryBenchmarkResult.new(
        "create_atoms",
        initial,
        final,
        2,
        12.5
      )

      result.operation.should eq("create_atoms")
      result.atom_count.should eq(2)
      result.duration_ms.should eq(12.5)
      result.memory_increase_kb.should eq(2)
      # (2 KB * 1024) / 2 atoms = 1024 bytes/atom
      result.memory_per_atom.should eq(1024.0)
      result.memory_efficiency.should eq(final.memory_efficiency)
    end

    it "returns zero memory_per_atom when atom_count is zero" do
      initial = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        100_i64, 200_i64, 50_i64, 25_i64, 25_i64, 25_i64
      )
      final = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        110_i64, 200_i64, 50_i64, 30_i64, 30_i64, 20_i64
      )

      result = CogUtil::MemoryProfiler::MemoryBenchmarkResult.new(
        "noop",
        initial,
        final,
        0,
        1.0
      )

      result.memory_per_atom.should eq(0.0)
      result.memory_increase_kb.should eq(10)
    end
  end

  describe ".get_system_memory_info" do
    it "returns non-negative system memory stats" do
      info = CogUtil::MemoryProfiler.get_system_memory_info

      info.should be_a(CogUtil::MemoryProfiler::SystemMemoryInfo)
      info.rss_kb.should be >= 0
      info.vsize_kb.should be >= 0
      info.heap_size.should be >= 0
      info.heap_used.should be >= 0
      info.free_bytes.should be >= 0
      info.total_allocations.should be >= 0
      info.memory_efficiency.should be >= 0.0
    end
  end

  describe ".estimate_atom_memory" do
    it "estimates memory for a concept node including name and truth value" do
      atomspace = AtomSpace::AtomSpace.new
      node = atomspace.add_concept_node("memory_test_node")
      node.truth_value = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      estimate = CogUtil::MemoryProfiler.estimate_atom_memory(node)

      estimate.atom_size.should eq(64)
      estimate.truth_value_size.should eq(32)
      estimate.name_size.should eq("memory_test_node".bytesize + 8)
      estimate.outgoing_size.should eq(0)
      estimate.total_size.should eq(
        estimate.atom_size + estimate.truth_value_size + estimate.name_size + estimate.outgoing_size
      )
    end

    it "estimates memory for a link including outgoing set" do
      atomspace = AtomSpace::AtomSpace.new
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      link = atomspace.add_inheritance_link(a, b)

      estimate = CogUtil::MemoryProfiler.estimate_atom_memory(link)

      estimate.atom_size.should eq(64)
      estimate.outgoing_size.should eq(link.outgoing.size * 8)
      estimate.total_size.should be > estimate.atom_size
    end
  end

  describe ".benchmark_memory" do
    it "benchmarks a block that returns an Int32 atom count" do
      result = CogUtil::MemoryProfiler.benchmark_memory("int_count_op") do
        5
      end

      result.operation.should eq("int_count_op")
      result.atom_count.should eq(5)
      result.duration_ms.should be >= 0.0
      result.initial_memory.should be_a(CogUtil::MemoryProfiler::SystemMemoryInfo)
      result.final_memory.should be_a(CogUtil::MemoryProfiler::SystemMemoryInfo)
    end

    it "benchmarks a block that returns a sized collection" do
      result = CogUtil::MemoryProfiler.benchmark_memory("array_op") do
        Array(Int32).new(3) { |i| i }
      end

      result.atom_count.should eq(3)
      result.operation.should eq("array_op")
    end

    it "uses zero atom count when the block result has no size" do
      result = CogUtil::MemoryProfiler.benchmark_memory("bool_op") do
        true
      end

      result.atom_count.should eq(0)
      result.memory_per_atom.should eq(0.0)
    end
  end

  describe ".evaluate_memory_efficiency" do
    it "treats empty workloads as meeting the C++ target" do
      initial = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        100_i64, 200_i64, 100_i64, 80_i64, 80_i64, 20_i64
      )
      final = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        100_i64, 200_i64, 100_i64, 80_i64, 80_i64, 20_i64
      )
      result = CogUtil::MemoryProfiler::MemoryBenchmarkResult.new(
        "empty", initial, final, 0, 10.0
      )

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)

      evaluation["meets_cpp_target"].should eq(true)
      evaluation["memory_per_atom"].should eq(0.0)
      evaluation["meets_performance_target"].should eq(true)
      evaluation["is_efficient"].should eq(true)
      evaluation["memory_efficiency"].should eq(result.memory_efficiency)
    end

    it "allows a higher per-atom budget for small batches" do
      initial = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        1000_i64, 2000_i64, 100_i64, 80_i64, 80_i64, 20_i64
      )
      # 4 KB increase for 2 atoms => 2048 bytes/atom (under 8192 small-batch limit)
      final = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        1004_i64, 2000_i64, 100_i64, 90_i64, 90_i64, 10_i64
      )
      result = CogUtil::MemoryProfiler::MemoryBenchmarkResult.new(
        "small_batch", initial, final, 2, 5.0
      )

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)
      evaluation["meets_cpp_target"].should eq(true)
      evaluation["memory_per_atom"].should eq(2048.0)
    end

    it "flags slow operations as missing the performance target" do
      initial = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        100_i64, 200_i64, 100_i64, 80_i64, 80_i64, 20_i64
      )
      final = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        100_i64, 200_i64, 100_i64, 80_i64, 80_i64, 20_i64
      )
      result = CogUtil::MemoryProfiler::MemoryBenchmarkResult.new(
        "slow", initial, final, 0, 1500.0
      )

      evaluation = CogUtil::MemoryProfiler.evaluate_memory_efficiency(result)
      evaluation["meets_performance_target"].should eq(false)
    end
  end

  describe ".generate_memory_report" do
    it "builds a human-readable report with summary" do
      initial = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        1000_i64, 2000_i64, 100_i64, 80_i64, 80_i64, 20_i64
      )
      final = CogUtil::MemoryProfiler::SystemMemoryInfo.new(
        1001_i64, 2000_i64, 100_i64, 90_i64, 90_i64, 10_i64
      )
      results = [
        CogUtil::MemoryProfiler::MemoryBenchmarkResult.new(
          "report_op", initial, final, 10, 3.25
        ),
      ]

      report = CogUtil::MemoryProfiler.generate_memory_report(results)

      report.should contain("Crystal CogUtil Memory Performance Report")
      report.should contain("Operation: report_op")
      report.should contain("Atoms processed: 10")
      report.should contain("Overall Summary:")
      report.should contain("Total atoms processed: 10")
      report.should contain("C++ compatibility:")
      report.should contain("Recommendation:")
    end
  end

  describe ".benchmark_atomspace_scaling" do
    it "returns one result per scale factor" do
      atomspace = AtomSpace::AtomSpace.new
      scale_factors = [5, 10]

      results = CogUtil::MemoryProfiler.benchmark_atomspace_scaling(atomspace, scale_factors)

      results.size.should eq(2)
      results[0].operation.should eq("atomspace_scale_5")
      results[0].atom_count.should eq(5)
      results[1].operation.should eq("atomspace_scale_10")
      results[1].atom_count.should eq(10)
      atomspace.size.should be >= 15
    end
  end

  describe ".detect_memory_leaks" do
    it "returns a boolean for a lightweight workload" do
      has_leak = CogUtil::MemoryProfiler.detect_memory_leaks(20) do
        # Allocate and drop a small temporary array
        Array(Int32).new(10) { |i| i }.sum
      end

      has_leak.should be_a(Bool)
    end
  end
end
