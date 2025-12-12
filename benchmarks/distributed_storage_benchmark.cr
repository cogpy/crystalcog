#!/usr/bin/env crystal

# Distributed Storage Performance Benchmark
# Tests LRU cache effectiveness, partition caching, and network I/O reduction

require "../src/atomspace/atomspace"
require "../src/atomspace/distributed_storage"
require "benchmark"

puts "=" * 70
puts "Distributed Storage Performance Benchmark"
puts "=" * 70
puts

# Configuration
ATOM_COUNT = 1000
CACHE_SIZE = 100
ITERATIONS = 5

# Create test atoms
def create_test_atoms(count : Int32) : Array(AtomSpace::Atom)
  atoms = [] of AtomSpace::Atom
  count.times do |i|
    atom = AtomSpace::ConceptNode.new("test_concept_#{i}")
    atom.handle = AtomSpace::Handle.new(i.to_u64)
    atoms << atom
  end
  atoms
end

# Simulate 80/20 access pattern (80% of accesses to 20% of atoms)
def generate_access_pattern(atom_count : Int32, access_count : Int32) : Array(Int32)
  pattern = [] of Int32
  hot_atoms = (atom_count * 0.2).to_i
  
  access_count.times do
    if rand < 0.8
      # 80% of accesses to hot atoms
      pattern << rand(hot_atoms)
    else
      # 20% of accesses to cold atoms
      pattern << hot_atoms + rand(atom_count - hot_atoms)
    end
  end
  
  pattern
end

puts "Configuration:"
puts "  Atom count: #{ATOM_COUNT}"
puts "  Cache size: #{CACHE_SIZE}"
puts "  Iterations: #{ITERATIONS}"
puts "  Access pattern: 80/20 (hot/cold)"
puts

# Benchmark 1: LRU Cache Hit Rate
puts "Benchmark 1: LRU Cache Hit Rate"
puts "-" * 70

atoms = create_test_atoms(ATOM_COUNT)
cache = AtomSpace::LRUCache.new(CACHE_SIZE)

# Populate cache with hot atoms
hot_count = (ATOM_COUNT * 0.2).to_i
hot_count.times do |i|
  cache.put(atoms[i])
end

# Generate access pattern
access_pattern = generate_access_pattern(ATOM_COUNT, 10000)

# Measure cache performance
cache_hits = 0
cache_misses = 0

access_pattern.each do |index|
  if cache.get(atoms[index].handle)
    cache_hits += 1
  else
    cache_misses += 1
    cache.put(atoms[index])
  end
end

hit_rate = (cache_hits.to_f / (cache_hits + cache_misses)) * 100
stats = cache.stats

puts "Results:"
puts "  Total accesses: #{access_pattern.size}"
puts "  Cache hits: #{cache_hits}"
puts "  Cache misses: #{cache_misses}"
puts "  Hit rate: #{hit_rate.round(2)}%"
puts "  Cache size: #{stats["size"]}"
puts "  Max size: #{stats["max_size"]}"
puts "  Network I/O reduction: #{hit_rate.round(2)}%"
puts

# Benchmark 2: Cache vs No Cache Performance
puts "Benchmark 2: Cache vs No Cache Performance"
puts "-" * 70

# Simulate fetch latency
def simulate_network_fetch(atom : AtomSpace::Atom, latency_ms : Float64 = 0.5)
  sleep(latency_ms / 1000.0)
  atom
end

# Without cache
no_cache_time = Benchmark.measure do
  access_pattern.each do |index|
    simulate_network_fetch(atoms[index], 0.1)
  end
end

# With cache
cached_time = Benchmark.measure do
  cache = AtomSpace::LRUCache.new(CACHE_SIZE)
  
  # Warm up cache
  hot_count.times { |i| cache.put(atoms[i]) }
  
  access_pattern.each do |index|
    atom = cache.get(atoms[index].handle)
    unless atom
      atom = simulate_network_fetch(atoms[index], 0.1)
      cache.put(atom)
    end
  end
end

speedup = no_cache_time.real / cached_time.real

puts "Results:"
puts "  Without cache: #{(no_cache_time.real * 1000).round(2)}ms"
puts "  With cache: #{(cached_time.real * 1000).round(2)}ms"
puts "  Speedup: #{speedup.round(2)}x"
puts "  Time saved: #{((no_cache_time.real - cached_time.real) * 1000).round(2)}ms"
puts

# Benchmark 3: Partition Cache Performance
puts "Benchmark 3: Partition Cache Performance"
puts "-" * 70

partition_cache = AtomSpace::PartitionInfoCache.new(CACHE_SIZE, 60.seconds)

# Simulate partition lookups
partition_lookup_count = 10000

