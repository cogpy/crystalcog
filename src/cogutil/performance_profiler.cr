require "json"
require "benchmark"
require "./cogutil"

# Comprehensive performance profiling and optimization tools for CrystalCog
# This module provides advanced profiling capabilities including CPU profiling,
# memory tracking, performance regression detection, and optimization recommendations
module CogUtil
  # Core performance profiler with CPU, memory, and timing metrics
  class PerformanceProfiler
    # Performance metrics data structure
    class Metrics
      property cpu_time : Float64
      property memory_used : UInt64
      property memory_peak : UInt64
      property wall_time : Float64
      property gc_time : Float64
      property call_count : UInt64
      property errors : UInt64
      
      def initialize
        @cpu_time = 0.0
        @memory_used = 0_u64
        @memory_peak = 0_u64
        @wall_time = 0.0
        @gc_time = 0.0
        @call_count = 0_u64
        @errors = 0_u64
      end
      
      def to_json(json : JSON::Builder)
        json.object do
          json.field "cpu_time", @cpu_time
          json.field "memory_used", @memory_used
          json.field "memory_peak", @memory_peak
          json.field "wall_time", @wall_time
          json.field "gc_time", @gc_time
          json.field "call_count", @call_count
          json.field "errors", @errors
        end
      end
    end
    
    # Profile session storing collected metrics
    class Session
      @metrics : Hash(String, Metrics)
      @start_time : Time::Span
      @memory_baseline : UInt64
      @active_profiles : Hash(String, Time::Span)
      
      def initialize
        @metrics = Hash(String, Metrics).new
        @start_time = Time.monotonic
        @memory_baseline = get_memory_usage
        @active_profiles = Hash(String, Time::Span).new
      end
      
      def start_profile(name : String)
        @active_profiles[name] = Time.monotonic
        unless @metrics.has_key?(name)
          @metrics[name] = Metrics.new
        end
      end
      
      def end_profile(name : String)
        end_time = Time.monotonic
        if start_time = @active_profiles.delete(name)
          metrics = @metrics[name]
          duration = (end_time - start_time).total_seconds
          
          metrics.wall_time += duration
          metrics.call_count += 1
          
          # Update memory metrics
          current_memory = get_memory_usage
          metrics.memory_used = current_memory
          if current_memory > metrics.memory_peak
            metrics.memory_peak = current_memory
          end
        end
      end
      
      def profile_error(name : String)
        if @metrics.has_key?(name)
          @metrics[name].errors += 1
        end
      end
      
      def get_metrics(name : String) : Metrics?
        @metrics[name]?
      end
      
      def all_metrics : Hash(String, Metrics)
        @metrics
      end
      
      def session_duration : Float64
        (Time.monotonic - @start_time).total_seconds
      end
      
      private def get_memory_usage : UInt64
        # Get memory usage through GC stats
        GC.stats.total_bytes.to_u64
      end
    end
    
    @@current_session : Session?
    @@global_metrics : Hash(String, Array(Metrics)) = Hash(String, Array(Metrics)).new
    
    # Start a new profiling session
    def self.start_session
      @@current_session = Session.new
    end
    
    # End current profiling session and return metrics
    def self.end_session : Session?
      session = @@current_session
      @@current_session = nil
      session
    end
    
    # Get current profiling session (for monitoring purposes)
    def self.current_session : Session?
      @@current_session
    end
    
    # Profile a code block with automatic timing and metrics collection
    def self.profile(name : String, &block)
      ensure_session
      session = @@current_session.not_nil!
      
      session.start_profile(name)
      start_time = Time.monotonic
      gc_stats_before = GC.stats
      
      begin
        result = yield
        
        # Update GC metrics BEFORE ending profile
        gc_stats_after = GC.stats
        metrics = session.get_metrics(name).not_nil!
        metrics.gc_time += (gc_stats_after.total_bytes - gc_stats_before.total_bytes).to_f64 / 1_000_000
        
        session.end_profile(name)
        
        result
      rescue ex
        session.profile_error(name)
        session.end_profile(name)
        raise ex
      end
    end
    
    # Profile multiple iterations of a code block for statistical analysis
    def self.profile_iterations(name : String, iterations : Int32, &block)
      results = Array(Float64).new(iterations)
      
      iterations.times do |i|
        result = profile("#{name}_iter_#{i}") do
          yield
        end
        
        if session = @@current_session
          if metrics = session.get_metrics("#{name}_iter_#{i}")
            results << metrics.wall_time
          end
        end
      end
      
      # Calculate statistics
      avg_time = results.sum / results.size
      min_time = results.min
      max_time = results.max
      std_dev = Math.sqrt(results.map { |x| (x - avg_time) ** 2 }.sum / results.size)
      
      {
        average: avg_time,
        minimum: min_time, 
        maximum: max_time,
        std_deviation: std_dev,
        iterations: iterations
      }
    end
    
    # Memory allocation profiler
    def self.profile_memory_allocation(name : String, &block)
      gc_before = GC.stats
      memory_before = get_process_memory
      
      result = profile(name) do
        yield
      end
      
      gc_after = GC.stats
      memory_after = get_process_memory
      
      allocation_info = {
        heap_allocated: gc_after.total_bytes - gc_before.total_bytes,
        process_memory_delta: memory_after - memory_before,
        # Note: GC collections count not available in Crystal 1.10.1
      }
      
      {result: result, allocation: allocation_info}
    end
    
    # Generate comprehensive performance report
    def self.generate_report : String
      return "No active session" unless session = @@current_session
      
      report = String.build do |str|
        str << "CrystalCog Performance Profiling Report\n"
        str << "=" * 50 << "\n"
        str << "Session Duration: #{session.session_duration.round(4)}s\n"
        str << "Generated: #{Time.utc}\n\n"
        
        # Summary statistics
        str << "Performance Summary:\n"
        str << "-" * 20 << "\n"
        
        total_time = session.all_metrics.values.sum(&.wall_time)
        total_calls = session.all_metrics.values.sum(&.call_count)
        total_errors = session.all_metrics.values.sum(&.errors)
        
        str << "Total Profiled Time: #{total_time.round(4)}s\n"
        str << "Total Function Calls: #{total_calls}\n"
        str << "Total Errors: #{total_errors}\n"
        str << "Error Rate: #{total_errors > 0 ? (total_errors.to_f / total_calls * 100).round(2) : 0.0}%\n\n"
        
        # Detailed metrics per function
        str << "Detailed Metrics:\n"
        str << "-" * 20 << "\n"
        
        # Sort by total time
        sorted_metrics = session.all_metrics.to_a.sort_by { |name, metrics| -metrics.wall_time }
        
        sorted_metrics.each do |name, metrics|
          avg_time = metrics.call_count > 0 ? metrics.wall_time / metrics.call_count : 0.0
          
          str << "#{name}:\n"
          str << "  Calls: #{metrics.call_count}\n"
          str << "  Total Time: #{metrics.wall_time.round(6)}s\n"
          str << "  Average Time: #{avg_time.round(6)}s\n"
          str << "  Memory Peak: #{format_bytes(metrics.memory_peak)}\n"
          str << "  GC Time: #{metrics.gc_time.round(6)}s\n"
          str << "  Errors: #{metrics.errors}\n\n"
        end
        
        # Performance recommendations
        str << generate_recommendations(sorted_metrics)
      end
      
      report
    end
    
    # Generate optimization recommendations based on profiling data
    private def self.generate_recommendations(sorted_metrics : Array(Tuple(String, Metrics))) : String
      recommendations = String.build do |str|
        str << "Optimization Recommendations:\n"
        str << "-" * 30 << "\n"
        
        # High-time functions
        high_time_functions = sorted_metrics.select { |name, metrics| metrics.wall_time > 0.1 }
        if high_time_functions.any?
          str << "🔍 High Time Consumption:\n"
          high_time_functions.first(3).each do |name, metrics|
            percentage = (metrics.wall_time / sorted_metrics.sum { |_, m| m.wall_time } * 100).round(1)
            str << "  - #{name}: #{metrics.wall_time.round(4)}s (#{percentage}% of total)\n"
          end
          str << "  → Consider optimizing these functions first\n\n"
        end
        
        # High call count functions
        high_call_functions = sorted_metrics.select { |name, metrics| metrics.call_count > 1000 }
        if high_call_functions.any?
          str << "🔄 High Call Frequency:\n"
          high_call_functions.first(3).each do |name, metrics|
            str << "  - #{name}: #{metrics.call_count} calls\n"
          end
          str << "  → Consider caching or reducing call frequency\n\n"
        end
        
        # High memory usage
        high_memory_functions = sorted_metrics.select { |name, metrics| metrics.memory_peak > 10_000_000 }
        if high_memory_functions.any?
          str << "💾 High Memory Usage:\n"
          high_memory_functions.first(3).each do |name, metrics|
            str << "  - #{name}: #{format_bytes(metrics.memory_peak)}\n"
          end
          str << "  → Consider memory optimization strategies\n\n"
        end
        
        # Error-prone functions
        error_functions = sorted_metrics.select { |name, metrics| metrics.errors > 0 }
        if error_functions.any?
          str << "⚠️ Error-Prone Functions:\n"
          error_functions.each do |name, metrics|
            error_rate = (metrics.errors.to_f / metrics.call_count * 100).round(2)
            str << "  - #{name}: #{metrics.errors} errors (#{error_rate}% rate)\n"
          end
          str << "  → Review error handling and input validation\n\n"
        end
      end
      
      recommendations
    end
    
    # Export metrics to JSON for external analysis
    def self.export_metrics : String
      return "{}" unless session = @@current_session
      
      JSON.build do |json|
        json.object do
          json.field "session_info" do
            json.object do
              json.field "duration", session.session_duration
              json.field "timestamp", Time.utc.to_rfc3339
              json.field "crystal_version", Crystal::VERSION
            end
          end
          
          json.field "metrics" do
            json.object do
              session.all_metrics.each do |name, metrics|
                json.field name, metrics
              end
            end
          end
        end
      end
    end
    
    private def self.ensure_session
      @@current_session ||= Session.new
    end
    
    private def self.get_process_memory : UInt64
      # Simple memory tracking - in a real implementation,
      # this would read from /proc/self/status or similar
      GC.stats.total_bytes.to_u64
    end
    
    private def self.format_bytes(bytes : UInt64) : String
      units = ["B", "KB", "MB", "GB", "TB"]
      return "0 B" if bytes == 0
      
      i = (Math.log(bytes) / Math.log(1024)).floor.to_i
      i = [i, units.size - 1].min
      
      size = bytes.to_f / (1024 ** i)
      "#{size.round(2)} #{units[i]}"
    end
  end
  
  # Decorator for automatic profiling
  module ProfiledMethod
    macro included
      def self.profiled(method_name, &block)
        PerformanceProfiler.profile(method_name.to_s) do
          block.call
        end
      end
    end
    
    # Macro to automatically profile method calls
    macro profile_method(method_name)
      def {{method_name}}(*args, **kwargs)
        PerformanceProfiler.profile("{{method_name}}") do
          previous_def(*args, **kwargs)
        end
      end
    end
  end
end