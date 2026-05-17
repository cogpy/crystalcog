# Crystal CogUtil performance optimization module
# Provides high-performance memory pooling and cache-optimized data structures
# for Agent-Zero Genesis cognitive operations

module CogUtil
  # Memory pool for high-frequency atom allocations
  # Reduces GC pressure and improves cache locality
  class AtomMemoryPool
    # Pool configuration
    POOL_SIZE  = 10000
    BLOCK_SIZE =   128 # bytes per block

    # Use heap-allocated memory instead of StaticArray to avoid compiler crashes
    # with large static allocations
    @blocks : Pointer(UInt8)
    @blocks_size : Int32
    @free_blocks : Array(Int32)
    @allocated_blocks : Set(Int32)
    @mutex : Mutex
    @stats : PoolStats

    struct PoolStats
      property total_allocations : UInt64
      property total_deallocations : UInt64
      property peak_usage : Int32
      property current_usage : Int32
      property cache_hits : UInt64
      property cache_misses : UInt64

      def initialize
        @total_allocations = 0_u64
        @total_deallocations = 0_u64
        @peak_usage = 0
        @current_usage = 0
        @cache_hits = 0_u64
        @cache_misses = 0_u64
      end

      def utilization_percentage : Float64
        return 0.0 if POOL_SIZE == 0
        (@current_usage.to_f / POOL_SIZE) * 100.0
      end

      def hit_rate : Float64
        total_requests = @cache_hits + @cache_misses
        return 0.0 if total_requests == 0
        (@cache_hits.to_f / total_requests) * 100.0
      end
    end

    def initialize
      @blocks_size = POOL_SIZE * BLOCK_SIZE
      @blocks = Pointer(UInt8).malloc(@blocks_size)
      @blocks.clear(@blocks_size)
      @free_blocks = Array(Int32).new(POOL_SIZE) { |i| i }
      @allocated_blocks = Set(Int32).new
      @mutex = Mutex.new
      @stats = PoolStats.new

      Logger.info("AtomMemoryPool initialized: #{POOL_SIZE} blocks of #{BLOCK_SIZE} bytes")
    end

    # Allocate a block from the pool
    def allocate : Pointer(UInt8)?
      @mutex.synchronize do
        if @free_blocks.empty?
          @stats.cache_misses += 1
          Logger.debug("AtomMemoryPool: Pool exhausted, falling back to system allocation")
          return Pointer(UInt8).malloc(BLOCK_SIZE)
        end

        block_index = @free_blocks.pop
        @allocated_blocks.add(block_index)
        @stats.total_allocations += 1
        @stats.current_usage += 1
        @stats.cache_hits += 1

        if @stats.current_usage > @stats.peak_usage
          @stats.peak_usage = @stats.current_usage
        end

        # Return pointer to block
        @blocks + (block_index * BLOCK_SIZE)
      end
    end

    # Deallocate a block back to the pool
    def deallocate(ptr : Pointer(UInt8)) : Bool
      @mutex.synchronize do
        # Check if pointer is within our pool range
        pool_start = @blocks
        pool_end = pool_start + @blocks_size

        if ptr < pool_start || ptr >= pool_end
          # This was allocated outside the pool
          Logger.debug("AtomMemoryPool: Deallocating non-pool memory")
          return false
        end

        # Calculate block index
        offset = ptr - pool_start
        block_index = offset // BLOCK_SIZE

        if @allocated_blocks.includes?(block_index)
          @allocated_blocks.delete(block_index)
          @free_blocks.push(block_index)
          @stats.total_deallocations += 1
          @stats.current_usage -= 1

          # Zero out the block for security
          memset(ptr, 0, BLOCK_SIZE)
          return true
        else
          Logger.warn("AtomMemoryPool: Attempt to deallocate non-allocated block #{block_index}")
          return false
        end
      end
    end

    # Get current pool statistics
    def stats : PoolStats
      @mutex.synchronize { @stats.dup }
    end

    # Reset pool statistics
    def reset_stats
      @mutex.synchronize do
        @stats = PoolStats.new
        Logger.info("AtomMemoryPool: Statistics reset")
      end
    end

    # Check pool health and integrity
    def health_check : Hash(String, Bool | Float64 | Int32)
      stats = self.stats
      {
        "healthy"             => stats.utilization_percentage < 90.0,
        "utilization_percent" => stats.utilization_percentage,
        "hit_rate_percent"    => stats.hit_rate,
        "peak_usage"          => stats.peak_usage,
        "current_usage"       => stats.current_usage,
        "fragmentation_low"   => @free_blocks.size + @allocated_blocks.size == POOL_SIZE,
      }
    end

    # Note: Memory allocated with Pointer.malloc is managed by Crystal's GC
    # (via GC.malloc_atomic under the hood), so no explicit cleanup is needed.

    private def memset(ptr : Pointer(UInt8), value : UInt8, size : Int32)
      size.times { |i| ptr[i] = value }
    end
  end

  # Cache-optimized data structure for cognitive operations
  class CognitiveCache(K, V)
    # Cache configuration optimized for cognitive workloads
    DEFAULT_CAPACITY = 8192
    LOAD_FACTOR      = 0.75

    @buckets : Array(Array(Entry(K, V)))
    @capacity : Int32
    @size : Int32
    @threshold : Int32
    @mutex : Mutex
    @stats : CacheStats

    struct Entry(K, V)
      property key : K
      property value : V
      property access_count : UInt32
      property last_access : Time

      def initialize(@key : K, @value : V)
        @access_count = 1_u32
        @last_access = Time.utc
      end

      def accessed!
        @access_count += 1
        @last_access = Time.utc
      end
    end

    struct CacheStats
      property hits : UInt64
      property misses : UInt64
      property evictions : UInt64
      property capacity_resizes : UInt32

      def initialize
        @hits = 0_u64
        @misses = 0_u64
        @evictions = 0_u64
        @capacity_resizes = 0_u32
      end

      def hit_rate : Float64
        total = @hits + @misses
        return 0.0 if total == 0
        (@hits.to_f / total) * 100.0
      end
    end

    def initialize(@capacity : Int32 = DEFAULT_CAPACITY)
      @buckets = Array.new(@capacity) { Array(Entry(K, V)).new }
      @size = 0
      @threshold = (@capacity * LOAD_FACTOR).to_i
      @mutex = Mutex.new
      @stats = CacheStats.new

      Logger.debug("CognitiveCache initialized: capacity=#{@capacity}")
    end

    # Get value by key with cache optimization
    def [](key : K) : V?
      @mutex.synchronize do
        bucket_index = hash_key(key) % @capacity
        bucket = @buckets[bucket_index]

        bucket.each do |entry|
          if entry.key == key
            entry.accessed!
            @stats.hits += 1
            return entry.value
          end
        end

        @stats.misses += 1
        nil
      end
    end

    # Set value by key with LFU eviction
    def []=(key : K, value : V)
      @mutex.synchronize do
        resize_if_needed

        bucket_index = hash_key(key) % @capacity
        bucket = @buckets[bucket_index]

        # Check if key already exists
        bucket.each do |entry|
          if entry.key == key
            entry.value = value
            entry.accessed!
            return value
          end
        end

        # Add new entry
        bucket << Entry.new(key, value)
        @size += 1

        # Evict if bucket is too large (max 4 entries per bucket for cache efficiency)
        if bucket.size > 4
          evict_from_bucket(bucket)
        end

        value
      end
    end

    # Check if key exists
    def has_key?(key : K) : Bool
      self[key] != nil
    end

    # Remove key
    def delete(key : K) : V?
      @mutex.synchronize do
        bucket_index = hash_key(key) % @capacity
        bucket = @buckets[bucket_index]

        bucket.each_with_index do |entry, i|
          if entry.key == key
            removed_entry = bucket.delete_at(i)
            @size -= 1
            return removed_entry.value
          end
        end

        nil
      end
    end

    # Get cache statistics
    def stats : CacheStats
      @mutex.synchronize { @stats.dup }
    end

    # Current cache size
    def size : Int32
      @mutex.synchronize { @size }
    end

    # Current cache capacity
    def capacity : Int32
      @capacity
    end

    # Cache utilization percentage
    def utilization : Float64
      (@size.to_f / @capacity) * 100.0
    end

    # Clear all entries
    def clear
      @mutex.synchronize do
        @buckets.each(&.clear)
        @size = 0
        Logger.debug("CognitiveCache cleared")
      end
    end

    private def hash_key(key : K) : UInt32
      # Use Crystal's built-in hash for type safety
      key.hash.to_u32
    end

    private def resize_if_needed
      return unless @size >= @threshold

      old_capacity = @capacity
      @capacity *= 2
      @threshold = (@capacity * LOAD_FACTOR).to_i

      old_buckets = @buckets
      @buckets = Array.new(@capacity) { Array(Entry(K, V)).new }
      @size = 0

      # Rehash all entries
      old_buckets.each do |bucket|
        bucket.each do |entry|
          self[entry.key] = entry.value
        end
      end

      @stats.capacity_resizes += 1
      Logger.debug("CognitiveCache resized: #{old_capacity} -> #{@capacity}")
    end

    private def evict_from_bucket(bucket : Array(Entry(K, V)))
      # Find least frequently used entry
      lfu_entry = bucket.min_by(&.access_count)
      bucket.delete(lfu_entry)
      @size -= 1
      @stats.evictions += 1
    end
  end

  # SIMD-optimized vector operations for cognitive tensors
  module SIMDOptimizations
    # Vectorized dot product for cognitive attention calculations
    def self.dot_product(a : Array(Float32), b : Array(Float32)) : Float32
      return 0.0_f32 if a.size != b.size || a.empty?

      result = 0.0_f32
      size = a.size

      # Process 4 elements at a time (SIMD-friendly)
      i = 0
      while i + 3 < size
        result += a[i] * b[i] + a[i + 1] * b[i + 1] + a[i + 2] * b[i + 2] + a[i + 3] * b[i + 3]
        i += 4
      end

      # Handle remaining elements
      while i < size
        result += a[i] * b[i]
        i += 1
      end

      result
    end

    # Vectorized attention weight application
    def self.apply_attention_weights(tensor : Array(Float32), weights : Array(Float32)) : Array(Float32)
      return tensor if tensor.size != weights.size || tensor.empty?

      result = Array(Float32).new(tensor.size)
      size = tensor.size

      # Process 4 elements at a time
      i = 0
      while i + 3 < size
        result << tensor[i] * weights[i]
        result << tensor[i + 1] * weights[i + 1]
        result << tensor[i + 2] * weights[i + 2]
        result << tensor[i + 3] * weights[i + 3]
        i += 4
      end

      # Handle remaining elements
      while i < size
        result << tensor[i] * weights[i]
        i += 1
      end

      result
    end

    # Fast normalization for cognitive tensors
    def self.normalize_l2(vector : Array(Float32)) : Array(Float32)
      return vector if vector.empty?

      # Calculate magnitude
      magnitude_squared = 0.0_f32
      vector.each { |x| magnitude_squared += x * x }

      return vector if magnitude_squared == 0.0_f32

      magnitude = Math.sqrt(magnitude_squared)
      inv_magnitude = 1.0_f32 / magnitude

      # Normalize
      vector.map { |x| x * inv_magnitude }
    end
  end
end
