require "spec"
require "../../src/cogutil/performance_profiler"
require "../../src/cogutil/performance_regression"
require "../../src/cogutil/optimization_engine"

# Unit coverage for CogUtil::OptimizationEngine
# (required path: spec/cogutil/optimization_engine_spec.cr)
describe CogUtil::OptimizationEngine do
  # Build a profiler session with deterministic metrics so rules can be tested
  # without depending on wall-clock sleeps.
  def self.build_session(entries : Hash(String, NamedTuple(
    wall_time: Float64,
    call_count: UInt64,
    memory_peak: UInt64,
    gc_time: Float64,
    errors: UInt64
  ))) : CogUtil::PerformanceProfiler::Session
    session = CogUtil::PerformanceProfiler::Session.new
    entries.each do |name, values|
      session.start_profile(name)
      session.end_profile(name)
      metrics = session.get_metrics(name).not_nil!
      metrics.wall_time = values[:wall_time]
      metrics.call_count = values[:call_count]
      metrics.memory_peak = values[:memory_peak]
      metrics.gc_time = values[:gc_time]
      metrics.errors = values[:errors]
    end
    session
  end

  describe "Recommendation" do
    it "reports critical and high priority thresholds" do
      critical = CogUtil::OptimizationEngine::Recommendation.new(
        category: "Reliability",
        priority: 90,
        function_name: "f",
        issue_description: "issue",
        optimization_strategy: "fix",
        expected_improvement: 0.3,
        implementation_difficulty: "medium"
      )
      high = CogUtil::OptimizationEngine::Recommendation.new(
        category: "Performance",
        priority: 70,
        function_name: "g",
        issue_description: "issue",
        optimization_strategy: "fix",
        expected_improvement: 0.2,
        implementation_difficulty: "low"
      )
      normal = CogUtil::OptimizationEngine::Recommendation.new(
        category: "Memory",
        priority: 50,
        function_name: "h",
        issue_description: "issue",
        optimization_strategy: "fix",
        expected_improvement: 0.1,
        implementation_difficulty: "high"
      )

      critical.critical?.should be_true
      critical.high_priority?.should be_true
      high.critical?.should be_false
      high.high_priority?.should be_true
      normal.critical?.should be_false
      normal.high_priority?.should be_false
    end

    it "defaults code_examples and related_functions to empty arrays" do
      rec = CogUtil::OptimizationEngine::Recommendation.new(
        category: "Performance",
        priority: 10,
        function_name: "noop",
        issue_description: "none",
        optimization_strategy: "n/a",
        expected_improvement: 0.0,
        implementation_difficulty: "low"
      )
      rec.code_examples.should be_empty
      rec.related_functions.should be_empty
    end
  end

  describe "PerformancePattern" do
    it "stores pattern analysis fields" do
      pattern = CogUtil::OptimizationEngine::PerformancePattern.new(
        pattern_type: "hot_path_inefficiency",
        severity: 0.8,
        affected_functions: ["a", "b"],
        pattern_description: "hot path",
        optimization_potential: 0.6
      )

      pattern.pattern_type.should eq("hot_path_inefficiency")
      pattern.severity.should eq(0.8)
      pattern.affected_functions.should eq(["a", "b"])
      pattern.pattern_description.should eq("hot path")
      pattern.optimization_potential.should eq(0.6)
    end
  end

  describe "initialization" do
    it "creates an engine with default regression detector" do
      engine = CogUtil::OptimizationEngine.new
      engine.should_not be_nil
    end

    it "accepts an injected regression detector" do
      regression = CogUtil::PerformanceRegression.new("/tmp/opt_engine_unit_spec.json")
      engine = CogUtil::OptimizationEngine.new(regression)
      engine.should_not be_nil
    end
  end

  describe "#analyze_and_recommend" do
    it "returns empty recommendations for well-behaved metrics" do
      session = build_session({
        "healthy" => {
          wall_time:   0.001,
          call_count:  1_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      recommendations = engine.analyze_and_recommend(session)
      recommendations.should be_a(Array(CogUtil::OptimizationEngine::Recommendation))
      recommendations.should be_empty
    end

    it "recommends for high execution time" do
      session = build_session({
        "slow_fn" => {
          wall_time:   1.0,
          call_count:  20_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      recommendations = engine.analyze_and_recommend(session)

      slow = recommendations.select { |r| r.function_name.includes?("slow_fn") }
      slow.should_not be_empty
      slow.any? { |r| r.category == "Performance" }.should be_true
    end

    it "recommends for high memory usage" do
      session = build_session({
        "mem_fn" => {
          wall_time:   0.01,
          call_count:  5_u64,
          memory_peak: 150_000_000_u64, # > 100 MB
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      recommendations = engine.analyze_and_recommend(session)

      mem = recommendations.select { |r| r.function_name.includes?("mem_fn") && r.category == "Memory" }
      mem.should_not be_empty
      mem.first.priority.should eq(80)
    end

    it "recommends caching for high call frequency with costly calls" do
      session = build_session({
        "hot_fn" => {
          wall_time:   20.0, # avg > 1ms per call with 10001 calls
          call_count:  10_001_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      recommendations = engine.analyze_and_recommend(session)

      cache = recommendations.select { |r| r.category == "Caching" }
      cache.should_not be_empty
      cache.first.implementation_difficulty.should eq("low")
    end

    it "recommends reliability fixes for high error rates" do
      session = build_session({
        "flaky_fn" => {
          wall_time:   0.05,
          call_count:  100_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      10_u64, # 10% error rate
        },
      })

      engine = CogUtil::OptimizationEngine.new
      recommendations = engine.analyze_and_recommend(session)

      reliability = recommendations.select { |r| r.category == "Reliability" }
      reliability.should_not be_empty
      reliability.first.critical?.should be_true
    end

    it "recommends reducing allocations under GC pressure" do
      session = build_session({
        "gc_fn" => {
          wall_time:   1.0,
          call_count:  5_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.2, # 20% of wall time
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      recommendations = engine.analyze_and_recommend(session)

      gc_recs = recommendations.select { |r|
        r.function_name.includes?("gc_fn") && r.issue_description.includes?("GC pressure")
      }
      gc_recs.should_not be_empty
    end

    it "sorts recommendations by priority then expected improvement" do
      session = build_session({
        "flaky" => {
          wall_time:   0.05,
          call_count:  100_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      10_u64,
        },
        "slow" => {
          wall_time:   1.0,
          call_count:  20_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      recommendations = engine.analyze_and_recommend(session)
      recommendations.size.should be > 1

      priorities = recommendations.map(&.priority)
      priorities.should eq(priorities.sort_by { |p| -p })
    end

    it "detects hot path global patterns" do
      session = build_session({
        "hot" => {
          wall_time:   5.0,
          call_count:  10_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
        "cold" => {
          wall_time:   0.1,
          call_count:  2_u64,
          memory_peak: 1_024_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      pattern_recs = engine.analyze_global_patterns(session)
      pattern_recs.any? { |r| r.category == "Architecture" }.should be_true
      pattern_recs.any? { |r| r.issue_description.includes?("Hot path") }.should be_true
    end
  end

  describe "#generate_optimization_report" do
    it "reports when there are no recommendations" do
      engine = CogUtil::OptimizationEngine.new
      report = engine.generate_optimization_report([] of CogUtil::OptimizationEngine::Recommendation)

      report.should contain("Optimization Analysis Report")
      report.should contain("Total Recommendations: 0")
      report.should contain("No optimization opportunities detected")
    end

    it "groups critical, high, and normal priority recommendations" do
      recommendations = [
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Reliability",
          priority: 95,
          function_name: "critical_fn",
          issue_description: "critical issue",
          optimization_strategy: "fix now",
          expected_improvement: 0.5,
          implementation_difficulty: "medium",
          code_examples: ["# fix"]
        ),
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Performance",
          priority: 80,
          function_name: "high_fn",
          issue_description: "high issue",
          optimization_strategy: "optimize",
          expected_improvement: 0.4,
          implementation_difficulty: "low"
        ),
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Memory",
          priority: 40,
          function_name: "normal_fn",
          issue_description: "normal issue",
          optimization_strategy: "later",
          expected_improvement: 0.1,
          implementation_difficulty: "high"
        ),
      ]

      engine = CogUtil::OptimizationEngine.new
      report = engine.generate_optimization_report(recommendations)

      report.should contain("CRITICAL OPTIMIZATIONS")
      report.should contain("HIGH PRIORITY OPTIMIZATIONS")
      report.should contain("ADDITIONAL OPTIMIZATION OPPORTUNITIES")
      report.should contain("critical_fn")
      report.should contain("high_fn")
      report.should contain("normal_fn")
      report.should contain("OPTIMIZATION SUMMARY")
      report.should contain("Quick Wins")
    end
  end

  describe "#estimate_optimization_impact" do
    it "returns 0.0 without a profiler session" do
      engine = CogUtil::OptimizationEngine.new
      engine.estimate_optimization_impact("missing", "caching").should eq(0.0)
    end

    it "returns 0.0 for unknown function names" do
      session = build_session({
        "known" => {
          wall_time:   0.5,
          call_count:  200_u64,
          memory_peak: 20_000_000_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      engine.profiler_session = session
      engine.estimate_optimization_impact("unknown", "caching").should eq(0.0)
    end

    it "estimates impact for known optimization types" do
      session = build_session({
        "target" => {
          wall_time:   1.5,
          call_count:  1500_u64,
          memory_peak: 120_000_000_u64,
          gc_time:     0.0,
          errors:      0_u64,
        },
      })

      engine = CogUtil::OptimizationEngine.new
      engine.profiler_session = session

      algorithm = engine.estimate_optimization_impact("target", "algorithm_improvement")
      memory = engine.estimate_optimization_impact("target", "memory_optimization")
      caching = engine.estimate_optimization_impact("target", "caching")
      concurrency = engine.estimate_optimization_impact("target", "concurrency")
      other = engine.estimate_optimization_impact("target", "unknown_type")

      algorithm.should be > 0.0
      memory.should eq(0.4)
      caching.should eq(0.6)
      concurrency.should eq(0.5)
      other.should eq(0.1)

      [algorithm, memory, caching, concurrency, other].each do |impact|
        impact.should be <= 1.0
      end
    end
  end

  describe "#get_optimization_roadmap" do
    it "partitions recommendations into quick wins, high impact, and systematic phases" do
      recommendations = [
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Caching",
          priority: 75,
          function_name: "quick_win",
          issue_description: "cache me",
          optimization_strategy: "memoize",
          expected_improvement: 0.5,
          implementation_difficulty: "low"
        ),
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Architecture",
          priority: 88,
          function_name: "high_impact",
          issue_description: "refactor hot path",
          optimization_strategy: "rewrite",
          expected_improvement: 0.6,
          implementation_difficulty: "high"
        ),
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Memory",
          priority: 40,
          function_name: "systematic",
          issue_description: "minor cleanup",
          optimization_strategy: "tweak",
          expected_improvement: 0.1,
          implementation_difficulty: "medium"
        ),
      ]

      engine = CogUtil::OptimizationEngine.new
      roadmap = engine.get_optimization_roadmap(recommendations)

      roadmap.has_key?("Phase 1: Quick Wins").should be_true
      roadmap.has_key?("Phase 2: High Impact").should be_true
      roadmap.has_key?("Phase 3: Systematic Improvements").should be_true

      roadmap["Phase 1: Quick Wins"].map(&.function_name).should eq(["quick_win"])
      roadmap["Phase 2: High Impact"].map(&.function_name).should eq(["high_impact"])
      roadmap["Phase 3: Systematic Improvements"].map(&.function_name).should eq(["systematic"])
    end
  end
end
