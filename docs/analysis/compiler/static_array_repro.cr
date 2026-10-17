# Reduced from CogUtil::AtomMemoryPool. No network, AtomSpace, or shards.
class LargeInlinePool
  SIZE = 1_280_000
  @blocks : StaticArray(UInt8, SIZE)

  def initialize
    @blocks = StaticArray(UInt8, SIZE).new(0_u8)
  end

  def first_byte : UInt8
    @blocks[0]
  end
end

puts LargeInlinePool.new.first_byte
