# Safetensors reader: an 8-byte little-endian header length, a JSON header
# mapping tensor names to {dtype, shape, data_offsets}, then raw data.
# Weights stay in BF16 (UInt16) form; F16/F32 tensors are converted to BF16
# so the kernels have a single storage type.

require "json"

module AphroditeJax
  class Safetensors
    record Entry, dtype : String, shape : Array(Int64), start : Int64, stop : Int64

    getter path : String
    getter entries : Hash(String, Entry)
    @data_start : Int64

    def initialize(@path : String)
      @entries = {} of String => Entry
      header, header_len = File.open(@path) do |f|
        n = f.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
        raise ArgumentError.new("#{@path}: implausible header size #{n}") if n > 100_000_000
        {JSON.parse(f.read_string(n.to_i32)), n}
      end
      @data_start = 8_i64 + header_len.to_i64
      header.as_h.each do |name, info|
        next if name == "__metadata__"
        offsets = info["data_offsets"].as_a.map(&.as_i64)
        @entries[name] = Entry.new(info["dtype"].as_s, info["shape"].as_a.map(&.as_i64), offsets[0], offsets[1])
      end
    end

    def has?(name : String) : Bool
      @entries.has_key?(name)
    end

    def shape(name : String) : Array(Int64)
      entry(name).shape
    end

    # Tensor contents as BF16 bit patterns, row-major.
    def bf16(name : String) : Slice(UInt16)
      e = entry(name)
      count = e.shape.product(1_i64).to_i32
      raw = Bytes.new(e.stop - e.start)
      File.open(@path) do |f|
        f.seek(@data_start + e.start)
        f.read_fully(raw)
      end
      case e.dtype
      when "BF16"
        check_size(name, raw, count * 2)
        if IO::ByteFormat::SystemEndian == IO::ByteFormat::LittleEndian
          Slice(UInt16).new(raw.to_unsafe.as(Pointer(UInt16)), count)
        else
          Slice(UInt16).new(count) { |i| IO::ByteFormat::LittleEndian.decode(UInt16, raw[i * 2, 2]) }
        end
      when "F32"
        check_size(name, raw, count * 4)
        Slice(UInt16).new(count) do |i|
          AphroditeJax.f32_to_bf16(IO::ByteFormat::LittleEndian.decode(Float32, raw[i * 4, 4]))
        end
      when "F16"
        check_size(name, raw, count * 2)
        Slice(UInt16).new(count) do |i|
          AphroditeJax.f32_to_bf16(AphroditeJax.f16_to_f32(IO::ByteFormat::LittleEndian.decode(UInt16, raw[i * 2, 2])))
        end
      else
        raise ArgumentError.new("#{name}: unsupported dtype #{e.dtype}")
      end
    end

    # Small tensors (norm weights) as Float32.
    def f32(name : String) : Slice(Float32)
      bf16(name).map { |b| AphroditeJax.bf16_to_f32(b) }
    end

    private def entry(name) : Entry
      @entries[name]? || raise KeyError.new("tensor #{name} not found in #{@path}")
    end

    private def check_size(name, raw, expected)
      raise ArgumentError.new("#{name}: expected #{expected} bytes, got #{raw.size}") unless raw.size == expected
    end
  end

  # A model may be split across shards (model-00001-of-0000N.safetensors).
  class TensorSet
    @files : Array(Safetensors)

    def initialize(dir : String)
      # Dir.children rather than Dir.glob: glob patterns break on Windows
      # backslash paths.
      paths = Dir.children(dir).select(&.ends_with?(".safetensors")).sort.map { |f| File.join(dir, f) }
      raise ArgumentError.new("no .safetensors files in #{dir}") if paths.empty?
      @files = paths.map { |p| Safetensors.new(p) }
    end

    def has?(name : String) : Bool
      @files.any?(&.has?(name))
    end

    def file(name : String) : Safetensors
      @files.find(&.has?(name)) || raise KeyError.new("tensor #{name} not found")
    end

    def bf16(name : String) : Slice(UInt16)
      file(name).bf16(name)
    end

    def f32(name : String) : Slice(Float32)
      file(name).f32(name)
    end

    def shape(name : String) : Array(Int64)
      file(name).shape(name)
    end
  end

  @[AlwaysInline]
  def self.bf16_to_f32(b : UInt16) : Float32
    (b.to_u32 << 16).unsafe_as(Float32)
  end

  # Round-to-nearest-even truncation of an f32 to bf16.
  def self.f32_to_bf16(f : Float32) : UInt16
    bits = f.unsafe_as(UInt32)
    return ((bits >> 16) | 0x40_u32).to_u16 if f.nan?
    rounding = 0x7FFF_u32 + ((bits >> 16) & 1_u32)
    ((bits &+ rounding) >> 16).to_u16
  end

  def self.f16_to_f32(h : UInt16) : Float32
    sign = (h.to_u32 & 0x8000_u32) << 16
    exp = (h.to_u32 >> 10) & 0x1F_u32
    mant = h.to_u32 & 0x3FF_u32
    bits = if exp == 0
             if mant == 0
               sign
             else
               # subnormal: normalise
               e = -1
               m = mant
               while (m & 0x400_u32) == 0
                 m <<= 1
                 e += 1
               end
               sign | ((127 - 15 - e).to_u32 << 23) | ((m & 0x3FF_u32) << 13)
             end
           elsif exp == 0x1F_u32
             sign | 0x7F800000_u32 | (mant << 13)
           else
             sign | ((exp + 112_u32) << 23) | (mant << 13)
           end
    bits.unsafe_as(Float32)
  end
end
