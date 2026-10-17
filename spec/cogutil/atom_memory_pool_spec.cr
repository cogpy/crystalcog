require "spec"
require "../../src/cogutil/logger"
require "../../src/cogutil/performance_optimization"

describe CogUtil::AtomMemoryPool do
  it "allocates all configured contiguous blocks with zero-filled storage" do
    pool = CogUtil::AtomMemoryPool.new
    blocks = Array(Pointer(UInt8)).new
    CogUtil::AtomMemoryPool::POOL_SIZE.times do
      blocks << pool.allocate.not_nil!
    end
    blocks.map(&.address).to_set.size.should eq(CogUtil::AtomMemoryPool::POOL_SIZE)
    (blocks.first - blocks.last).should eq(CogUtil::AtomMemoryPool::TOTAL_SIZE - CogUtil::AtomMemoryPool::BLOCK_SIZE)
    blocks.first[0].should eq(0_u8)
    blocks.last[CogUtil::AtomMemoryPool::BLOCK_SIZE - 1].should eq(0_u8)
    stats = pool.stats
    stats.current_usage.should eq(CogUtil::AtomMemoryPool::POOL_SIZE)
    stats.peak_usage.should eq(CogUtil::AtomMemoryPool::POOL_SIZE)
    stats.cache_hits.should eq(CogUtil::AtomMemoryPool::POOL_SIZE)
    blocks.each { |block| pool.deallocate(block).should be_true }
    pool.stats.current_usage.should eq(0)
  end

  it "keeps allocated bytes alive across garbage collection and zeros reused blocks" do
    pool = CogUtil::AtomMemoryPool.new
    block = pool.allocate.not_nil!
    CogUtil::AtomMemoryPool::BLOCK_SIZE.times { |i| block[i] = 0xa5_u8 }
    GC.collect
    block[0].should eq(0xa5_u8)
    block[CogUtil::AtomMemoryPool::BLOCK_SIZE - 1].should eq(0xa5_u8)
    pool.deallocate(block).should be_true
    pool.deallocate(block).should be_false
    reused = pool.allocate.not_nil!
    reused.should eq(block)
    CogUtil::AtomMemoryPool::BLOCK_SIZE.times { |i| reused[i].should eq(0_u8) }
    pool.deallocate(reused).should be_true
  end

  it "rejects interior and external pointers without corrupting allocation bookkeeping" do
    pool = CogUtil::AtomMemoryPool.new
    block = pool.allocate.not_nil!
    block[0] = 0x77_u8
    pool.deallocate(block + 1).should be_false
    pool.deallocate(Pointer(UInt8).null).should be_false
    pool.deallocate(Bytes.new(128).to_unsafe).should be_false
    pool.stats.current_usage.should eq(1)
    block[0].should eq(0x77_u8)
    pool.deallocate(block).should be_true
  end
end
