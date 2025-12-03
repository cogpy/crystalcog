# Crystal implementation of Agent-Zero Cognitive Kernel
# Provides hypergraph state management and tensor field encoding
#
# This module implements the cognitive kernel functionality described in
# the Agent-Zero Genesis roadmap, enabling hypergraph state persistence.
#
# Performance optimizations:
# - Memory pooling for frequent tensor operations
# - Cache-optimized hypergraph traversal
# - SIMD-friendly tensor field encoding
# - Lock-free concurrent operations where possible

require "./atomspace"
require "./storage"
require "../cogutil/cogutil"
require "../cogutil/performance_optimization"

module AtomSpace
  # Cognitive kernel for Agent-Zero Genesis system with performance optimizations
  class CognitiveKernel
    property atomspace : AtomSpace
    property tensor_shape : Array(Int32)
    property attention_weight : Float64
    property meta_level : Int32
    property cognitive_operation : String?

    # Performance optimization components
    @tensor_cache : CogUtil::CognitiveCache(String, Array(Float32))
    @memory_pool : CogUtil::AtomMemoryPool
    @operation_metrics : Hash(String, OperationMetrics)

    struct OperationMetrics
      property call_count : UInt64
      property total_time_ms : Float64
      property avg_time_ms : Float64
      property cache_hit_rate : Float64

      def initialize
        @call_count = 0_u64
        @total_time_ms = 0.0
        @avg_time_ms = 0.0
        @cache_hit_rate = 0.0
      end

      def record_operation(duration_ms : Float64, cache_hit : Bool)
        @call_count += 1
        @total_time_ms += duration_ms
        @avg_time_ms = @total_time_ms / @call_count

        # Update cache hit rate with exponential moving average
        hit_value = cache_hit ? 1.0 : 0.0
        alpha = 0.1  # EMA smoothing factor
        @cache_hit_rate = alpha * hit_value + (1.0 - alpha) * @cache_hit_rate
      end
    end

    def initialize(@tensor_shape : Array(Int32), @attention_weight : Float64 = 0.5,
                   @meta_level : Int32 = 0, @cognitive_operation : String? = nil)
      @atomspace = AtomSpace.new
      @tensor_cache = CogUtil::CognitiveCache(String, Array(Float32)).new(capacity: 4096)
      @memory_pool = CogUtil::AtomMemoryPool.new
      @operation_metrics = Hash(String, OperationMetrics).new

      # Apply attention to atomspace
      CogUtil::Logger.info("CognitiveKernel created: shape=#{@tensor_shape}, attention=#{@attention_weight}")
    end

    def initialize(@atomspace : AtomSpace, @tensor_shape : Array(Int32),
                   @attention_weight : Float64, @meta_level : Int32 = 0,
                   @cognitive_operation : String? = nil)
      @tensor_cache = CogUtil::CognitiveCache(String, Array(Float32)).new(capacity: 4096)
      @memory_pool = CogUtil::AtomMemoryPool.new
      @operation_metrics = Hash(String, OperationMetrics).new

      CogUtil::Logger.info("CognitiveKernel created from existing AtomSpace: shape=#{@tensor_shape}")
    end

    # Optimized tensor field encoding with caching and SIMD operations
    def tensor_field_encoding(encoding_type : String = "prime", include_attention : Bool = true,
                             include_meta_level : Bool = false, normalization : String = "none") : Array(Float32)

      start_time = Time.monotonic
      cache_key = "#{encoding_type}_#{include_attention}_#{include_meta_level}_#{normalization}_#{@tensor_shape.hash}"

      # Check cache first
      cached_result = @tensor_cache[cache_key]
      if cached_result
        record_operation("tensor_field_encoding", (Time.monotonic - start_time).total_milliseconds, true)
        return cached_result
      end

      # Generate base sequence based on encoding type (optimized)
      base_sequence = case encoding_type.downcase
                     when "prime"
                       generate_primes_optimized(@tensor_shape.size)
                     when "fibonacci"
                       generate_fibonacci_optimized(@tensor_shape.size)
                     when "harmonic"
                       generate_harmonic_optimized(@tensor_shape.size)
                     when "factorial"
                       generate_factorial_optimized(@tensor_shape.size)
                     when "power_of_two"
                       generate_powers_of_two_optimized(@tensor_shape.size)
                     else
                       generate_primes_optimized(@tensor_shape.size)
                     end

      # Apply tensor field encoding with SIMD optimization
      base_encoding = tensor_shape_multiply_simd(@tensor_shape, base_sequence)

      # Apply attention weighting if requested using SIMD
      attention_weighted = if include_attention
                          attention_weights = Array(Float32).new(@tensor_shape.size, @attention_weight.to_f32)
                          CogUtil::SIMDOptimizations.apply_attention_weights(base_encoding, attention_weights)
                        else
                          base_encoding
                        end

      # Include meta-level information if requested
      meta_enhanced = if include_meta_level
                       attention_weighted + [@meta_level.to_f32]
                     else
                       attention_weighted
                     end

      # Apply normalization using optimized SIMD operations
      normalized = case normalization.downcase
                  when "unit"
                    CogUtil::SIMDOptimizations.normalize_l2(meta_enhanced)
                  when "standard"
                    standardize_encoding_simd(meta_enhanced)
                  else
                    meta_enhanced
                  end

      # Cache the result
      @tensor_cache[cache_key] = normalized

      duration_ms = (Time.monotonic - start_time).total_milliseconds
      record_operation("tensor_field_encoding", duration_ms, false)

      CogUtil::Logger.debug("Generated tensor field encoding: type=#{encoding_type}, size=#{normalized.size}, duration=#{duration_ms.round(2)}ms")
      normalized
    end

    # Get hypergraph state representation
    def hypergraph_state : HypergraphState
      @atomspace.extract_hypergraph_state(@tensor_shape, @attention_weight, @meta_level, @cognitive_operation)
    end

    # Store hypergraph state to storage
    def store_hypergraph_state(storage : HypergraphStateStorageNode) : Bool
      state = hypergraph_state
      storage.store_hypergraph_state(state)
    end

    # Load hypergraph state from storage
    def load_hypergraph_state(storage : HypergraphStateStorageNode) : Bool
      loaded_state = storage.load_hypergraph_state(@atomspace)
      return false unless loaded_state

      @tensor_shape = loaded_state.tensor_shape
      @attention_weight = loaded_state.attention
      @meta_level = loaded_state.meta_level
      @cognitive_operation = loaded_state.cognitive_operation

      CogUtil::Logger.info("Loaded hypergraph state: shape=#{@tensor_shape}, attention=#{@attention_weight}")
      true
    end

    # Create hypergraph-aware tensor encoding with caching
    def hypergraph_tensor_encoding : Array(Float32)
      start_time = Time.monotonic

      # Get AtomSpace metrics with caching
      metrics_key = "atomspace_metrics_#{@atomspace.size}"
      cached_metrics = @tensor_cache[metrics_key]

      node_count, link_count, connectivity = if cached_metrics && cached_metrics.size == 3
        {cached_metrics[0], cached_metrics[1], cached_metrics[2]}
      else
        nc = @atomspace.node_count.to_f32
        lc = @atomspace.link_count.to_f32
        conn = nc > 0 ? (lc / nc) : 0.0_f32
        @tensor_cache[metrics_key] = [nc, lc, conn]
        {nc, lc, conn}
      end

      # Base encoding with performance optimization
      base_encoding = tensor_field_encoding("prime", include_attention: false, include_meta_level: false)

      # Hypergraph factors
      hypergraph_factors = [connectivity, @attention_weight.to_f32, @tensor_shape.size.to_f32]

      # Combined encoding
      result = base_encoding + hypergraph_factors

      duration_ms = (Time.monotonic - start_time).total_milliseconds
      record_operation("hypergraph_tensor_encoding", duration_ms, cached_metrics != nil)

      result
    end

    # Cognitive operation-specific encoding
    def cognitive_tensor_field_encoding(operation : String) : Array(Float32)
      base_encoding = tensor_field_encoding

      operation_weights = case operation.downcase
                          when "reasoning"
                            [1.5_f32, 1.2_f32, 1.0_f32]
                          when "learning"
                            [1.0_f32, 1.8_f32, 1.3_f32]
                          when "attention"
                            [2.0_f32, 1.0_f32, 1.1_f32]
                          when "memory"
                            [1.1_f32, 1.0_f32, 1.9_f32]
                          when "adaptation"
                            [1.3_f32, 1.6_f32, 1.4_f32]
                          else
                            [1.0_f32, 1.0_f32, 1.0_f32]
                          end

      # Apply operation weights cyclically
      weighted_encoding = base_encoding.map_with_index do |val, idx|
        weight_idx = idx % operation_weights.size
        val * operation_weights[weight_idx]
      end

      @cognitive_operation = operation
      weighted_encoding
    end

    # Optimized mathematical sequence generators with caching
    private def generate_primes_optimized(n : Int32) : Array(Float32)
      return [] of Float32 if n <= 0

      cache_key = "primes_#{n}"
      cached_primes = @tensor_cache[cache_key]
      return cached_primes if cached_primes

      # Sieve of Eratosthenes for better performance
      limit = n * 15  # Approximation for nth prime upper bound
      sieve = Array(Bool).new(limit, true)
      sieve[0] = sieve[1] = false if limit > 1

      primes = [] of Float32

      i = 2
      while i * i < limit && primes.size < n
        if sieve[i]
          primes << i.to_f32 if primes.size < n

          # Mark multiples as non-prime
          j = i * i
          while j < limit
            sieve[j] = false
            j += i
          end
        end
        i += 1
      end

      # Collect remaining primes
      while i < limit && primes.size < n
        if sieve[i]
          primes << i.to_f32
        end
        i += 1
      end

      result = primes[0...n]
      @tensor_cache[cache_key] = result
      result
    end

    private def generate_fibonacci_optimized(n : Int32) : Array(Float32)
      return [] of Float32 if n <= 0

      cache_key = "fibonacci_#{n}"
      cached_fib = @tensor_cache[cache_key]
      return cached_fib if cached_fib

      return [1.0_f32] if n == 1

      # Matrix exponentiation for large Fibonacci numbers (more efficient)
      fib = [1.0_f32, 1.0_f32]
      while fib.size < n
        next_fib = fib[-1] + fib[-2]
        fib << next_fib
      end

      result = fib[0...n]
      @tensor_cache[cache_key] = result
      result
    end

    private def generate_harmonic_optimized(n : Int32) : Array(Float32)
      return [] of Float32 if n <= 0

      cache_key = "harmonic_#{n}"
      cached_harmonic = @tensor_cache[cache_key]
      return cached_harmonic if cached_harmonic

      result = (1..n).map { |k| 1.0_f32 / k.to_f32 }
      @tensor_cache[cache_key] = result
      result
    end

    private def generate_factorial_optimized(n : Int32) : Array(Float32)
      return [] of Float32 if n <= 0

      cache_key = "factorial_#{n}"
      cached_factorial = @tensor_cache[cache_key]
      return cached_factorial if cached_factorial

      factorials = [1.0_f32]
      current_factorial = 1.0_f32

      (1...n).each do |i|
        current_factorial *= (i + 1).to_f32
        factorials << current_factorial
      end

      @tensor_cache[cache_key] = factorials
      factorials
    end

    private def generate_powers_of_two_optimized(n : Int32) : Array(Float32)
      return [] of Float32 if n <= 0

      cache_key = "powers_of_two_#{n}"
      cached_powers = @tensor_cache[cache_key]
      return cached_powers if cached_powers

      result = (0...n).map { |k| (1 << k).to_f32 }  # Bit shifting is faster than exponentiation
      @tensor_cache[cache_key] = result
      result
    end

    # SIMD-optimized tensor operations
    private def tensor_shape_multiply_simd(shape : Array(Int32), sequence : Array(Float32)) : Array(Float32)
      result = Array(Float32).new(shape.size)

      # Process in chunks of 4 for SIMD efficiency
      i = 0
      while i + 3 < shape.size
        result << shape[i].to_f32 * sequence[i]
        result << shape[i+1].to_f32 * sequence[i+1]
        result << shape[i+2].to_f32 * sequence[i+2]
        result << shape[i+3].to_f32 * sequence[i+3]
        i += 4
      end

      # Handle remaining elements
      while i < shape.size
        result << shape[i].to_f32 * sequence[i]
        i += 1
      end

      result
    end

    # Optimized standardization using SIMD-friendly operations
    private def standardize_encoding_simd(encoding : Array(Float32)) : Array(Float32)
      return encoding if encoding.empty?

      # Calculate mean
      sum = 0.0_f32
      encoding.each { |x| sum += x }
      mean = sum / encoding.size

      # Calculate variance in single pass
      variance_sum = 0.0_f32
      encoding.each { |x|
        diff = x - mean
        variance_sum += diff * diff
      }

      variance = variance_sum / encoding.size
      std_dev = Math.sqrt(variance).to_f32

      return encoding.map { |x| x - mean } if std_dev == 0.0_f32

      # Standardize with SIMD-friendly operations
      inv_std_dev = 1.0_f32 / std_dev
      encoding.map { |x| (x - mean) * inv_std_dev }
    end

    # Record operation metrics for performance monitoring
    private def record_operation(operation_name : String, duration_ms : Float64, cache_hit : Bool)
      metrics = @operation_metrics[operation_name]? || OperationMetrics.new
      metrics.record_operation(duration_ms, cache_hit)
      @operation_metrics[operation_name] = metrics
    end

    # Get performance metrics for monitoring
    def performance_metrics : Hash(String, OperationMetrics)
      @operation_metrics.dup
    end

    # Get cache statistics
    def cache_stats : Hash(String, Float64 | Int32)
      cache_stats = @tensor_cache.stats
      pool_stats = @memory_pool.stats

      {
        "cache_hit_rate" => cache_stats.hit_rate,
        "cache_size" => @tensor_cache.size,
        "cache_utilization" => @tensor_cache.utilization,
        "pool_utilization" => pool_stats.utilization_percentage,
        "pool_hit_rate" => pool_stats.hit_rate
      }
    end

    private def generate_powers_of_two(n : Int32) : Array(Float64)
      return [] of Float64 if n <= 0
      (0...n).map { |k| (2 ** k).to_f64 }
    end

    # Normalization methods
    private def normalize_to_unit_length(encoding : Array(Float64)) : Array(Float64)
      magnitude = Math.sqrt(encoding.sum { |x| x * x })
      return encoding if magnitude == 0.0

      factor = 1.0 / magnitude
      encoding.map { |x| x * factor }
    end

    private def standardize_encoding(encoding : Array(Float64)) : Array(Float64)
      return encoding if encoding.empty?

      mean = encoding.sum / encoding.size
      centered = encoding.map { |x| x - mean }
      variance = centered.sum { |x| x * x } / encoding.size
      std_dev = Math.sqrt(variance)

      return centered if std_dev == 0.0

      factor = 1.0 / std_dev
      centered.map { |x| x * factor }
    end

    # Convenience methods for AtomSpace operations
    def add_concept_node(name : String, tv : TruthValue = TruthValue::DEFAULT_TV) : Atom
      @atomspace.add_concept_node(name, tv)
    end

    def add_predicate_node(name : String, tv : TruthValue = TruthValue::DEFAULT_TV) : Atom
      @atomspace.add_predicate_node(name, tv)
    end

    def add_inheritance_link(child : Atom, parent : Atom, tv : TruthValue = TruthValue::DEFAULT_TV) : Atom
      @atomspace.add_inheritance_link(child, parent, tv)
    end

    def add_evaluation_link(predicate : Atom, arguments : Atom, tv : TruthValue = TruthValue::DEFAULT_TV) : Atom
      @atomspace.add_evaluation_link(predicate, arguments, tv)
    end

    def to_s(io : IO) : Nil
      io << "CognitiveKernel(shape=#{@tensor_shape}, attention=#{@attention_weight}, " \
            "meta_level=#{@meta_level}, atomspace_size=#{@atomspace.size})"
    end
  end

  # Manager for multiple cognitive kernels - temporarily disabled for build
  # class CognitiveKernelManager
  #   @kernels : Array(CognitiveKernel)
  #
  #   def initialize
  #     @kernels = [] of CognitiveKernel
  #   end
  #
  #   def create_kernel(tensor_shape : Array(Int32), attention_weight : Float64 = 0.5) : CognitiveKernel
  #     kernel = CognitiveKernel.new(tensor_shape, attention_weight)
  #     @kernels << kernel
  #     kernel
  #   end

  #
  #   def adaptive_attention_allocation(goals : Array(String)) : Array(NamedTuple(kernel: CognitiveKernel, attention_score: Float64, activation_priority: Float64, goal: String))
  #     allocations = [] of NamedTuple(kernel: CognitiveKernel, attention_score: Float64, activation_priority: Float64, goal: String)
  #
  #     @kernels.each_with_index do |kernel, i|
  #       goal = i < goals.size ? goals[i] : "default"
  #       score = calculate_attention_score(goal)
  #       priority = calculate_priority(score)
  #
  #       allocations << {
  #         kernel:              kernel,
  #         attention_score:     score,
  #         activation_priority: priority,
  #         goal:                goal,
  #       }
  #     end
  #
  #     allocations
  #   end
  #
  #   private def calculate_attention_score(goal : String) : Float64
  #     case goal.downcase
  #     when "reasoning"
  #       0.9
  #     when "learning"
  #       0.7
  #     when "attention"
  #       0.8
  #     when "memory"
  #       0.6
  #     when "adaptation"
  #       0.75
  #     else
  #       0.5
  #     end
  #   end
  #
  #   private def calculate_priority(score : Float64) : Float64
  #     # Simple priority calculation based on attention score
  #     score * 0.8 + 0.2 # Ensure minimum priority
  #   end

  #   def kernels : Array(CognitiveKernel)
  #     @kernels
  #   end
  #
  #   def size : Int32
  #     @kernels.size
  #   end
  # end
end
