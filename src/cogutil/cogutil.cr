# CogUtil module - Core utilities for Crystal OpenCog implementation
# Converted from cogutil/opencog/util/*
#
# This module provides the foundational utilities needed by all OpenCog components.

# Compatibility shim for Crystal < 1.19.0 which lacks Time::Instant
{% if compare_versions(Crystal::VERSION, "1.19.0") < 0 %}
  struct Time::Instant
    include Comparable(Time::Instant)

    getter span : Time::Span

    def initialize(@span : Time::Span)
    end

    def -(other : Time::Instant) : Time::Span
      @span - other.span
    end

    def -(other : Time::Span) : Time::Instant
      Time::Instant.new(@span - other)
    end

    def +(other : Time::Span) : Time::Instant
      Time::Instant.new(@span + other)
    end

    def <=>(other : Time::Instant) : Int32
      @span <=> other.span
    end

    def elapsed : Time::Span
      Time.instant - self
    end

    def duration_since(other : Time::Instant) : Time::Span
      self - other
    end
  end

  module Time
    def self.instant : Time::Instant
      Time::Instant.new(Time.monotonic)
    end
  end
{% end %}

require "./logger"
require "./config"
require "./randgen"
require "./memory_profiler"
require "./performance_profiler"
require "./performance_regression"
require "./optimization_engine"
require "./performance_monitor"
require "./profiling_cli"

module CogUtil
  VERSION = "0.1.0"

  # Initialize the CogUtil subsystem
  def self.initialize
    # Load configuration
    Config.create_instance

    # Setup default logger
    Logger.info("CogUtil #{VERSION} initialized")

    # Seed random number generator if configured
    if seed = config_get("RANDOM_SEED").to_i32?
      RandGen.seed(seed.to_u32)
      Logger.debug("Random seed set to: #{seed}")
    end
  end

  # Get a configuration value
  def self.config_get(key : String, default : String = "") : String
    Config.instance.get(key, default)
  end

  # Set a configuration value
  def self.config_set(key : String, value)
    Config.instance.set(key, value)
  end

  # Get current timestamp as string
  def self.timestamp : String
    Time.utc.to_s("%Y-%m-%d %H:%M:%S UTC")
  end

  # Convert value to string (utility method)
  def self.to_string(value) : String
    value.to_s
  end

  # Shutdown and cleanup
  def self.finalize
    Logger.info("CogUtil shutting down")
  end

  # Exception classes for OpenCog
  class OpenCogException < Exception
  end

  class InvalidParamException < OpenCogException
  end

  class AssertionException < OpenCogException
  end

  class RuntimeException < OpenCogException
  end

  class IOException < OpenCogException
  end

  class ComboException < OpenCogException
  end

  class StandardException < OpenCogException
  end

  # OpenCog assertion macro - similar to oc_assert
  macro oc_assert(condition, message = "Assertion failed")
    {% if flag?(:release) %}
      # In release mode, assertions are disabled
    {% else %}
      unless {{condition}}
        raise CogUtil::AssertionException.new({{message}} + " at {{__FILE__}}:{{__LINE__}}")
      end
    {% end %}
  end

  # Platform-specific utilities
  module Platform
    # Get number of CPU cores
    def self.cpu_count : Int32
      {% if flag?(:linux) %}
        File.read("/proc/cpuinfo").scan(/^processor\s*:/).size
      {% elsif flag?(:darwin) %}
        `sysctl -n hw.ncpu`.to_i
      {% else %}
        1
      {% end %}
    rescue
      1
    end

    # Get total system memory in bytes
    def self.total_memory : Int64
      {% if flag?(:linux) %}
        if match = File.read("/proc/meminfo").match(/MemTotal:\s*(\d+)\s*kB/)
          match[1].to_i64 * 1024
        else
          0_i64
        end
      {% elsif flag?(:darwin) %}
        `sysctl -n hw.memsize`.to_i64
      {% else %}
        0_i64
      {% end %}
    rescue
      0_i64
    end

    # Get available memory in bytes
    def self.available_memory : Int64
      {% if flag?(:linux) %}
        if match = File.read("/proc/meminfo").match(/MemAvailable:\s*(\d+)\s*kB/)
          match[1].to_i64 * 1024
        else
          0_i64
        end
      {% else %}
        total_memory # Approximate for non-Linux systems
      {% end %}
    rescue
      0_i64
    end
  end

  # String utilities
  module StringUtil
    # Trim whitespace and convert to lowercase
    def self.normalize(str : String) : String
      str.strip.downcase
    end

    # Split string by delimiter, handling quoted sections
    def self.tokenize(str : String, delimiter : Char = ' ') : Array(String)
      tokens = [] of String
      current_token = String::Builder.new
      in_quotes = false
      quote_char = '"'

      str.each_char do |char|
        case char
        when '"', '\''
          if in_quotes && char == quote_char
            in_quotes = false
          elsif !in_quotes
            in_quotes = true
            quote_char = char
          else
            current_token << char
          end
        when delimiter
          if in_quotes
            current_token << char
          else
            tokens << current_token.to_s.strip unless current_token.empty?
            current_token.clear
          end
        else
          current_token << char
        end
      end

      tokens << current_token.to_s.strip unless current_token.empty?
      tokens
    end

    # Convert string to snake_case
    def self.to_snake_case(str : String) : String
      str.gsub(/([A-Z])/, "_\\1").downcase.lstrip('_')
    end

    # Convert string to CamelCase
    def self.to_camel_case(str : String) : String
      str.split('_').map(&.capitalize).join
    end
  end

  # Timing utilities
  module Timer
    # Benchmark block execution time
    def self.benchmark(description : String = "Operation", &block)
      start_time = Time.instant
      result = yield
      end_time = Time.instant
      elapsed = end_time - start_time

      Logger.info("#{description} took #{elapsed.total_milliseconds.round(3)}ms")
      result
    end

    # Get current timestamp in milliseconds
    def self.current_millis : Int64
      Time.utc.to_unix_ms
    end

    # Get current timestamp in microseconds
    def self.current_micros : Int64
      Time.utc.to_unix_ms * 1000
    end
  end

  # Memory utilities
  module Memory
    # Get current memory usage of the process
    def self.current_usage : Int64
      {% if flag?(:linux) %}
        if status = File.read("/proc/self/status")
          if match = status.match(/VmRSS:\s*(\d+)\s*kB/)
            return match[1].to_i64 * 1024
          end
        end
      {% end %}
      0_i64
    rescue
      0_i64
    end

    # Force garbage collection
    def self.gc_collect
      GC.collect
    end

    # Get GC statistics
    def self.gc_stats
      GC.stats
    end
  end
end
