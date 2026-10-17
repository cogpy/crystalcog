# Control case: same capacity and initialization, no large by-value aggregate.
class LargeHeapPool
  SIZE = 1_280_000
  @blocks : Bytes

  def initialize
    @blocks = Bytes.new(SIZE, 0_u8)
  end

  def first_byte : UInt8
    @blocks[0]
  end
end

puts LargeHeapPool.new.first_byte