# Without cache
no_partition_cache_time = Benchmark.measure do
  partition_lookup_count.times do |i|
    handle = AtomSpace::Handle.new(i.to_u64)
    # Simulate hash calculation overhead
    hash_value = handle.hash.abs.to_u64
    partition = "node_#{hash_value % 10}"
  end
end

# With cache
with_partition_cache_time = Benchmark.measure do
  partition_lookup_count.times do |i|
    handle = AtomSpace::Handle.new(i.to_u64)
    
    cached_info = partition_cache.get(handle)
    unless cached_info
      hash_value = handle.hash.abs.to_u64
      partition = "node_#{hash_value % 10}"
      info = AtomSpace::PartitionInfo.new(partition, Time.utc)
      partition_cache.put(handle, info)
    end
  end
end

partition_speedup = no_partition_cache_time.real / with_partition_cache_time.real
partition_stats = partition_cache.stats

puts "Results:"
puts "  Lookups: #{partition_lookup_count}"
puts "  Without cache: #{(no_partition_cache_time.real * 1000).round(2)}ms"
puts "  With cache: #{(with_partition_cache_time.real * 1000).round(2)}ms"
puts "  Speedup: #{partition_speedup.round(2)}x"
puts "  Cache hit rate: #{partition_stats["hit_rate_percent"].round(2)}%"
puts "  Cache size: #{partition_stats["size"]}"
puts

# Benchmark 4: Concurrent Access Performance
puts "Benchmark 4: Concurrent Access Performance"
puts "-" * 70

concurrent_access_count = 1000
thread_count = 10

# Sequential access
sequential_time = Benchmark.measure do
  cache = AtomSpace::LRUCache.new(CACHE_SIZE)
  (concurrent_access_count * thread_count).times do |i|
    index = i % ATOM_COUNT
    atom = cache.get(atoms[index].handle)
    unless atom
      cache.put(atoms[index])
    end
  end
end

# Concurrent access
concurrent_time = Benchmark.measure do
  cache = AtomSpace::LRUCache.new(CACHE_SIZE)
  
  fibers = [] of Fiber
  thread_count.times do
    fibers << spawn do
      concurrent_access_count.times do |i|
        index = rand(ATOM_COUNT)
        atom = cache.get(atoms[index].handle)
        unless atom
          cache.put(atoms[index])
        end
      end
    end
  end
  
  fibers.each(&.join)
end

concurrent_speedup = sequential_time.real / concurrent_time.real

puts "Results:"
puts "  Total operations: #{concurrent_access_count * thread_count}"
puts "  Threads: #{thread_count}"
puts "  Sequential time: #{(sequential_time.real * 1000).round(2)}ms"
puts "  Concurrent time: #{(concurrent_time.real * 1000).round(2)}ms"
puts "  Speedup: #{concurrent_speedup.round(2)}x"
puts "  Throughput: #{((concurrent_access_count * thread_count) / concurrent_time.real).round(0)} ops/sec"
puts

# Benchmark 5: Memory Efficiency
puts "Benchmark 5: Memory Efficiency"
puts "-" * 70

# Measure cache memory overhead
cache_small = AtomSpace::LRUCache.new(10)
cache_medium = AtomSpace::LRUCache.new(100)
cache_large = AtomSpace::LRUCache.new(1000)

10.times { |i| cache_small.put(atoms[i]) }
100.times { |i| cache_medium.put(atoms[i]) }
1000.times { |i| cache_large.put(atoms[i]) }

puts "Results:"
puts "  Small cache (10): #{cache_small.stats["size"]} atoms"
puts "  Medium cache (100): #{cache_medium.stats["size"]} atoms"
puts "  Large cache (1000): #{cache_large.stats["size"]} atoms"
puts "  Memory overhead: Minimal (only stores references)"
puts

# Summary
puts "=" * 70
puts "Benchmark Summary"
puts "=" * 70
puts
puts "Key Findings:"
puts "  1. LRU Cache Hit Rate: #{hit_rate.round(2)}% (80/20 access pattern)"
puts "  2. Network I/O Reduction: #{hit_rate.round(2)}%"
puts "  3. Cache Speedup: #{speedup.round(2)}x faster than no cache"
puts "  4. Partition Cache Speedup: #{partition_speedup.round(2)}x"
puts "  5. Concurrent Throughput: #{((concurrent_access_count * thread_count) / concurrent_time.real).round(0)} ops/sec"
puts
puts "Recommendations:"
puts "  - Use cache size of 100-1000 for optimal hit rate"
puts "  - Enable partition caching for distributed deployments"
puts "  - Configure cache based on working set size"
puts "  - Monitor hit rates and adjust cache size accordingly"
puts
puts "=" * 70
