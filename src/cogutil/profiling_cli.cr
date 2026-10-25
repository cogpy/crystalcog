require "option_parser"
require "colorize"
require "./performance_profiler"
require "./performance_regression"
require "./optimization_engine"
require "./performance_monitor"

# Comprehensive performance profiling command-line interface
# Provides easy access to all profiling and optimization tools
module CogUtil
  class ProfilingCLI
    @profiler_session : PerformanceProfiler::Session?
    @regression_detector : PerformanceRegression?
    @optimization_engine : OptimizationEngine?
    @monitor : PerformanceMonitor?
    @output_format : String = "text"
    @verbose : Bool = false

    def initialize
      setup_signal_handlers
    end

    def run(args : Array(String))
      command = ""
      options = Hash(String, String).new

      parser = OptionParser.new do |parser|
        parser.banner = "CrystalCog Performance Profiling Tools\n\nUsage: profiler [command] [options]"

        parser.on("profile", "Start a profiling session") do
          command = "profile"

          parser.on("--output FILE", "Output file for profiling results") do |file|
            options["output"] = file
          end

          parser.on("--format FORMAT", "Output format (text, json, html)") do |format|
            @output_format = format
          end

          parser.on("--duration SECONDS", "Profiling duration in seconds") do |duration|
            options["duration"] = duration
          end
        end

        parser.on("analyze", "Analyze existing profiling data") do
          command = "analyze"

          parser.on("--input FILE", "Input profiling data file") do |file|
            options["input"] = file
          end

          parser.on("--baseline FILE", "Baseline data for regression analysis") do |file|
            options["baseline"] = file
          end
        end

        parser.on("monitor", "Start real-time performance monitoring") do
          command = "monitor"

          parser.on("--port PORT", "Dashboard port (default: 8080)") do |port|
            options["port"] = port
          end

          parser.on("--interval SECONDS", "Monitoring interval (default: 1)") do |interval|
            options["interval"] = interval
          end

          parser.on("--alerts FILE", "Alert configuration file") do |file|
            options["alerts"] = file
          end
        end

        parser.on("optimize", "Generate optimization recommendations") do
          command = "optimize"

          parser.on("--input FILE", "Input profiling data file") do |file|
            options["input"] = file
          end

          parser.on("--priority LEVEL", "Minimum priority level (1-100)") do |level|
            options["priority"] = level
          end
        end

        parser.on("compare", "Compare performance between versions") do
          command = "compare"

          parser.on("--baseline FILE", "Baseline performance data") do |file|
            options["baseline"] = file
          end

          parser.on("--current FILE", "Current performance data") do |file|
            options["current"] = file
          end
        end

        parser.on("benchmark", "Run built-in benchmarks") do
          command = "benchmark"

          parser.on("--suite SUITE", "Benchmark suite to run") do |suite|
            options["suite"] = suite
          end

          parser.on("--iterations N", "Number of iterations") do |n|
            options["iterations"] = n
          end
        end

        parser.on("report", "Generate performance report") do
          command = "report"

          parser.on("--template TEMPLATE", "Report template") do |template|
            options["template"] = template
          end

          parser.on("--period DAYS", "Report period in days") do |days|
            options["period"] = days
          end
        end

        parser.on("-v", "--verbose", "Verbose output") do
          @verbose = true
        end

        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit(0)
        end

        parser.on("--version", "Show version information") do
          show_version
          exit(0)
        end
      end

      begin
        parser.parse(args)

        if command.empty?
          puts parser
          exit(1)
        end

        execute_command(command, options)
      rescue ex : OptionParser::InvalidOption
        puts "Error: #{ex.message}".colorize(:red)
        puts parser
        exit(1)
      rescue ex
        puts "Error: #{ex.message}".colorize(:red)
        exit(1)
      end
    end

    private def execute_command(command : String, options : Hash(String, String))
      case command
      when "profile"
        run_profiling_session(options)
      when "analyze"
        analyze_profiling_data(options)
      when "monitor"
        start_monitoring(options)
      when "optimize"
        generate_optimizations(options)
      when "compare"
        compare_performance(options)
      when "benchmark"
        run_benchmarks(options)
      when "report"
        generate_report(options)
      else
        puts "Unknown command: #{command}".colorize(:red)
        exit(1)
      end
    end

    private def run_profiling_session(options : Hash(String, String))
      puts "🚀 Starting Performance Profiling Session".colorize(:green)

      duration = options["duration"]?.try(&.to_i?) || 60
      output_file = options["output"]? || "profile_#{Time.utc.to_unix}.#{@output_format}"

      PerformanceProfiler.start_session

      puts "Profiling for #{duration} seconds..."
      puts "Press Ctrl+C to stop early"

      # Example profiling - in real usage, this would profile the actual application
      start_time = Time.instant

      while (Time.instant - start_time).total_seconds < duration
        # Simulate some work to profile
        PerformanceProfiler.profile("example_computation") do
          result = 0
          1000.times { |i| result += i * i }
          result
        end

        PerformanceProfiler.profile("example_memory_allocation") do
          large_array = Array(Int32).new(1000) { |i| i }
          large_array.sum
        end

        sleep 0.1.seconds
      end

      session = PerformanceProfiler.end_session

      if session
        save_profiling_results(session, output_file)
        puts "Profiling complete! Results saved to #{output_file}".colorize(:green)

        if @verbose
          puts PerformanceProfiler.generate_report
        end
      else
        puts "Error: No profiling session data available".colorize(:red)
      end
    end

    private def analyze_profiling_data(options : Hash(String, String))
      puts "🔍 Analyzing Profiling Data".colorize(:blue)

      input_file = options["input"]?
      unless input_file && File.exists?(input_file)
        puts "Error: Input file not found or not specified".colorize(:red)
        return
      end

      puts "Loading profiling data from #{input_file}..."
      return unless session = load_session(input_file)

      @regression_detector = PerformanceRegression.new

      if baseline_file = options["baseline"]?
        puts "Performing regression analysis against baseline: #{baseline_file}"
        return unless baseline = load_session(baseline_file)
        regressions = @regression_detector.not_nil!.compare_sessions(baseline, session)
        if regressions.empty?
          puts "✅ No regressions against baseline".colorize(:green)
        else
          puts @regression_detector.not_nil!.generate_regression_report(regressions)
        end
      else
        puts "No baseline specified, performing standalone analysis"
        print_session_summary(session)
      end

      puts "Analysis complete!".colorize(:green)
    end

    private def start_monitoring(options : Hash(String, String))
      puts "📊 Starting Real-time Performance Monitoring".colorize(:cyan)

      port = options["port"]?.try(&.to_i?) || 8080
      interval = options["interval"]?.try(&.to_i?) || 1

      @monitor = PerformanceMonitor.new

      # Load custom alert rules if specified
      if alerts_file = options["alerts"]?
        load_alert_configuration(alerts_file)
      end

      puts "Starting dashboard on port #{port}..."
      @monitor.try(&.start_dashboard(port))

      puts "Starting monitoring with #{interval}s interval..."
      @monitor.try(&.start_monitoring(interval.seconds))

      puts "Performance monitoring active!".colorize(:green)
      puts "Dashboard: http://localhost:#{port}"
      puts "Press Ctrl+C to stop"

      # Keep the process running
      sleep
    end

    private def generate_optimizations(options : Hash(String, String))
      puts "💡 Generating Optimization Recommendations".colorize(:yellow)

      input_file = options["input"]?
      unless input_file && File.exists?(input_file)
        puts "Error: Input file not found or not specified".colorize(:red)
        return
      end

      min_priority = options["priority"]?.try(&.to_i?) || 0

      # Initialize optimization engine
      @optimization_engine = OptimizationEngine.new

      return unless session = load_session(input_file)

      recommendations = @optimization_engine.try(&.analyze_and_recommend(session)) || [] of OptimizationEngine::Recommendation

      # Filter by priority
      filtered_recommendations = recommendations.select { |r| r.priority >= min_priority }

      puts "Found #{filtered_recommendations.size} optimization opportunities".colorize(:green)

      if filtered_recommendations.any?
        report = @optimization_engine.try(&.generate_optimization_report(filtered_recommendations)) || ""
        puts report

        # Generate roadmap
        roadmap = @optimization_engine.try(&.get_optimization_roadmap(filtered_recommendations))
        if roadmap
          puts "\n🗺️ OPTIMIZATION ROADMAP:".colorize(:cyan)
          puts "=" * 30

          roadmap.each do |phase, recs|
            puts "\n#{phase}:".colorize(:yellow)
            recs.each_with_index do |rec, i|
              puts "  #{i + 1}. #{rec.function_name}: #{rec.optimization_strategy}"
            end
          end
        end
      else
        puts "No optimization opportunities found with priority >= #{min_priority}".colorize(:green)
      end
    end

    private def compare_performance(options : Hash(String, String))
      puts "⚖️ Comparing Performance Data".colorize(:magenta)

      baseline_file = options["baseline"]?
      current_file = options["current"]?

      unless baseline_file && current_file
        puts "Error: Both baseline and current files must be specified".colorize(:red)
        return
      end

      unless File.exists?(baseline_file) && File.exists?(current_file)
        puts "Error: One or both files not found".colorize(:red)
        return
      end

      puts "Comparing #{current_file} against baseline #{baseline_file}..."

      # Initialize regression detector
      @regression_detector = PerformanceRegression.new

      return unless baseline = load_session(baseline_file)
      return unless current = load_session(current_file)
      regressions = @regression_detector.not_nil!.compare_sessions(baseline, current)

      if regressions.any?
        report = @regression_detector.try(&.generate_regression_report(regressions)) || ""
        puts report

        # Summary
        critical = regressions.count(&.critical?)
        warnings = regressions.count { |r| r.warning? && !r.critical? }

        puts "\nComparison Summary:".colorize(:cyan)
        puts "  Critical Regressions: #{critical}"
        puts "  Warning Regressions: #{warnings}"
        puts "  Total Issues: #{regressions.size}"
      else
        puts "✅ No performance regressions detected!".colorize(:green)
      end
    end

    private def run_benchmarks(options : Hash(String, String))
      puts "🏃 Running Performance Benchmarks".colorize(:blue)

      suite = options["suite"]? || "all"
      iterations = options["iterations"]?.try(&.to_i?) || 10

      puts "Running benchmark suite: #{suite}"
      puts "Iterations: #{iterations}"

      # Run built-in benchmarks
      case suite
      when "all"
        run_atomspace_benchmarks(iterations)
        run_pln_benchmarks(iterations)
        run_memory_benchmarks(iterations)
        run_concurrency_benchmarks(iterations)
      when "atomspace"
        run_atomspace_benchmarks(iterations)
      when "pln"
        run_pln_benchmarks(iterations)
      when "memory"
        run_memory_benchmarks(iterations)
      when "concurrent"
        run_concurrency_benchmarks(iterations)
      else
        puts "Unknown benchmark suite: #{suite}".colorize(:red)
        return
      end

      puts "Benchmarks complete!".colorize(:green)
    end

    private def generate_report(options : Hash(String, String))
      puts "📄 Generating Performance Report".colorize(:green)

      template = options["template"]? || "comprehensive"
      period_days = options["period"]?.try(&.to_i?) || 7

      puts "Generating #{template} report for last #{period_days} days..."

      # Initialize components
      @regression_detector = PerformanceRegression.new
      @monitor = PerformanceMonitor.new

      # Generate comprehensive report
      report = String.build do |str|
        str << "CrystalCog Performance Report\n"
        str << "=" * 40 << "\n"
        str << "Period: Last #{period_days} days\n"
        str << "Generated: #{Time.utc}\n"
        str << "Template: #{template}\n\n"

        # Add monitoring report
        if monitor = @monitor
          str << monitor.generate_monitoring_report
          str << "\n"
        end

        # Add trend analysis
        str << generate_trend_analysis(period_days)
      end

      puts report

      # Save to file
      report_file = "performance_report_#{Time.utc.to_unix}.txt"
      File.write(report_file, report)
      puts "\nReport saved to #{report_file}".colorize(:green)
    end

    private def save_profiling_results(session : PerformanceProfiler::Session, filename : String)
      case @output_format
      when "json"
        File.write(filename, PerformanceProfiler.export_metrics)
      when "html"
        html_report = generate_html_report(session)
        File.write(filename, html_report)
      else
        File.write(filename, PerformanceProfiler.generate_report)
      end
    end

    private def generate_html_report(session : PerformanceProfiler::Session) : String
      <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
          <title>CrystalCog Performance Profile Report</title>
          <style>
              body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
              .header { background: #34495e; color: white; padding: 20px; border-radius: 8px; }
              .metric { background: #ecf0f1; padding: 15px; margin: 10px 0; border-radius: 5px; }
              .metric-name { font-weight: bold; color: #2c3e50; }
              .metric-value { color: #e74c3c; font-size: 1.2em; }
              .recommendations { background: #fff3cd; padding: 20px; border-radius: 8px; margin: 20px 0; }
          </style>
      </head>
      <body>
          <div class="header">
              <h1>🚀 CrystalCog Performance Profile Report</h1>
              <p>Generated: #{Time.utc}</p>
              <p>Session Duration: #{session.session_duration.round(4)}s</p>
          </div>
          
          <h2>📊 Performance Metrics</h2>
          #{generate_metrics_html(session)}
          
          <div class="recommendations">
              <h2>💡 Recommendations</h2>
              <p>Based on the profiling data, consider reviewing functions with high execution times or frequent calls.</p>
              <p>Use the optimization engine for detailed recommendations.</p>
          </div>
      </body>
      </html>
      HTML
    end

    private def generate_metrics_html(session : PerformanceProfiler::Session) : String
      String.build do |str|
        session.all_metrics.each do |name, metrics|
          str << %(<div class="metric">)
          str << %(<div class="metric-name">#{name}</div>)
          str << %(<div class="metric-value">Total Time: #{metrics.wall_time.round(6)}s</div>)
          str << %(<div>Calls: #{metrics.call_count}</div>)
          str << %(<div>Memory Peak: #{format_bytes(metrics.memory_peak)}</div>)
          str << %(<div>Errors: #{metrics.errors}</div>)
          str << %(</div>)
        end
      end
    end

    private def format_bytes(bytes : UInt64) : String
      units = ["B", "KB", "MB", "GB"]
      size = bytes.to_f64
      unit_index = 0

      while size >= 1024 && unit_index < units.size - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end

    # Load a session saved with `--format json` (PerformanceProfiler.export_metrics).
    private def load_session(filename : String) : PerformanceProfiler::Session?
      unless File.exists?(filename)
        puts "Error: #{filename} not found".colorize(:red)
        return nil
      end
      session = PerformanceProfiler::Session.from_export(File.read(filename))
      if session.all_metrics.empty?
        puts "Warning: #{filename} contains no metrics".colorize(:yellow)
      end
      session
    rescue ex : JSON::ParseException
      puts "Error: #{filename} is not a JSON profile (save it with --format json): #{ex.message}".colorize(:red)
      nil
    end

    private def print_session_summary(session : PerformanceProfiler::Session)
      metrics = session.all_metrics
      puts "Functions profiled: #{metrics.size}"
      puts "Session duration: #{session.session_duration.round(4)}s"
      metrics.to_a.sort_by { |_, m| -m.wall_time }.each do |name, m|
        avg_ms = m.call_count > 0 ? m.wall_time / m.call_count * 1000 : 0.0
        puts "  #{name}: #{m.call_count} calls, total #{(m.wall_time * 1000).round(3)}ms, avg #{avg_ms.round(3)}ms, errors #{m.errors}, peak #{format_bytes(m.memory_peak)}"
      end
    end

    # Alert rules file: JSON array (or {"rules": [...]}) of objects with
    # name, metric_pattern, threshold, comparison (gt|lt|eq), duration_seconds,
    # severity and optional enabled.
    private def load_alert_configuration(filename : String)
      puts "Loading alert configuration from #{filename}..."
      unless File.exists?(filename)
        puts "Error: #{filename} not found".colorize(:red)
        return
      end

      data = JSON.parse(File.read(filename))
      rules = data.as_a? || data.as_h?.try(&.["rules"]?).try(&.as_a?) || [] of JSON::Any
      loaded = 0
      rules.each do |rule|
        next unless rule.as_h?
        name = rule["name"]?.try(&.as_s?)
        pattern = rule["metric_pattern"]?.try(&.as_s?)
        threshold = rule["threshold"]?.try { |t| t.as_f? || t.as_i64?.try(&.to_f64) }
        unless name && pattern && threshold
          puts "  Skipping rule without name/metric_pattern/threshold: #{rule.to_json}".colorize(:yellow)
          next
        end
        seconds = rule["duration_seconds"]?.try { |d| d.as_f? || d.as_i64?.try(&.to_f64) } || 0.0
        @monitor.try &.add_alert_rule(
          name, pattern, threshold,
          rule["comparison"]?.try(&.as_s?) || "gt",
          seconds.seconds,
          rule["severity"]?.try(&.as_s?) || "warning",
          rule["enabled"]?.try(&.as_bool?) != false
        )
        loaded += 1
      end
      puts "Alert configuration loaded: #{loaded} rule(s)".colorize(:green)
    rescue ex : JSON::ParseException
      puts "Error: invalid alert configuration #{filename}: #{ex.message}".colorize(:red)
    end

    # Run `iterations` timed samples of `block` and print the mean.
    private def time_samples(label : String, iterations : Int32, &block : Int32 ->)
      iterations = 1 if iterations < 1
      total = 0.0
      iterations.times do |i|
        start = Time.instant
        block.call(i)
        total += (Time.instant - start).total_seconds
        step = Math.max(iterations // 10, 1)
        if @verbose && (i + 1) % step == 0
          puts "  Progress: #{((i + 1).to_f / iterations * 100).round(1)}%"
        end
      end
      puts "  #{label}: #{(total / iterations * 1000).round(3)}ms per iteration".colorize(:green)
    end

    # Store-shaped workload (no AtomSpace dependency in cogutil): intern
    # names, index by type, and walk an outgoing-set map like links do.
    private def run_atomspace_benchmarks(iterations : Int32)
      puts "Running AtomSpace benchmarks (#{iterations} iterations)...".colorize(:blue)
      time_samples("insert+index+lookup of 1000 atoms", iterations) do |i|
        by_name = Hash(String, UInt64).new
        by_outgoing = Hash(Array(UInt64), UInt64).new
        1000.times do |j|
          handle = (i * 1000 + j).to_u64
          by_name["concept_#{j}"] = handle
          by_outgoing[[handle, handle &+ 1]] = handle if j.even?
        end
        1000.times { |j| by_name["concept_#{j}"]? }
      end
    end

    # PLN deduction strength/confidence formula over chains of truth values.
    private def run_pln_benchmarks(iterations : Int32)
      puts "Running PLN reasoning benchmarks (#{iterations} iterations)...".colorize(:blue)
      rng = Random.new(42)
      acc = 0.0
      time_samples("10000 deduction steps", iterations) do
        s_ab, s_bc, s_b, s_c = rng.rand, rng.rand, rng.rand(0.01..0.99), rng.rand
        10000.times do
          s_ac = s_ab * s_bc + (1.0 - s_ab) * (s_c - s_b * s_bc) / (1.0 - s_b)
          s_ab = s_ac.clamp(0.0, 1.0)
          acc += s_ab
        end
      end
      puts "  checksum: #{acc.round(6)}" if @verbose
    end

    private def run_memory_benchmarks(iterations : Int32)
      puts "Running memory allocation benchmarks (#{iterations} iterations)...".colorize(:blue)
      before = GC.stats.total_bytes
      time_samples("allocate 10000 small objects", iterations) do
        arrays = Array(Array(Int32)).new(10000) { |k| [k, k + 1, k + 2] }
        arrays.size
      end
      allocated = GC.stats.total_bytes - before
      puts "  Allocated #{format_bytes(allocated.to_u64)} total".colorize(:green)
    end

    private def run_concurrency_benchmarks(iterations : Int32)
      puts "Running concurrency benchmarks (#{iterations} iterations)...".colorize(:blue)
      time_samples("100 fibers x 100 channel messages", iterations) do
        channel = Channel(Int32).new(64)
        done = Channel(Nil).new
        100.times do
          spawn do
            100.times { |k| channel.send(k) }
            done.send(nil)
          end
        end
        spawn { 100.times { done.receive }; channel.close }
        while channel.receive?
        end
      end
    end

    private def generate_trend_analysis(days : Int32) : String
      String.build do |str|
        str << "📈 TREND ANALYSIS (Last #{days} days):\n"
        str << "-" * 40 << "\n"
        detector = @regression_detector || PerformanceRegression.new
        functions = detector.tracked_functions
        if functions.empty?
          str << "No historical samples recorded yet\n\n"
        else
          functions.each do |name|
            if trend = detector.get_trend_analysis(name, days)
              str << "• #{name}: time trend #{trend["time_trend"].round(4)}, memory trend #{trend["memory_trend"].round(2)}, samples #{trend["samples"].to_i}\n"
            else
              str << "• #{name}: fewer than 2 samples in window\n"
            end
          end
          str << "\n"
        end
      end
    end

    private def setup_signal_handlers
      # Windows has no POSIX signals (Signal#trap raises NotImplementedError)
      {% if flag?(:win32) %}
        return
      {% end %}

      Signal::INT.trap do
        puts "\n🛑 Profiling interrupted by user".colorize(:yellow)

        # Clean shutdown
        @monitor.try(&.stop_monitoring)
        @monitor.try(&.stop_dashboard)

        if session = PerformanceProfiler.end_session
          puts "Saving partial results..."
          save_profiling_results(session, "interrupted_profile_#{Time.utc.to_unix}.txt")
        end

        exit(0)
      end
    end

    private def show_version
      puts "CrystalCog Performance Profiling Tools"
      puts "Version: 1.0.0"
      puts "Crystal Version: #{Crystal::VERSION}"
      puts "Built: #{Time.utc}"
    end
  end
end

# Main entry point for CLI tool
if PROGRAM_NAME.includes?("profiling_cli")
  cli = CogUtil::ProfilingCLI.new
  cli.run(ARGV)
end
