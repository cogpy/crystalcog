require "./performance_profiler"
require "./performance_regression"

# Intelligent optimization recommendation engine
# Analyzes performance data and suggests specific optimizations
module CogUtil
  class OptimizationEngine
    # Optimization recommendation with detailed analysis
    struct Recommendation
      property category : String
      property priority : Int32
      property function_name : String
      property issue_description : String
      property optimization_strategy : String
      property expected_improvement : Float64
      property implementation_difficulty : String
      property code_examples : Array(String)
      property related_functions : Array(String)

      def initialize(@category : String, @priority : Int32, @function_name : String,
                     @issue_description : String, @optimization_strategy : String,
                     @expected_improvement : Float64, @implementation_difficulty : String,
                     @code_examples : Array(String) = Array(String).new,
                     @related_functions : Array(String) = Array(String).new)
      end

      def critical? : Bool
        @priority >= 90
      end

      def high_priority? : Bool
        @priority >= 70
      end
    end

    # Performance pattern analysis result
    struct PerformancePattern
      property pattern_type : String
      property severity : Float64
      property affected_functions : Array(String)
      property pattern_description : String
      property optimization_potential : Float64

      def initialize(@pattern_type : String, @severity : Float64,
                     @affected_functions : Array(String), @pattern_description : String,
                     @optimization_potential : Float64)
      end
    end

    @profiler_session : PerformanceProfiler::Session?
    @regression_detector : PerformanceRegression
    @optimization_rules : Hash(String, Proc(PerformanceProfiler::Metrics, Recommendation?))

    def initialize(regression_detector : PerformanceRegression? = nil)
      @regression_detector = regression_detector || PerformanceRegression.new
      @optimization_rules = Hash(String, Proc(PerformanceProfiler::Metrics, Recommendation?)).new
      initialize_optimization_rules
    end

    # Set the profiler session for optimization analysis
    def profiler_session=(session : PerformanceProfiler::Session?)
      @profiler_session = session
    end

    # Analyze performance data and generate optimization recommendations
    def analyze_and_recommend(session : PerformanceProfiler::Session) : Array(Recommendation)
      @profiler_session = session
      recommendations = Array(Recommendation).new

      # Apply optimization rules to each function
      session.all_metrics.each do |function_name, metrics|
        @optimization_rules.each do |rule_name, rule|
          if recommendation = rule.call(metrics)
            recommendation.function_name = function_name
            recommendations << recommendation
          end
        end
      end

      # Analyze global patterns
      pattern_recommendations = analyze_global_patterns(session)
      recommendations.concat(pattern_recommendations)

      # Sort by priority and expected improvement
      recommendations.sort_by { |r| [-r.priority, -r.expected_improvement] }
    end

    # Generate comprehensive optimization report
    def generate_optimization_report(recommendations : Array(Recommendation)) : String
      String.build do |str|
        str << "CrystalCog Optimization Analysis Report\n"
        str << "=" * 50 << "\n"
        str << "Generated: #{Time.utc}\n"
        str << "Total Recommendations: #{recommendations.size}\n\n"

        if recommendations.empty?
          str << "✅ No optimization opportunities detected!\n"
          str << "Your code appears to be well-optimized.\n"
          return str.to_s
        end

        # Group by priority
        critical = recommendations.select(&.critical?)
        high_priority = recommendations.select(&.high_priority?).reject(&.critical?)
        normal_priority = recommendations.reject(&.high_priority?)

        if critical.any?
          str << "🚨 CRITICAL OPTIMIZATIONS (Immediate Action Required):\n"
          str << "=" * 55 << "\n"
          critical.each { |rec| str << format_recommendation(rec) }
          str << "\n"
        end

        if high_priority.any?
          str << "🔥 HIGH PRIORITY OPTIMIZATIONS:\n"
          str << "=" * 35 << "\n"
          high_priority.each { |rec| str << format_recommendation(rec) }
          str << "\n"
        end

        if normal_priority.any?
          str << "💡 ADDITIONAL OPTIMIZATION OPPORTUNITIES:\n"
          str << "=" * 45 << "\n"
          normal_priority.each { |rec| str << format_recommendation(rec) }
          str << "\n"
        end

        # Summary and quick wins
        str << generate_optimization_summary(recommendations)
      end
    end

    # Analyze code patterns across all functions
    def analyze_global_patterns(session : PerformanceProfiler::Session) : Array(Recommendation)
      patterns = detect_performance_patterns(session)
      recommendations = Array(Recommendation).new

      patterns.each do |pattern|
        case pattern.pattern_type
        when "hot_path_inefficiency"
          recommendations << create_hot_path_recommendation(pattern)
        when "memory_thrashing"
          recommendations << create_memory_optimization_recommendation(pattern)
        when "excessive_allocation"
          recommendations << create_allocation_reduction_recommendation(pattern)
        when "cache_misses"
          recommendations << create_cache_optimization_recommendation(pattern)
        when "unnecessary_computation"
          recommendations << create_computation_optimization_recommendation(pattern)
        end
      end

      recommendations.compact
    end

    # Estimate optimization impact based on function metrics
    def estimate_optimization_impact(function_name : String, optimization_type : String) : Float64
      return 0.0 unless session = @profiler_session
      return 0.0 unless metrics = session.get_metrics(function_name)

      case optimization_type
      when "algorithm_improvement"
        # Estimate based on call frequency and current time
        base_impact = metrics.call_count > 100 ? 0.3 : 0.1
        time_factor = metrics.wall_time > 0.1 ? 0.4 : 0.2
        base_impact + time_factor
      when "memory_optimization"
        # Estimate based on memory usage
        memory_mb = metrics.memory_peak.to_f64 / (1024 * 1024)
        memory_mb > 100 ? 0.4 : memory_mb > 10 ? 0.2 : 0.1
      when "caching"
        # Estimate based on call frequency
        metrics.call_count > 1000 ? 0.6 : metrics.call_count > 100 ? 0.3 : 0.1
      when "concurrency"
        # Estimate based on execution time
        metrics.wall_time > 1.0 ? 0.5 : metrics.wall_time > 0.1 ? 0.3 : 0.1
      else
        0.1
      end
    end

    # Get optimization roadmap prioritized by impact
    def get_optimization_roadmap(recommendations : Array(Recommendation)) : Hash(String, Array(Recommendation))
      roadmap = Hash(String, Array(Recommendation)).new

      # Phase 1: Quick wins (high impact, low difficulty)
      quick_wins = recommendations.select do |r|
        r.expected_improvement > 0.3 && r.implementation_difficulty == "low"
      end
      roadmap["Phase 1: Quick Wins"] = quick_wins

      # Phase 2: High impact optimizations
      high_impact = recommendations.select do |r|
        r.expected_improvement > 0.4 && r.implementation_difficulty != "low" && !quick_wins.includes?(r)
      end
      roadmap["Phase 2: High Impact"] = high_impact

      # Phase 3: Systematic improvements
      systematic = recommendations.reject { |r| quick_wins.includes?(r) || high_impact.includes?(r) }
      roadmap["Phase 3: Systematic Improvements"] = systematic

      roadmap
    end

    private def initialize_optimization_rules
      # High execution time optimization
      @optimization_rules["high_execution_time"] = ->(metrics : PerformanceProfiler::Metrics) {
        if metrics.wall_time > 0.5 && metrics.call_count > 10
          Recommendation.new(
            category: "Performance",
            priority: 85,
            function_name: "",
            issue_description: "Function has high execution time (#{metrics.wall_time.round(4)}s total)",
            optimization_strategy: "Algorithm optimization, profiling, or parallelization",
            expected_improvement: estimate_time_improvement(metrics),
            implementation_difficulty: "medium",
            code_examples: [
              "# Consider algorithmic improvements",
              "# Profile hot code paths with --profile",
              "# Use Channel(T) for parallel processing",
              "# Cache expensive computations",
            ]
          )
        end
      }

      # High memory usage optimization
      @optimization_rules["high_memory_usage"] = ->(metrics : PerformanceProfiler::Metrics) {
        memory_mb = metrics.memory_peak.to_f64 / (1024 * 1024)
        if memory_mb > 100
          Recommendation.new(
            category: "Memory",
            priority: 80,
            function_name: "",
            issue_description: "High memory usage (#{memory_mb.round(2)} MB peak)",
            optimization_strategy: "Memory pooling, object reuse, or streaming",
            expected_improvement: 0.4,
            implementation_difficulty: "medium",
            code_examples: [
              "# Use object pooling for frequent allocations",
              "# Consider streaming for large data sets",
              "# Use Slice(T) instead of Array(T) when possible",
              "# Implement lazy loading for large objects",
            ]
          )
        end
      }

      # High call frequency optimization
      @optimization_rules["high_call_frequency"] = ->(metrics : PerformanceProfiler::Metrics) {
        if metrics.call_count > 10000
          avg_time = metrics.wall_time / metrics.call_count
          if avg_time > 0.001 # More than 1ms per call
            Recommendation.new(
              category: "Caching",
              priority: 75,
              function_name: "",
              issue_description: "Function called very frequently (#{metrics.call_count} times) with significant per-call cost",
              optimization_strategy: "Implement caching or memoization",
              expected_improvement: 0.6,
              implementation_difficulty: "low",
              code_examples: [
                "# Implement result caching",
                "@cache = Hash(InputType, ResultType).new",
                "def cached_method(input)",
                "  @cache[input] ||= expensive_computation(input)",
                "end",
              ]
            )
          end
        end
      }

      # Error-prone function optimization
      @optimization_rules["error_prone"] = ->(metrics : PerformanceProfiler::Metrics) {
        if metrics.errors > 0 && metrics.call_count > 0
          error_rate = (metrics.errors.to_f64 / metrics.call_count.to_f64) * 100
          if error_rate > 5.0
            Recommendation.new(
              category: "Reliability",
              priority: 90,
              function_name: "",
              issue_description: "High error rate (#{error_rate.round(2)}%)",
              optimization_strategy: "Improve error handling and input validation",
              expected_improvement: 0.3,
              implementation_difficulty: "medium",
              code_examples: [
                "# Add comprehensive input validation",
                "# Use Result(T, E) for error handling",
                "# Implement circuit breaker pattern",
                "# Add defensive programming checks",
              ]
            )
          end
        end
      }

      # GC pressure optimization
      @optimization_rules["gc_pressure"] = ->(metrics : PerformanceProfiler::Metrics) {
        if metrics.gc_time > metrics.wall_time * 0.1 # GC takes more than 10% of time
          Recommendation.new(
            category: "Memory",
            priority: 70,
            function_name: "",
            issue_description: "High GC pressure (#{(metrics.gc_time / metrics.wall_time * 100).round(1)}% of execution time)",
            optimization_strategy: "Reduce allocations and object churn",
            expected_improvement: 0.3,
            implementation_difficulty: "medium",
            code_examples: [
              "# Use object pooling",
              "# Reuse buffers and arrays",
              "# Prefer value types over reference types",
              "# Use StaticArray for fixed-size collections",
            ]
          )
        end
      }
    end

    private def detect_performance_patterns(session : PerformanceProfiler::Session) : Array(PerformancePattern)
      patterns = Array(PerformancePattern).new
      all_metrics = session.all_metrics

      # Detect hot path inefficiency
      total_time = all_metrics.values.sum(&.wall_time)
      hot_functions = all_metrics.select { |name, metrics| metrics.wall_time > total_time * 0.1 }

      if hot_functions.any?
        patterns << PerformancePattern.new(
          pattern_type: "hot_path_inefficiency",
          severity: hot_functions.size > 3 ? 0.8 : 0.5,
          affected_functions: hot_functions.keys,
          pattern_description: "Functions consuming significant execution time",
          optimization_potential: 0.6
        )
      end

      # Detect memory thrashing
      high_memory_functions = all_metrics.select { |name, metrics|
        metrics.memory_peak > 50_000_000 # > 50MB
      }

      if high_memory_functions.size > 2
        patterns << PerformancePattern.new(
          pattern_type: "memory_thrashing",
          severity: 0.7,
          affected_functions: high_memory_functions.keys,
          pattern_description: "Multiple functions with high memory usage",
          optimization_potential: 0.5
        )
      end

      # Detect excessive allocation pattern
      frequent_callers = all_metrics.select { |name, metrics| metrics.call_count > 1000 }
      if frequent_callers.size > 5
        patterns << PerformancePattern.new(
          pattern_type: "excessive_allocation",
          severity: 0.6,
          affected_functions: frequent_callers.keys,
          pattern_description: "Many functions called very frequently",
          optimization_potential: 0.4
        )
      end

      patterns
    end

    private def create_hot_path_recommendation(pattern : PerformancePattern) : Recommendation
      Recommendation.new(
        category: "Architecture",
        priority: 88,
        function_name: pattern.affected_functions.join(", "),
        issue_description: "Hot path detected: #{pattern.pattern_description}",
        optimization_strategy: "Profile and optimize critical path, consider async processing",
        expected_improvement: pattern.optimization_potential,
        implementation_difficulty: "high",
        code_examples: [
          "# Profile hot paths with sampling profiler",
          "# Consider breaking up monolithic functions",
          "# Use async/await for I/O bound operations",
          "# Implement lazy evaluation where possible",
        ],
        related_functions: pattern.affected_functions
      )
    end

    private def create_memory_optimization_recommendation(pattern : PerformancePattern) : Recommendation
      Recommendation.new(
        category: "Memory",
        priority: 82,
        function_name: pattern.affected_functions.join(", "),
        issue_description: "Memory thrashing pattern detected",
        optimization_strategy: "Implement memory pooling and reduce object creation",
        expected_improvement: pattern.optimization_potential,
        implementation_difficulty: "medium",
        code_examples: [
          "# Implement global memory pools",
          "# Use object recycling patterns",
          "# Consider streaming for large datasets",
          "# Use weak references where appropriate",
        ],
        related_functions: pattern.affected_functions
      )
    end

    private def create_allocation_reduction_recommendation(pattern : PerformancePattern) : Recommendation
      Recommendation.new(
        category: "Memory",
        priority: 75,
        function_name: pattern.affected_functions.join(", "),
        issue_description: "High allocation rate detected",
        optimization_strategy: "Reduce object allocations through reuse and pooling",
        expected_improvement: pattern.optimization_potential,
        implementation_difficulty: "medium",
        code_examples: [
          "# Cache and reuse expensive objects",
          "# Use buffer pools for temporary allocations",
          "# Prefer stack allocation with StaticArray",
          "# Implement copy-on-write semantics",
        ],
        related_functions: pattern.affected_functions
      )
    end

    private def create_cache_optimization_recommendation(pattern : PerformancePattern) : Recommendation
      Recommendation.new(
        category: "Caching",
        priority: 78,
        function_name: pattern.affected_functions.join(", "),
        issue_description: "Cache miss pattern detected",
        optimization_strategy: "Implement intelligent caching strategies",
        expected_improvement: pattern.optimization_potential,
        implementation_difficulty: "low",
        code_examples: [
          "# Implement LRU cache for frequently accessed data",
          "# Use memoization for pure functions",
          "# Consider bloom filters for existence checks",
          "# Implement cache warming strategies",
        ],
        related_functions: pattern.affected_functions
      )
    end

    private def create_computation_optimization_recommendation(pattern : PerformancePattern) : Recommendation
      Recommendation.new(
        category: "Algorithm",
        priority: 80,
        function_name: pattern.affected_functions.join(", "),
        issue_description: "Unnecessary computation detected",
        optimization_strategy: "Optimize algorithms and reduce redundant calculations",
        expected_improvement: pattern.optimization_potential,
        implementation_difficulty: "high",
        code_examples: [
          "# Analyze algorithm complexity (Big O)",
          "# Use more efficient data structures",
          "# Implement early termination conditions",
          "# Consider approximation algorithms for acceptable trade-offs",
        ],
        related_functions: pattern.affected_functions
      )
    end

    private def estimate_time_improvement(metrics : PerformanceProfiler::Metrics) : Float64
      # Estimate improvement based on current performance characteristics
      if metrics.wall_time > 2.0
        0.6 # High potential for improvement
      elsif metrics.wall_time > 0.5
        0.4 # Medium potential
      elsif metrics.call_count > 10000
        0.3 # Frequent calls, good caching potential
      else
        0.2 # Lower potential
      end
    end

    private def format_recommendation(rec : Recommendation) : String
      String.build do |str|
        str << "#{rec.category.upcase}: #{rec.function_name}\n"
        str << "Priority: #{rec.priority}/100, Expected Improvement: #{(rec.expected_improvement * 100).round(1)}%\n"
        str << "Difficulty: #{rec.implementation_difficulty.capitalize}\n"
        str << "\nIssue: #{rec.issue_description}\n"
        str << "Strategy: #{rec.optimization_strategy}\n"

        if rec.code_examples.any?
          str << "\nCode Examples:\n"
          rec.code_examples.each { |example| str << "#{example}\n" }
        end

        if rec.related_functions.any?
          str << "\nRelated Functions: #{rec.related_functions.join(", ")}\n"
        end

        str << "\n" + "-" * 60 + "\n\n"
      end
    end

    private def generate_optimization_summary(recommendations : Array(Recommendation)) : String
      String.build do |str|
        str << "OPTIMIZATION SUMMARY:\n"
        str << "=" * 25 << "\n"

        # Calculate potential improvements
        total_improvement = recommendations.sum(&.expected_improvement)
        categories = recommendations.group_by(&.category)

        str << "Potential Total Improvement: #{(total_improvement * 100).round(1)}%\n"
        str << "Optimization Categories:\n"

        categories.each do |category, recs|
          avg_improvement = recs.sum(&.expected_improvement) / recs.size
          str << "  #{category}: #{recs.size} recommendations (avg #{(avg_improvement * 100).round(1)}% improvement)\n"
        end

        str << "\nQuick Wins (Low effort, high impact):\n"
        quick_wins = recommendations.select { |r| r.implementation_difficulty == "low" && r.expected_improvement > 0.3 }
        if quick_wins.any?
          quick_wins.each { |r| str << "  • #{r.function_name}: #{r.optimization_strategy}\n" }
        else
          str << "  No quick wins identified\n"
        end

        str << "\nNext Steps:\n"
        str << "1. Address critical issues first (priority >= 90)\n"
        str << "2. Implement quick wins for immediate impact\n"
        str << "3. Plan systematic optimization phases\n"
        str << "4. Measure and validate improvements\n"
      end
    end
  end
end
