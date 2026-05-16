require "json"
require "file_utils"
require "./performance_profiler"

# Performance regression detection system
# Tracks performance metrics over time and detects regressions
module CogUtil
  class PerformanceRegression
    # Historical performance data point
    struct HistoricalData
      property timestamp : Time
      property metrics : Hash(String, PerformanceProfiler::Metrics)
      property version : String
      property environment : Hash(String, String)

      def initialize(@timestamp : Time, @metrics : Hash(String, PerformanceProfiler::Metrics),
                     @version : String, @environment : Hash(String, String))
      end

      def to_json(json : JSON::Builder)
        json.object do
          json.field "timestamp", @timestamp.to_rfc3339
          json.field "version", @version
          json.field "environment", @environment
          json.field "metrics" do
            json.object do
              @metrics.each do |name, metrics|
                json.field name, metrics
              end
            end
          end
        end
      end

      def self.from_json(json : JSON::PullParser) : HistoricalData
        timestamp = Time.utc
        version = ""
        environment = Hash(String, String).new
        metrics = Hash(String, PerformanceProfiler::Metrics).new

        json.read_object do |key|
          case key
          when "timestamp"
            timestamp = Time.parse_rfc3339(json.read_string)
          when "version"
            version = json.read_string
          when "environment"
            environment = Hash(String, String).from_json(json)
          when "metrics"
            json.read_object do |metric_name|
              # This would need proper Metrics.from_json implementation
              json.skip
            end
          end
        end

        new(timestamp, metrics, version, environment)
      end
    end

    # Regression analysis result
    struct RegressionResult
      property function_name : String
      property regression_type : String
      property severity : Float64
      property baseline_value : Float64
      property current_value : Float64
      property change_percentage : Float64
      property confidence : Float64

      def initialize(@function_name : String, @regression_type : String,
                     @severity : Float64, @baseline_value : Float64,
                     @current_value : Float64, @change_percentage : Float64,
                     @confidence : Float64)
      end

      def critical? : Bool
        @severity > 0.8 && @change_percentage.abs > 20.0
      end

      def warning? : Bool
        @severity > 0.5 && @change_percentage.abs > 10.0
      end
    end

    @storage_path : String
    @historical_data : Array(HistoricalData)
    @baseline_window : Int32
    @sensitivity_threshold : Float64

    def initialize(storage_path : String = "performance_history.json",
                   baseline_window : Int32 = 10,
                   sensitivity_threshold : Float64 = 5.0)
      @storage_path = storage_path
      @historical_data = Array(HistoricalData).new
      @baseline_window = baseline_window
      @sensitivity_threshold = sensitivity_threshold
      load_historical_data
    end

    # Record current performance metrics
    def record_metrics(session : PerformanceProfiler::Session, version : String)
      environment = {
        "crystal_version" => Crystal::VERSION,
        "hostname"        => System.hostname || "unknown",
        "platform"        => {% if flag?(:linux) %}"linux"{% elsif flag?(:darwin) %}"macos"{% else %}"unknown"{% end %},
      }

      data = HistoricalData.new(
        timestamp: Time.utc,
        metrics: session.all_metrics,
        version: version,
        environment: environment
      )

      @historical_data << data
      save_historical_data
    end

    # Analyze for performance regressions
    def analyze_regressions(current_session : PerformanceProfiler::Session) : Array(RegressionResult)
      return Array(RegressionResult).new if @historical_data.size < 2

      regressions = Array(RegressionResult).new
      current_metrics = current_session.all_metrics

      # Get baseline metrics (average of last N entries)
      baseline_metrics = calculate_baseline_metrics

      current_metrics.each do |function_name, current_metric|
        next unless baseline_metric = baseline_metrics[function_name]?

        # Analyze different regression types
        time_regression = analyze_time_regression(function_name, baseline_metric, current_metric)
        memory_regression = analyze_memory_regression(function_name, baseline_metric, current_metric)
        error_regression = analyze_error_regression(function_name, baseline_metric, current_metric)

        [time_regression, memory_regression, error_regression].compact.each do |regression|
          regressions << regression if regression
        end
      end

      regressions.sort_by { |r| -r.severity }
    end

    # Generate regression report
    def generate_regression_report(regressions : Array(RegressionResult)) : String
      String.build do |str|
        str << "Performance Regression Analysis Report\n"
        str << "=" * 50 << "\n"
        str << "Analysis Date: #{Time.utc}\n"
        str << "Baseline Window: #{@baseline_window} samples\n"
        str << "Sensitivity Threshold: #{@sensitivity_threshold}%\n\n"

        if regressions.empty?
          str << "✅ No performance regressions detected!\n"
          return str.to_s
        end

        critical_regressions = regressions.select(&.critical?)
        warning_regressions = regressions.select(&.warning?)
        minor_regressions = regressions.reject { |r| r.critical? || r.warning? }

        if critical_regressions.any?
          str << "🚨 CRITICAL REGRESSIONS:\n"
          str << "-" * 25 << "\n"
          critical_regressions.each do |regression|
            str << format_regression(regression)
          end
          str << "\n"
        end

        if warning_regressions.any?
          str << "⚠️ WARNING REGRESSIONS:\n"
          str << "-" * 23 << "\n"
          warning_regressions.each do |regression|
            str << format_regression(regression)
          end
          str << "\n"
        end

        if minor_regressions.any?
          str << "ℹ️ MINOR REGRESSIONS:\n"
          str << "-" * 20 << "\n"
          minor_regressions.each do |regression|
            str << format_regression(regression)
          end
          str << "\n"
        end

        # Summary statistics
        str << "Summary:\n"
        str << "  Critical: #{critical_regressions.size}\n"
        str << "  Warning: #{warning_regressions.size}\n"
        str << "  Minor: #{minor_regressions.size}\n"
        str << "  Total: #{regressions.size}\n"
      end
    end

    # Get trend analysis for a specific function
    def get_trend_analysis(function_name : String, days : Int32 = 30) : Hash(String, Float64)?
      cutoff_time = Time.utc - days.days
      recent_data = @historical_data.select { |d| d.timestamp > cutoff_time }

      return nil if recent_data.size < 2

      time_values = recent_data.compact_map { |d| d.metrics[function_name]?.try(&.wall_time) }
      memory_values = recent_data.compact_map { |d| d.metrics[function_name]?.try(&.memory_peak.to_f64) }

      return nil if time_values.size < 2

      {
        "time_trend"      => calculate_trend(time_values),
        "memory_trend"    => calculate_trend(memory_values),
        "samples"         => time_values.size.to_f64,
        "time_variance"   => calculate_variance(time_values),
        "memory_variance" => calculate_variance(memory_values),
      }
    end

    # Export historical data for external analysis
    def export_data(format : String = "json") : String
      case format
      when "json"
        JSON.build do |json|
          json.object do
            json.field "export_timestamp", Time.utc.to_rfc3339
            json.field "total_samples", @historical_data.size
            json.field "data" do
              json.array do
                @historical_data.each do |data|
                  data.to_json(json)
                end
              end
            end
          end
        end
      when "csv"
        export_csv
      else
        raise ArgumentError.new("Unsupported format: #{format}")
      end
    end

    # Clean old data beyond retention period
    def cleanup_old_data(retention_days : Int32 = 90)
      cutoff_time = Time.utc - retention_days.days
      original_size = @historical_data.size
      @historical_data = @historical_data.select { |d| d.timestamp > cutoff_time }

      if @historical_data.size < original_size
        save_historical_data
        puts "Cleaned #{original_size - @historical_data.size} old performance records"
      end
    end

    private def load_historical_data
      return unless File.exists?(@storage_path)

      begin
        json_data = File.read(@storage_path)
        parsed = JSON.parse(json_data)

        if data_json = parsed["data"]?
          if data_array = data_json.as_a?
            @historical_data = data_array.map do |item|
              # Would need proper HistoricalData.from_json implementation
              # For now, we'll use a simplified version
              timestamp = Time.parse_rfc3339(item["timestamp"].as_s)
              version = item["version"].as_s
              environment = item["environment"].as_h.transform_values(&.as_s)
              metrics = Hash(String, PerformanceProfiler::Metrics).new

              HistoricalData.new(timestamp, metrics, version, environment)
            end
          end
        end
      rescue ex
        puts "Warning: Could not load historical performance data: #{ex.message}"
        @historical_data = Array(HistoricalData).new
      end
    end

    private def save_historical_data
      FileUtils.mkdir_p(File.dirname(@storage_path))

      File.write(@storage_path, JSON.build do |json|
        json.object do
          json.field "format_version", 1
          json.field "saved_at", Time.utc.to_rfc3339
          json.field "total_samples", @historical_data.size
          json.field "data" do
            json.array do
              @historical_data.each do |data|
                data.to_json(json)
              end
            end
          end
        end
      end)
    end

    private def calculate_baseline_metrics : Hash(String, PerformanceProfiler::Metrics)
      return Hash(String, PerformanceProfiler::Metrics).new if @historical_data.empty?

      # Take last N samples for baseline
      baseline_samples = @historical_data.last([@baseline_window, @historical_data.size].min)
      baseline_metrics = Hash(String, Array(PerformanceProfiler::Metrics)).new

      # Group metrics by function name
      baseline_samples.each do |sample|
        sample.metrics.each do |function_name, metrics|
          baseline_metrics[function_name] ||= Array(PerformanceProfiler::Metrics).new
          baseline_metrics[function_name] << metrics
        end
      end

      # Calculate average metrics for each function
      result = Hash(String, PerformanceProfiler::Metrics).new
      baseline_metrics.each do |function_name, metrics_array|
        avg_metrics = PerformanceProfiler::Metrics.new

        if metrics_array.any?
          avg_metrics.wall_time = metrics_array.sum(&.wall_time) / metrics_array.size
          avg_metrics.memory_peak = (metrics_array.sum(&.memory_peak.to_f64) / metrics_array.size).to_u64
          avg_metrics.call_count = (metrics_array.sum(&.call_count.to_f64) / metrics_array.size).to_u64
          avg_metrics.errors = (metrics_array.sum(&.errors.to_f64) / metrics_array.size).to_u64
          avg_metrics.gc_time = metrics_array.sum(&.gc_time) / metrics_array.size
        end

        result[function_name] = avg_metrics
      end

      result
    end

    private def analyze_time_regression(function_name : String, baseline : PerformanceProfiler::Metrics,
                                        current : PerformanceProfiler::Metrics) : RegressionResult?
      return nil if baseline.wall_time == 0.0

      change_percentage = ((current.wall_time - baseline.wall_time) / baseline.wall_time) * 100
      return nil if change_percentage.abs < @sensitivity_threshold

      severity = [change_percentage.abs / 50.0, 1.0].min
      confidence = calculate_confidence(baseline.call_count, current.call_count)

      RegressionResult.new(
        function_name: function_name,
        regression_type: "execution_time",
        severity: severity,
        baseline_value: baseline.wall_time,
        current_value: current.wall_time,
        change_percentage: change_percentage,
        confidence: confidence
      )
    end

    private def analyze_memory_regression(function_name : String, baseline : PerformanceProfiler::Metrics,
                                          current : PerformanceProfiler::Metrics) : RegressionResult?
      return nil if baseline.memory_peak == 0

      change_percentage = ((current.memory_peak.to_f64 - baseline.memory_peak.to_f64) / baseline.memory_peak.to_f64) * 100
      return nil if change_percentage.abs < @sensitivity_threshold

      severity = [change_percentage.abs / 100.0, 1.0].min
      confidence = calculate_confidence(baseline.call_count, current.call_count)

      RegressionResult.new(
        function_name: function_name,
        regression_type: "memory_usage",
        severity: severity,
        baseline_value: baseline.memory_peak.to_f64,
        current_value: current.memory_peak.to_f64,
        change_percentage: change_percentage,
        confidence: confidence
      )
    end

    private def analyze_error_regression(function_name : String, baseline : PerformanceProfiler::Metrics,
                                         current : PerformanceProfiler::Metrics) : RegressionResult?
      baseline_rate = baseline.call_count > 0 ? (baseline.errors.to_f64 / baseline.call_count.to_f64) * 100 : 0.0
      current_rate = current.call_count > 0 ? (current.errors.to_f64 / current.call_count.to_f64) * 100 : 0.0

      return nil if baseline_rate == 0.0 && current_rate == 0.0

      change_percentage = baseline_rate > 0 ? ((current_rate - baseline_rate) / baseline_rate) * 100 : current_rate * 100
      return nil if change_percentage.abs < @sensitivity_threshold

      severity = [change_percentage.abs / 25.0, 1.0].min
      confidence = calculate_confidence(baseline.call_count, current.call_count)

      RegressionResult.new(
        function_name: function_name,
        regression_type: "error_rate",
        severity: severity,
        baseline_value: baseline_rate,
        current_value: current_rate,
        change_percentage: change_percentage,
        confidence: confidence
      )
    end

    private def calculate_confidence(baseline_calls : UInt64, current_calls : UInt64) : Float64
      min_calls = [baseline_calls, current_calls].min.to_f64
      # Higher confidence with more samples
      [min_calls / 1000.0, 1.0].min
    end

    private def format_regression(regression : RegressionResult) : String
      direction = regression.change_percentage > 0 ? "increased" : "decreased"
      String.build do |str|
        str << "  #{regression.function_name} (#{regression.regression_type}):\n"
        str << "    #{direction} by #{regression.change_percentage.abs.round(2)}%\n"
        str << "    #{regression.baseline_value.round(6)} → #{regression.current_value.round(6)}\n"
        str << "    Severity: #{(regression.severity * 100).round(1)}%, Confidence: #{(regression.confidence * 100).round(1)}%\n\n"
      end
    end

    private def calculate_trend(values : Array(Float64)) : Float64
      return 0.0 if values.size < 2

      n = values.size.to_f64
      x_sum = (0...values.size).sum.to_f64
      y_sum = values.sum
      xy_sum = (0...values.size).zip(values).sum { |x, y| x * y }
      x2_sum = (0...values.size).sum { |x| x * x }.to_f64

      # Linear regression slope
      denominator = n * x2_sum - x_sum * x_sum
      return 0.0 if denominator == 0.0

      (n * xy_sum - x_sum * y_sum) / denominator
    end

    private def calculate_variance(values : Array(Float64)) : Float64
      return 0.0 if values.size < 2

      mean = values.sum / values.size
      sum_sq_diff = values.sum { |v| (v - mean) ** 2 }
      sum_sq_diff / values.size
    end

    private def export_csv : String
      String.build do |str|
        str << "timestamp,version,function_name,wall_time,memory_peak,call_count,errors,gc_time\n"

        @historical_data.each do |data|
          data.metrics.each do |function_name, metrics|
            str << "#{data.timestamp.to_rfc3339},#{data.version},#{function_name},"
            str << "#{metrics.wall_time},#{metrics.memory_peak},#{metrics.call_count},"
            str << "#{metrics.errors},#{metrics.gc_time}\n"
          end
        end
      end
    end
  end
end
