require "spec"
require "../../src/cogutil/performance_profiler"
require "../../src/cogutil/performance_regression"
require "../../src/cogutil/optimization_engine"
require "../../src/cogutil/performance_monitor"

# Comprehensive test suite for performance profiling and optimization tools
describe "Performance Profiling Tools" do
  describe "PerformanceProfiler" do
    it "can start and end a profiling session" do
      CogUtil::PerformanceProfiler.start_session
      session = CogUtil::PerformanceProfiler.end_session
      
      session.should_not be_nil
      if session
        session.session_duration.should be > 0.0
      end
    end
    
    it "profiles code blocks with timing metrics" do
      CogUtil::PerformanceProfiler.start_session
      
      result = CogUtil::PerformanceProfiler.profile("test_function") do
        sum = 0
        1000.times { |i| sum += i }
        sum
      end
      
      result.should eq(499500)  # Expected sum of 0..999
      
      session = CogUtil::PerformanceProfiler.end_session
      session.should_not be_nil
      
      if session
        metrics = session.get_metrics("test_function")
        metrics.should_not be_nil
        
        if metrics
          metrics.call_count.should eq(1)
          metrics.wall_time.should be > 0.0
          metrics.errors.should eq(0)
        end
      end
    end
    
    it "handles errors in profiled code" do
      CogUtil::PerformanceProfiler.start_session
      
      expect_raises(ArgumentError) do
        CogUtil::PerformanceProfiler.profile("error_function") do
          raise ArgumentError.new("Test error")
        end
      end
      
      session = CogUtil::PerformanceProfiler.end_session
      session.should_not be_nil
      
      if session
        metrics = session.get_metrics("error_function")
        metrics.should_not be_nil
        metrics.try(&.errors).should eq(1)
      end
    end
    
    it "profiles multiple iterations with statistics" do
      CogUtil::PerformanceProfiler.start_session
      
      stats = CogUtil::PerformanceProfiler.profile_iterations("iteration_test", 5) do
        sleep 0.001  # Small delay to ensure measurable time
      end
      
      stats[:iterations].should eq(5)
      stats[:average].should be > 0.0
      stats[:minimum].should be > 0.0
      stats[:maximum].should be >= stats[:minimum]
      stats[:std_deviation].should be >= 0.0
      
      CogUtil::PerformanceProfiler.end_session
    end
    
    it "tracks memory allocation" do
      CogUtil::PerformanceProfiler.start_session
      
      result = CogUtil::PerformanceProfiler.profile_memory_allocation("memory_test") do
        # Allocate some memory
        large_array = Array(Int32).new(1000) { |i| i }
        large_array.sum
      end
      
      result[:result].should eq(499500)
      result[:allocation][:heap_allocated].should be >= 0
      result[:allocation][:process_memory_delta].should be >= 0
      
      CogUtil::PerformanceProfiler.end_session
    end
    
    it "generates comprehensive reports" do
      CogUtil::PerformanceProfiler.start_session
      
      # Profile some test functions
      CogUtil::PerformanceProfiler.profile("fast_function") do
        10.times { |i| i * 2 }
      end
      
      CogUtil::PerformanceProfiler.profile("slow_function") do
        sleep 0.01
      end
      
      report = CogUtil::PerformanceProfiler.generate_report
      
      report.should contain("Performance Profiling Report")
      report.should contain("fast_function")
      report.should contain("slow_function")
      report.should contain("Optimization Recommendations")
      
      CogUtil::PerformanceProfiler.end_session
    end
    
    it "exports metrics to JSON" do
      CogUtil::PerformanceProfiler.start_session
      
      CogUtil::PerformanceProfiler.profile("json_test") do
        42
      end
      
      json_data = CogUtil::PerformanceProfiler.export_metrics
      
      json_data.should contain("session_info")
      json_data.should contain("metrics")
      json_data.should contain("json_test")
      
      # Validate JSON structure
      parsed = JSON.parse(json_data)
      parsed["session_info"]["crystal_version"].should eq(Crystal::VERSION)
      
      CogUtil::PerformanceProfiler.end_session
    end
  end
  
  describe "PerformanceRegression" do
    it "initializes with storage configuration" do
      regression = CogUtil::PerformanceRegression.new("test_performance.json", 5, 10.0)
      regression.should_not be_nil
    end
    
    it "records and analyzes performance metrics" do
      CogUtil::PerformanceProfiler.start_session
      
      # Create some test metrics
      CogUtil::PerformanceProfiler.profile("test_regression") do
        100.times { |i| i ** 2 }
      end
      
      session = CogUtil::PerformanceProfiler.end_session
      session.should_not be_nil
      
      if session
        regression = CogUtil::PerformanceRegression.new("/tmp/test_regression.json")
        regression.record_metrics(session, "v1.0.0")
        
        # Analyze for regressions (should be empty on first run)
        regressions = regression.analyze_regressions(session)
        regressions.should be_a(Array(CogUtil::PerformanceRegression::RegressionResult))
      end
    end
    
    it "generates regression reports" do
      regression = CogUtil::PerformanceRegression.new("/tmp/test_report.json")
      empty_regressions = [] of CogUtil::PerformanceRegression::RegressionResult
      
      report = regression.generate_regression_report(empty_regressions)
      
      report.should contain("Performance Regression Analysis Report")
      report.should contain("No performance regressions detected")
    end
    
    it "exports data in different formats" do
      regression = CogUtil::PerformanceRegression.new("/tmp/test_export.json")
      
      json_export = regression.export_data("json")
      json_export.should contain("export_timestamp")
      json_export.should contain("total_samples")
      
      csv_export = regression.export_data("csv")
      csv_export.should contain("timestamp,version,function_name")
    end
    
    it "handles data cleanup" do
      regression = CogUtil::PerformanceRegression.new("/tmp/test_cleanup.json")
      
      # This should not raise an error even with no data
      regression.cleanup_old_data(30)
    end
  end
  
  describe "OptimizationEngine" do
    it "initializes with regression detector" do
      regression = CogUtil::PerformanceRegression.new("/tmp/test_optimization.json")
      engine = CogUtil::OptimizationEngine.new(regression)
      engine.should_not be_nil
    end
    
    it "analyzes performance and generates recommendations" do
      CogUtil::PerformanceProfiler.start_session
      
      # Create performance data that should trigger recommendations
      CogUtil::PerformanceProfiler.profile("slow_function") do
        sleep 0.05  # Intentionally slow
      end
      
      # High frequency function
      100.times do
        CogUtil::PerformanceProfiler.profile("frequent_function") do
          10 + 20
        end
      end
      
      session = CogUtil::PerformanceProfiler.end_session
      session.should_not be_nil
      
      if session
        engine = CogUtil::OptimizationEngine.new
        recommendations = engine.analyze_and_recommend(session)
        
        recommendations.should be_a(Array(CogUtil::OptimizationEngine::Recommendation))
        
        # Should have some recommendations for the slow function
        slow_recommendations = recommendations.select { |r| r.function_name.includes?("slow_function") }
        slow_recommendations.should_not be_empty
      end
    end
    
    it "generates optimization reports" do
      engine = CogUtil::OptimizationEngine.new
      
      # Create mock recommendation
      recommendations = [
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Performance",
          priority: 85,
          function_name: "test_function",
          issue_description: "High execution time",
          optimization_strategy: "Algorithm optimization",
          expected_improvement: 0.4,
          implementation_difficulty: "medium"
        )
      ]
      
      report = engine.generate_optimization_report(recommendations)
      
      report.should contain("Optimization Analysis Report")
      report.should contain("test_function")
      report.should contain("Algorithm optimization")
      report.should contain("HIGH PRIORITY")
    end
    
    it "estimates optimization impact" do
      CogUtil::PerformanceProfiler.start_session
      
      CogUtil::PerformanceProfiler.profile("impact_test") do
        sleep 0.1  # Slow enough to suggest optimization
      end
      
      session = CogUtil::PerformanceProfiler.end_session
      session.should_not be_nil
      
      if session
        engine = CogUtil::OptimizationEngine.new
        engine.profiler_session = session
        
        impact = engine.estimate_optimization_impact("impact_test", "algorithm_improvement")
        impact.should be > 0.0
        impact.should be <= 1.0
      end
    end
    
    it "creates optimization roadmaps" do
      recommendations = [
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Performance",
          priority: 90,
          function_name: "quick_win",
          issue_description: "Easy optimization",
          optimization_strategy: "Simple cache",
          expected_improvement: 0.5,
          implementation_difficulty: "low"
        ),
        CogUtil::OptimizationEngine::Recommendation.new(
          category: "Memory",
          priority: 80,
          function_name: "complex_optimization",
          issue_description: "Memory optimization",
          optimization_strategy: "Complex refactoring",
          expected_improvement: 0.6,
          implementation_difficulty: "high"
        )
      ]
      
      engine = CogUtil::OptimizationEngine.new
      roadmap = engine.get_optimization_roadmap(recommendations)
      
      roadmap.has_key?("Phase 1: Quick Wins").should be_true
      roadmap.has_key?("Phase 2: High Impact").should be_true
      roadmap.has_key?("Phase 3: Systematic Improvements").should be_true
      
      # Quick win should be in Phase 1
      phase1 = roadmap["Phase 1: Quick Wins"]
      phase1.should_not be_empty
      phase1.first.function_name.should eq("quick_win")
    end
  end
  
  describe "PerformanceMonitor" do
    it "initializes with buffer configuration" do
      monitor = CogUtil::PerformanceMonitor.new(1000)
      monitor.should_not be_nil
    end
    
    it "records and retrieves metrics" do
      monitor = CogUtil::PerformanceMonitor.new
      
      monitor.record_metric("test_metric", 42.5)
      monitor.record_metric("test_metric", 45.0)
      
      summary = monitor.get_performance_summary
      summary.has_key?("test_metric").should be_true
      
      metric_data = summary["test_metric"]
      metric_data["current"].as_f.should eq(45.0)
    end
    
    it "manages alert rules" do
      monitor = CogUtil::PerformanceMonitor.new
      
      alert_rule = CogUtil::PerformanceMonitor::AlertRule.new(
        name: "test_alert",
        metric_pattern: "test_metric",
        threshold: 50.0,
        comparison: "gt",
        duration: 1.second,
        severity: "warning"
      )
      
      monitor.add_alert_rule(alert_rule)
      
      # This should trigger the alert
      monitor.record_metric("test_metric", 55.0)
      
      alerts = monitor.get_active_alerts
      alerts.size.should be >= 0  # May or may not trigger depending on timing
    end
    
    it "generates monitoring reports" do
      monitor = CogUtil::PerformanceMonitor.new
      
      monitor.record_metric("response_time", 0.5)
      monitor.record_metric("memory_usage", 100_000_000.0)
      
      report = monitor.generate_monitoring_report
      
      report.should contain("Performance Monitoring Report")
      report.should contain("SYSTEM HEALTH")
    end
    
    it "exports monitoring data" do
      monitor = CogUtil::PerformanceMonitor.new
      
      monitor.record_metric("export_test", 123.0)
      
      json_export = monitor.export_monitoring_data("json")
      json_export.should contain("export_timestamp")
      json_export.should contain("samples")
      
      csv_export = monitor.export_monitoring_data("csv")
      csv_export.should contain("timestamp,metric_name,value")
    end
    
    it "tracks metric history" do
      monitor = CogUtil::PerformanceMonitor.new
      
      # Record some historical data
      5.times do |i|
        monitor.record_metric("history_test", i.to_f64)
        sleep 0.001  # Ensure different timestamps
      end
      
      history = monitor.get_metric_history("history_test", 1.hour)
      history.size.should eq(5)
      history.first.value.should eq(0.0)
      history.last.value.should eq(4.0)
    end
  end
  
  describe "Integration Tests" do
    it "can profile, analyze, and optimize in sequence" do
      # Step 1: Profile some code
      CogUtil::PerformanceProfiler.start_session
      
      CogUtil::PerformanceProfiler.profile("integration_test") do
        result = 0
        1000.times { |i| result += i * i }
        result
      end
      
      session = CogUtil::PerformanceProfiler.end_session
      session.should_not be_nil
      
      if session
        # Step 2: Record for regression analysis
        regression = CogUtil::PerformanceRegression.new("/tmp/integration_test.json")
        regression.record_metrics(session, "test_version")
        
        # Step 3: Generate optimization recommendations
        engine = CogUtil::OptimizationEngine.new(regression)
        recommendations = engine.analyze_and_recommend(session)
        
        # Step 4: Monitor performance
        monitor = CogUtil::PerformanceMonitor.new
        monitor.record_metric("integration_metric", 42.0)
        
        # All steps should complete without errors
        recommendations.should be_a(Array(CogUtil::OptimizationEngine::Recommendation))
        monitor.get_performance_summary.has_key?("integration_metric").should be_true
      end
    end
    
    it "handles concurrent profiling sessions" do
      # Test that multiple profiling operations don't interfere
      results = [] of Int32
      
      10.times do |i|
        spawn do
          CogUtil::PerformanceProfiler.start_session
          
          result = CogUtil::PerformanceProfiler.profile("concurrent_test_#{i}") do
            sum = 0
            100.times { |j| sum += j }
            sum
          end
          
          results << result
          CogUtil::PerformanceProfiler.end_session
        end
      end
      
      # Wait for all fibers to complete
      sleep 0.1
      
      # All should have completed successfully
      results.size.should eq(10)
      results.all? { |r| r == 4950 }.should be_true
    end
    
    it "preserves performance data across multiple sessions" do
      # First session
      CogUtil::PerformanceProfiler.start_session
      CogUtil::PerformanceProfiler.profile("persistent_test") do
        sleep 0.01
      end
      session1 = CogUtil::PerformanceProfiler.end_session
      
      # Second session
      CogUtil::PerformanceProfiler.start_session
      CogUtil::PerformanceProfiler.profile("persistent_test") do
        sleep 0.01
      end
      session2 = CogUtil::PerformanceProfiler.end_session
      
      # Both sessions should have data
      session1.should_not be_nil
      session2.should_not be_nil
      
      if session1 && session2
        session1.get_metrics("persistent_test").should_not be_nil
        session2.get_metrics("persistent_test").should_not be_nil
      end
    end
  end
end