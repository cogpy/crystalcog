require "spec"
require "../../src/cogutil/performance_optimization"

describe CogUtil::CognitiveCache do
  it "stores and retrieves values" do
    cache = CogUtil::CognitiveCache(String, Int32).new(16)
    cache["a"] = 1
    cache["b"] = 2

    cache["a"].should eq(1)
    cache["b"].should eq(2)
    cache.size.should eq(2)
  end

  it "returns nil for missing keys" do
    cache = CogUtil::CognitiveCache(String, Int32).new(16)
    cache["missing"].should be_nil
  end

  it "tracks hits and misses" do
    cache = CogUtil::CognitiveCache(String, Int32).new(16)
    cache["x"] = 10
    cache["x"]        # hit
    cache["absent"]   # miss

    stats = cache.stats
    stats.hits.should eq(1_u64)
    stats.misses.should eq(1_u64)
    stats.hit_rate.should eq(50.0)
  end

  it "supports has_key? and delete" do
    cache = CogUtil::CognitiveCache(String, Int32).new(16)
    cache["k"] = 5
    cache.has_key?("k").should be_true

    cache.delete("k").should eq(5)
    cache.has_key?("k").should be_false
    cache.size.should eq(0)
  end

  it "reports utilization and capacity" do
    cache = CogUtil::CognitiveCache(String, Int32).new(100)
    10.times { |i| cache["key#{i}"] = i }
    cache.capacity.should eq(100)
    cache.utilization.should be > 0.0
  end

  it "clears all entries" do
    cache = CogUtil::CognitiveCache(String, Int32).new(16)
    cache["a"] = 1
    cache.clear
    cache.size.should eq(0)
    cache["a"].should be_nil
  end
end

describe CogUtil::AtomMemoryPool do
  it "allocates and deallocates blocks" do
    pool = CogUtil::AtomMemoryPool.new
    ptr = pool.allocate
    ptr.should_not be_nil
    pool.deallocate(ptr.not_nil!).should be_true
  end

  it "tracks allocation statistics" do
    pool = CogUtil::AtomMemoryPool.new
    pool.reset_stats
    ptr = pool.allocate
    stats = pool.stats
    stats.total_allocations.should be >= 1_u64
    pool.deallocate(ptr.not_nil!)
  end

  it "reports health check information" do
    pool = CogUtil::AtomMemoryPool.new
    health = pool.health_check
    health.should be_a(Hash(String, Bool | Float64 | Int32))
  end
end

describe CogUtil::SIMDOptimizations do
  it "computes dot product" do
    a = [1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
    b = [5.0_f32, 6.0_f32, 7.0_f32, 8.0_f32]
    CogUtil::SIMDOptimizations.dot_product(a, b).should eq(70.0_f32)
  end

  it "returns zero for mismatched or empty vectors" do
    CogUtil::SIMDOptimizations.dot_product([1.0_f32], [1.0_f32, 2.0_f32]).should eq(0.0_f32)
    CogUtil::SIMDOptimizations.dot_product([] of Float32, [] of Float32).should eq(0.0_f32)
  end

  it "applies attention weights elementwise" do
    tensor = [1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
    weights = [2.0_f32, 2.0_f32, 2.0_f32, 2.0_f32]
    CogUtil::SIMDOptimizations.apply_attention_weights(tensor, weights).should eq([2.0_f32, 4.0_f32, 6.0_f32, 8.0_f32])
  end

  it "normalizes a vector to unit L2 norm" do
    v = [3.0_f32, 4.0_f32]
    normalized = CogUtil::SIMDOptimizations.normalize_l2(v)
    normalized[0].should be_close(0.6_f32, 1e-6)
    normalized[1].should be_close(0.8_f32, 1e-6)
  end

  it "returns the vector unchanged when magnitude is zero" do
    v = [0.0_f32, 0.0_f32]
    CogUtil::SIMDOptimizations.normalize_l2(v).should eq(v)
  end
end
