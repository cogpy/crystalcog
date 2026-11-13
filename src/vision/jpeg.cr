# Baseline JPEG decoding in pure Crystal.
#
# Handles what cameras and most tools write by default: 8-bit Huffman-coded
# sequential DCT (SOF0 and SOF1), grayscale or three components with any
# sampling factors, interleaved or one component per scan, with or without
# restart markers. Progressive, lossless, arithmetic-coded, 12-bit and
# four-component (CMYK) files are refused with an `ImageError`.

require "./image"

module Vision
  module JPEG
    # Largest image accepted, in pixels.
    MAX_PIXELS = 100_000_000_i64

    # Order in which a block's 64 coefficients are stored.
    ZIGZAG = [
      0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
      12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
      35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
      58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
    ]

    # IDCT_BASIS[x * 8 + u] = C(u)/2 * cos((2x + 1) * u * pi / 16)
    IDCT_BASIS = begin
      table = Array(Float64).new(64, 0.0)
      8.times do |x|
        8.times do |u|
          scale = u == 0 ? Math.sqrt(0.125) : 0.5
          table[x * 8 + u] = scale * Math.cos((2 * x + 1) * u * Math::PI / 16)
        end
      end
      table
    end

    # A Huffman table in the canonical form JPEG stores: codes of each
    # length are consecutive, shorter codes first.
    class HuffmanTable
      @min_code = StaticArray(Int32, 17).new(0)
      @max_code = StaticArray(Int32, 17).new(-1)
      @first_symbol = StaticArray(Int32, 17).new(0)

      def initialize(counts : Bytes, @symbols : Bytes)
        code = 0
        index = 0
        (1..16).each do |length|
          count = counts[length - 1].to_i
          if count > 0
            @first_symbol[length] = index
            @min_code[length] = code
            code += count
            index += count
            @max_code[length] = code - 1
          end
          code <<= 1
        end
        raise ImageError.new("JPEG Huffman table lists more symbols than it stores") if index > @symbols.size
      end

      def decode(reader : BitReader) : Int32
        code = 0
        (1..16).each do |length|
          code = (code << 1) | reader.bit
          if code <= @max_code[length] && @max_code[length] >= 0
            return @symbols[@first_symbol[length] + code - @min_code[length]].to_i
          end
        end
        raise ImageError.new("JPEG data has a code that is in no Huffman table")
      end
    end

    # Reads entropy-coded bits, removing the zero byte stuffed after 0xFF
    # and stopping at a marker.
    class BitReader
      getter position : Int32

      def initialize(@bytes : Bytes, @position : Int32)
        @buffer = 0
        @available = 0
      end

      def bit : Int32
        if @available == 0
          raise ImageError.new("JPEG data ends inside a scan") if @position >= @bytes.size
          byte = @bytes[@position].to_i
          if byte == 0xFF
            following = @position + 1 < @bytes.size ? @bytes[@position + 1].to_i : 0xD9
            if following == 0
              @position += 2
            else
              # A marker: the scan is over. Decoders pad with zero bits.
              byte = 0
            end
          else
            @position += 1
          end
          @buffer = byte
          @available = 8
        end
        @available -= 1
        (@buffer >> @available) & 1
      end

      # `count` bits as the signed value JPEG encodes with them.
      def signed(count : Int32) : Int32
        return 0 if count == 0
        value = 0
        count.times { value = (value << 1) | bit }
        value < (1 << (count - 1)) ? value - (1 << count) + 1 : value
      end

      # Drop the bits left in the current byte and step over a restart marker.
      def restart : Nil
        @available = 0
        if @position + 1 < @bytes.size && @bytes[@position] == 0xFF && (0xD0..0xD7).includes?(@bytes[@position + 1])
          @position += 2
        end
      end
    end

    class Component
      getter id : Int32
      getter horizontal : Int32
      getter vertical : Int32
      getter quantization : Int32
      property dc_table = 0
      property ac_table = 0
      property predictor = 0
      # Decoded samples, in whole blocks.
      property plane = Bytes.empty
      property plane_width = 0
      property plane_height = 0

      def initialize(@id, @horizontal, @vertical, @quantization)
      end
    end

    def self.decode(bytes : Bytes) : Image
      unless bytes.size >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8
        raise ImageError.new("not a JPEG file")
      end

      quantization = Hash(Int32, Array(Int32)).new
      dc_tables = Hash(Int32, HuffmanTable).new
      ac_tables = Hash(Int32, HuffmanTable).new
      components = [] of Component
      width = height = 0
      restart_interval = 0
      adobe_transform : Int32? = nil
      scans = 0

      position = 2
      loop do
        # Find the next marker; any number of 0xFF fill bytes may precede it.
        while position < bytes.size && bytes[position] != 0xFF
          position += 1
        end
        while position < bytes.size && bytes[position] == 0xFF
          position += 1
        end
        raise ImageError.new("JPEG ends without an end-of-image marker") if position >= bytes.size
        marker = bytes[position].to_i
        position += 1

        case marker
        when 0xD9                   then break # end of image
        when 0x00, 0x01, 0xD0..0xD8 then next  # stuffing, TEM, stray restart or SOI
        end

        raise ImageError.new("truncated JPEG segment") if position + 2 > bytes.size
        length = (bytes[position].to_i << 8) | bytes[position + 1].to_i
        raise ImageError.new("truncated JPEG segment") if length < 2 || position + length > bytes.size
        segment = bytes[position + 2, length - 2]
        position += length

        case marker
        when 0xDB then read_quantization(segment, quantization)
        when 0xC4 then read_huffman(segment, dc_tables, ac_tables)
        when 0xC0, 0xC1
          raise ImageError.new("JPEG has more than one frame") unless components.empty?
          raise ImageError.new("truncated JPEG frame header") if segment.size < 6
          raise ImageError.new("only 8-bit JPEG is supported (this one has #{segment[0]} bits)") unless segment[0] == 8
          height = (segment[1].to_i << 8) | segment[2].to_i
          width = (segment[3].to_i << 8) | segment[4].to_i
          count = segment[5].to_i
          raise ImageError.new("JPEG size #{width}x#{height} is not valid") unless width > 0 && height > 0
          raise ImageError.new("JPEG is too large") if width.to_i64 * height > MAX_PIXELS
          unless count == 1 || count == 3
            raise ImageError.new("JPEG with #{count} components is not supported (grayscale and three-component only)")
          end
          raise ImageError.new("truncated JPEG frame header") if segment.size < 6 + count * 3
          count.times do |i|
            factors = segment[7 + i * 3].to_i
            component = Component.new(segment[6 + i * 3].to_i, factors >> 4, factors & 15, segment[8 + i * 3].to_i)
            unless (1..4).includes?(component.horizontal) && (1..4).includes?(component.vertical)
              raise ImageError.new("JPEG sampling factor out of range")
            end
            components << component
          end
        when 0xC2
          raise ImageError.new("progressive JPEG is not supported (baseline only)")
        when 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF
          raise ImageError.new("this kind of JPEG (lossless, hierarchical or arithmetic-coded) is not supported")
        when 0xDD
          raise ImageError.new("truncated JPEG restart interval") if segment.size < 2
          restart_interval = (segment[0].to_i << 8) | segment[1].to_i
        when 0xEE
          # Adobe: the last byte says whether three components are YCbCr.
          if segment.size >= 12 && String.new(segment[0, 5]) == "Adobe"
            adobe_transform = segment[11].to_i
          end
        when 0xDA
          raise ImageError.new("JPEG scan comes before its frame header") if components.empty?
          prepare_planes(components, width, height) if scans == 0
          position = decode_scan(bytes, position, segment, components, quantization, dc_tables, ac_tables,
            restart_interval, width, height)
          scans += 1
        end
      end

      raise ImageError.new("JPEG has no image data") if scans == 0
      assemble(components, width, height, adobe_transform)
    end

    private def self.read_quantization(segment : Bytes, tables : Hash(Int32, Array(Int32))) : Nil
      position = 0
      while position < segment.size
        precision = segment[position] >> 4
        id = (segment[position] & 15).to_i
        position += 1
        size = precision == 0 ? 64 : 128
        raise ImageError.new("truncated JPEG quantization table") if position + size > segment.size
        table = Array(Int32).new(64, 0)
        64.times do |i|
          table[i] = if precision == 0
                       segment[position + i].to_i
                     else
                       (segment[position + i * 2].to_i << 8) | segment[position + i * 2 + 1].to_i
                     end
        end
        tables[id] = table
        position += size
      end
    end

    private def self.read_huffman(segment : Bytes, dc_tables : Hash(Int32, HuffmanTable),
                                  ac_tables : Hash(Int32, HuffmanTable)) : Nil
      position = 0
      while position < segment.size
        raise ImageError.new("truncated JPEG Huffman table") if position + 17 > segment.size
        table_class = segment[position] >> 4
        id = (segment[position] & 15).to_i
        counts = segment[position + 1, 16]
        total = counts.sum(&.to_i)
        raise ImageError.new("truncated JPEG Huffman table") if position + 17 + total > segment.size
        table = HuffmanTable.new(counts, segment[position + 17, total])
        (table_class == 0 ? dc_tables : ac_tables)[id] = table
        position += 17 + total
      end
    end

    private def self.prepare_planes(components : Array(Component), width : Int32, height : Int32) : Nil
      h_max = components.max_of(&.horizontal)
      v_max = components.max_of(&.vertical)
      mcus_wide = (width + 8 * h_max - 1) // (8 * h_max)
      mcus_high = (height + 8 * v_max - 1) // (8 * v_max)
      components.each do |component|
        component.plane_width = mcus_wide * component.horizontal * 8
        component.plane_height = mcus_high * component.vertical * 8
        component.plane = Bytes.new(component.plane_width * component.plane_height)
      end
    end

    # Decode one scan and return the position just after its data.
    private def self.decode_scan(bytes : Bytes, position : Int32, header : Bytes, components : Array(Component),
                                 quantization : Hash(Int32, Array(Int32)), dc_tables : Hash(Int32, HuffmanTable),
                                 ac_tables : Hash(Int32, HuffmanTable), restart_interval : Int32,
                                 width : Int32, height : Int32) : Int32
      raise ImageError.new("truncated JPEG scan header") if header.size < 1
      count = header[0].to_i
      raise ImageError.new("truncated JPEG scan header") if header.size < 1 + count * 2 + 3
      scan = Array(Component).new(count) do |i|
        id = header[1 + i * 2].to_i
        component = components.find { |candidate| candidate.id == id } ||
                    raise ImageError.new("JPEG scan names component #{id}, which the frame does not have")
        tables = header[2 + i * 2].to_i
        component.dc_table = tables >> 4
        component.ac_table = tables & 15
        component.predictor = 0
        component
      end
      raise ImageError.new("JPEG scan has no components") if scan.empty?

      h_max = components.max_of(&.horizontal)
      v_max = components.max_of(&.vertical)
      reader = BitReader.new(bytes, position)
      coefficients = StaticArray(Int32, 64).new(0)
      workspace = StaticArray(Float64, 64).new(0.0)

      # Each unit of an interleaved scan holds every component's blocks for
      # one 8*h_max by 8*v_max area. A scan of one component is just its
      # blocks in row order, covering the image and no more.
      if scan.size == 1
        component = scan.first
        units_wide = (width * component.horizontal + 8 * h_max - 1) // (8 * h_max)
        units_high = (height * component.vertical + 8 * v_max - 1) // (8 * v_max)
      else
        units_wide = (width + 8 * h_max - 1) // (8 * h_max)
        units_high = (height + 8 * v_max - 1) // (8 * v_max)
      end

      unit = 0
      units_high.times do |unit_y|
        units_wide.times do |unit_x|
          if restart_interval > 0 && unit > 0 && unit % restart_interval == 0
            reader.restart
            scan.each { |component| component.predictor = 0 }
          end
          unit += 1

          scan.each do |component|
            dc = dc_tables[component.dc_table]? || raise ImageError.new("JPEG scan uses a DC table that was not defined")
            ac = ac_tables[component.ac_table]? || raise ImageError.new("JPEG scan uses an AC table that was not defined")
            table = quantization[component.quantization]? ||
                    raise ImageError.new("JPEG component uses a quantization table that was not defined")
            across = scan.size == 1 ? 1 : component.horizontal
            down = scan.size == 1 ? 1 : component.vertical
            down.times do |block_y|
              across.times do |block_x|
                decode_block(reader, component, dc, ac, table, pointerof(coefficients))
                inverse_dct(pointerof(coefficients), pointerof(workspace), component,
                  (unit_x * across + block_x) * 8, (unit_y * down + block_y) * 8)
              end
            end
          end
        end
      end
      reader.position
    end

    private def self.decode_block(reader : BitReader, component : Component, dc : HuffmanTable, ac : HuffmanTable,
                                  table : Array(Int32), coefficients : Pointer(StaticArray(Int32, 64))) : Nil
      block = coefficients.value.to_unsafe
      64.times { |i| block[i] = 0 }

      size = dc.decode(reader)
      raise ImageError.new("JPEG DC coefficient is too large") if size > 11
      component.predictor += reader.signed(size)
      block[0] = component.predictor * table[0]

      index = 1
      while index < 64
        symbol = ac.decode(reader)
        run = symbol >> 4
        size = symbol & 15
        if size == 0
          break unless run == 15 # end of block
          index += 16            # sixteen zeros
          next
        end
        index += run
        raise ImageError.new("JPEG block has more than 64 coefficients") if index > 63
        block[ZIGZAG[index]] = reader.signed(size) * table[index]
        index += 1
      end
    end

    # Rows, then columns, then store the block at (x, y) of the plane.
    private def self.inverse_dct(coefficients : Pointer(StaticArray(Int32, 64)), workspace : Pointer(StaticArray(Float64, 64)),
                                 component : Component, x : Int32, y : Int32) : Nil
      block = coefficients.value.to_unsafe
      rows = workspace.value.to_unsafe
      basis = IDCT_BASIS.to_unsafe

      8.times do |v|
        8.times do |px|
          sum = 0.0
          8.times { |u| sum += basis[px * 8 + u] * block[v * 8 + u] }
          rows[v * 8 + px] = sum
        end
      end

      return if y + 8 > component.plane_height || x + 8 > component.plane_width
      plane = component.plane.to_unsafe
      8.times do |py|
        8.times do |px|
          sum = 0.0
          8.times { |v| sum += basis[py * 8 + v] * rows[v * 8 + px] }
          plane[(y + py) * component.plane_width + x + px] = (sum + 128.0).round.clamp(0.0, 255.0).to_u8
        end
      end
    end

    # Bring every component to full resolution and convert to gray or RGB.
    private def self.assemble(components : Array(Component), width : Int32, height : Int32,
                              adobe_transform : Int32?) : Image
      if components.size == 1
        component = components.first
        image = Image.new(width, height, 1)
        height.times do |y|
          image.data[y * width, width].copy_from(component.plane[y * component.plane_width, width])
        end
        return image
      end

      h_max = components.max_of(&.horizontal)
      v_max = components.max_of(&.vertical)
      # Three components are YCbCr unless Adobe's marker or the component
      # names say they are stored as RGB.
      stored_rgb = adobe_transform == 0 || components.map(&.id) == [82, 71, 66]
      image = Image.new(width, height, 3)
      sample = StaticArray(Int32, 3).new(0)
      height.times do |y|
        width.times do |x|
          components.each_with_index do |component, i|
            source_x = x * component.horizontal // h_max
            source_y = y * component.vertical // v_max
            sample[i] = component.plane[source_y * component.plane_width + source_x].to_i
          end
          target = (y * width + x) * 3
          if stored_rgb
            3.times { |i| image.data[target + i] = sample[i].to_u8 }
          else
            luma = sample[0].to_f
            blue = sample[1] - 128.0
            red = sample[2] - 128.0
            image.data[target] = (luma + 1.402 * red).round.clamp(0.0, 255.0).to_u8
            image.data[target + 1] = (luma - 0.344136 * blue - 0.714136 * red).round.clamp(0.0, 255.0).to_u8
            image.data[target + 2] = (luma + 1.772 * blue).round.clamp(0.0, 255.0).to_u8
          end
        end
      end
      image
    end
  end
end
