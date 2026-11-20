# JPEG decoding in pure Crystal.
#
# Handles Huffman-coded files of three kinds:
#
# - DCT, sequential (SOF0, SOF1), 8 or 12 bits per sample;
# - DCT, progressive (SOF2), 8 bits per sample;
# - lossless (SOF3), 2 to 16 bits per sample, with any of the seven
#   predictors and a point transform.
#
# Each may be grayscale or have three components with any sampling
# factors, interleaved or one component per scan, with or without restart
# markers, or four components (CMYK or YCCK, as print workflows write
# them), which are converted to RGB without a colour profile. Samples of
# more than 8 bits are scaled to 8. Arithmetic-coded, hierarchical and
# 12-bit progressive files are refused with an `ImageError`.
#
# A lossless file codes each sample as its difference from a prediction
# made from the samples to its left, above, and above left.
#
# A progressive file sends each block's coefficients over several scans:
# first by frequency band (spectral selection), and within a band first
# the high bits and then one more bit per scan (successive approximation).
# The coefficients are collected and turned into pixels at the end.

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

      # `count` bits as a plain number.
      def unsigned(count : Int32) : Int32
        value = 0
        count.times { value = (value << 1) | bit }
        value
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
      # Bits per sample.
      property precision = 8
      # Lossless files only: the samples as coded, before the point
      # transform, at full precision; and the point transform.
      property samples = Slice(UInt16).empty
      property point_transform = 0
      # Progressive files only: every block's 64 coefficients, in natural
      # (row by row) order, before dequantization.
      property coefficients = Slice(Int16).empty

      def blocks_wide : Int32
        plane_width // 8
      end

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
      adobe = false
      scans = 0
      progressive = false
      lossless = false
      precision = 8

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
        when 0xC0, 0xC1, 0xC2, 0xC3
          progressive = marker == 0xC2
          lossless = marker == 0xC3
          raise ImageError.new("JPEG has more than one frame") unless components.empty?
          raise ImageError.new("truncated JPEG frame header") if segment.size < 6
          precision = segment[0].to_i
          if lossless
            unless (2..16).includes?(precision)
              raise ImageError.new("lossless JPEG with #{precision} bits per sample is not valid (2 to 16)")
            end
          elsif progressive && precision == 12
            raise ImageError.new("12-bit progressive JPEG is not supported")
          elsif precision != 8 && precision != 12
            raise ImageError.new("JPEG with #{precision} bits per sample is not supported (8 or 12, or 2 to 16 when lossless)")
          end
          height = (segment[1].to_i << 8) | segment[2].to_i
          width = (segment[3].to_i << 8) | segment[4].to_i
          count = segment[5].to_i
          raise ImageError.new("JPEG size #{width}x#{height} is not valid") unless width > 0 && height > 0
          raise ImageError.new("JPEG is too large") if width.to_i64 * height > MAX_PIXELS
          unless count == 1 || count == 3 || count == 4
            raise ImageError.new("JPEG with #{count} components is not supported (one, three or four only)")
          end
          raise ImageError.new("truncated JPEG frame header") if segment.size < 6 + count * 3
          count.times do |i|
            factors = segment[7 + i * 3].to_i
            component = Component.new(segment[6 + i * 3].to_i, factors >> 4, factors & 15, segment[8 + i * 3].to_i)
            unless (1..4).includes?(component.horizontal) && (1..4).includes?(component.vertical)
              raise ImageError.new("JPEG sampling factor out of range")
            end
            component.precision = precision
            components << component
          end
        when 0xC5, 0xC6, 0xC7, 0xCD, 0xCE, 0xCF
          raise ImageError.new("hierarchical JPEG is not supported")
        when 0xC9, 0xCA, 0xCB
          raise ImageError.new("arithmetic-coded JPEG is not supported")
        when 0xDD
          raise ImageError.new("truncated JPEG restart interval") if segment.size < 2
          restart_interval = (segment[0].to_i << 8) | segment[1].to_i
        when 0xEE
          # Adobe: the last byte says whether three components are YCbCr.
          if segment.size >= 12 && String.new(segment[0, 5]) == "Adobe"
            adobe = true
            adobe_transform = segment[11].to_i
          end
        when 0xDA
          raise ImageError.new("JPEG scan comes before its frame header") if components.empty?
          if scans == 0
            prepare_planes(components, width, height, lossless)
            if progressive
              components.each do |component|
                component.coefficients = Slice(Int16).new(component.plane_width * component.plane_height)
              end
            end
          end
          position = if lossless
                       decode_lossless_scan(bytes, position, segment, components, dc_tables,
                         restart_interval, width, height)
                     elsif progressive
                       decode_progressive_scan(bytes, position, segment, components, dc_tables, ac_tables,
                         restart_interval, width, height)
                     else
                       decode_scan(bytes, position, segment, components, quantization, dc_tables, ac_tables,
                         restart_interval, width, height)
                     end
          scans += 1
        end
      end

      raise ImageError.new("JPEG has no image data") if scans == 0
      reconstruct(components, quantization) if progressive
      settle_samples(components) if lossless
      assemble(components, width, height, adobe_transform, adobe)
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

    # A DCT file's planes are whole blocks of 8 by 8; a lossless file's
    # are whole MCUs, each a sample of every component at its sampling.
    private def self.prepare_planes(components : Array(Component), width : Int32, height : Int32,
                                    lossless : Bool = false) : Nil
      h_max = components.max_of(&.horizontal)
      v_max = components.max_of(&.vertical)
      block = lossless ? 1 : 8
      mcus_wide = (width + block * h_max - 1) // (block * h_max)
      mcus_high = (height + block * v_max - 1) // (block * v_max)
      components.each do |component|
        component.plane_width = mcus_wide * component.horizontal * block
        component.plane_height = mcus_high * component.vertical * block
        component.plane = Bytes.new(component.plane_width * component.plane_height)
        component.samples = Slice(UInt16).new(component.plane_width * component.plane_height) if lossless
      end
    end

    # One scan of a lossless file. Returns the position after it.
    #
    # The scan header's spectral start is the predictor and its low bit
    # position the point transform. Each sample is coded as its difference
    # from a prediction, its size by the component's DC table:
    #
    #   1: left   2: above   3: above left   4: left + above - above left
    #   5: left + (above - above left) / 2   6: above + (left - above left) / 2
    #   7: (left + above) / 2
    #
    # The first sample, and the first after each restart, is predicted as
    # half the sample range; the rest of that line from the left, and the
    # first sample of each later line from above.
    private def self.decode_lossless_scan(bytes : Bytes, position : Int32, header : Bytes, components : Array(Component),
                                          dc_tables : Hash(Int32, HuffmanTable), restart_interval : Int32,
                                          width : Int32, height : Int32) : Int32
      raise ImageError.new("truncated JPEG scan header") if header.size < 1
      count = header[0].to_i
      raise ImageError.new("truncated JPEG scan header") if header.size < 1 + count * 2 + 3
      scan = Array(Component).new(count) do |i|
        id = header[1 + i * 2].to_i
        component = components.find { |candidate| candidate.id == id } ||
                    raise ImageError.new("JPEG scan names component #{id}, which the frame does not have")
        component.dc_table = header[2 + i * 2].to_i >> 4
        component
      end
      raise ImageError.new("JPEG scan has no components") if scan.empty?
      predictor = header[1 + count * 2].to_i
      raise ImageError.new("lossless JPEG predictor #{predictor} is not valid (1 to 7)") unless (1..7).includes?(predictor)
      point_transform = header[3 + count * 2].to_i & 15
      tables = scan.map do |component|
        dc_tables[component.dc_table]? || raise ImageError.new("JPEG scan uses a DC table that was not defined")
      end
      scan.each do |component|
        component.point_transform = point_transform
        if point_transform >= component.precision
          raise ImageError.new("lossless JPEG point transform #{point_transform} is too large")
        end
      end

      h_max = components.max_of(&.horizontal)
      v_max = components.max_of(&.vertical)
      reader = BitReader.new(bytes, position)
      # Per component: whether the next sample starts afresh, and the line
      # that counts as the first.
      fresh = Array(Bool).new(scan.size, true)
      first_line = Array(Int32).new(scan.size, 0)

      if scan.size == 1
        component = scan.first
        units_wide = (width * component.horizontal + h_max - 1) // h_max
        units_high = (height * component.vertical + v_max - 1) // v_max
      else
        units_wide = (width + h_max - 1) // h_max
        units_high = (height + v_max - 1) // v_max
      end

      unit = 0
      units_high.times do |unit_y|
        units_wide.times do |unit_x|
          restarting = restart_interval > 0 && unit > 0 && unit % restart_interval == 0
          reader.restart if restarting
          unit += 1

          scan.each_with_index do |component, i|
            across = scan.size == 1 ? 1 : component.horizontal
            down = scan.size == 1 ? 1 : component.vertical
            if restarting
              fresh[i] = true
              first_line[i] = unit_y * down
            end
            down.times do |dy|
              across.times do |dx|
                y = unit_y * down + dy
                x = unit_x * across + dx
                prediction = lossless_prediction(component, predictor, x, y, fresh[i], y == first_line[i])
                fresh[i] = false
                size = tables[i].decode(reader)
                raise ImageError.new("lossless JPEG difference is too large") if size > 16
                difference = size == 16 ? 32768 : reader.signed(size)
                component.samples[y * component.plane_width + x] = ((prediction + difference) & 0xFFFF).to_u16
              end
            end
          end
        end
      end
      reader.position
    end

    private def self.lossless_prediction(component : Component, predictor : Int32, x : Int32, y : Int32,
                                         fresh : Bool, first_line : Bool) : Int32
      return 1 << (component.precision - component.point_transform - 1) if fresh
      samples = component.samples
      row = y * component.plane_width
      return samples[row + x - 1].to_i if first_line
      above = samples[row - component.plane_width + x].to_i
      return above if x == 0
      left = samples[row + x - 1].to_i
      corner = samples[row - component.plane_width + x - 1].to_i
      case predictor
      when 1 then left
      when 2 then above
      when 3 then corner
      when 4 then left + above - corner
      when 5 then left + ((above - corner) >> 1)
      when 6 then above + ((left - corner) >> 1)
      else        (left + above) >> 1
      end
    end

    # Lossless files: undo the point transform and bring the samples to
    # 8 bits.
    private def self.settle_samples(components : Array(Component)) : Nil
      components.each do |component|
        top = (1 << component.precision) - 1
        plane = component.plane
        component.samples.each_with_index do |sample, i|
          value = Math.min(sample.to_i << component.point_transform, top)
          plane[i] = component.precision == 8 ? value.to_u8 : ((value * 255 + top // 2) // top).to_u8
        end
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
      raise ImageError.new("JPEG DC coefficient is too large") if size > component.precision + 3
      component.predictor &+= reader.signed(size)
      block[0] = component.predictor &* table[0]

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

    # One scan of a progressive file: the bits `low` and above (or just bit
    # `low`, when `high` says the higher ones came earlier) of coefficients
    # `first..last` for the scan's components. Returns the position after it.
    private def self.decode_progressive_scan(bytes : Bytes, position : Int32, header : Bytes,
                                             components : Array(Component), dc_tables : Hash(Int32, HuffmanTable),
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

      first = header[1 + count * 2].to_i
      last = header[2 + count * 2].to_i
      high = header[3 + count * 2].to_i >> 4
      low = header[3 + count * 2].to_i & 15
      unless first <= last && last <= 63 && low <= 13 && (first == 0) == (last == 0)
        raise ImageError.new("JPEG progressive scan has an invalid coefficient range")
      end
      raise ImageError.new("JPEG progressive AC scan must have one component") if first > 0 && scan.size > 1

      h_max = components.max_of(&.horizontal)
      v_max = components.max_of(&.vertical)
      if scan.size == 1
        component = scan.first
        units_wide = (width * component.horizontal + 8 * h_max - 1) // (8 * h_max)
        units_high = (height * component.vertical + 8 * v_max - 1) // (8 * v_max)
      else
        units_wide = (width + 8 * h_max - 1) // (8 * h_max)
        units_high = (height + 8 * v_max - 1) // (8 * v_max)
      end

      reader = BitReader.new(bytes, position)
      # Blocks still to come whose band is entirely zero in this scan.
      end_of_band_run = 0
      unit = 0
      units_high.times do |unit_y|
        units_wide.times do |unit_x|
          if restart_interval > 0 && unit > 0 && unit % restart_interval == 0
            reader.restart
            scan.each { |component| component.predictor = 0 }
            end_of_band_run = 0
          end
          unit += 1

          scan.each do |component|
            across = scan.size == 1 ? 1 : component.horizontal
            down = scan.size == 1 ? 1 : component.vertical
            down.times do |block_y|
              across.times do |block_x|
                index = ((unit_y * down + block_y) * component.blocks_wide + unit_x * across + block_x) * 64
                next if index + 64 > component.coefficients.size
                block = component.coefficients.to_unsafe + index
                if first == 0
                  if high == 0
                    table = dc_tables[component.dc_table]? || raise ImageError.new("JPEG scan uses a DC table that was not defined")
                    size = table.decode(reader)
                    raise ImageError.new("JPEG DC coefficient is too large") if size > 11
                    component.predictor &+= reader.signed(size)
                    block[0] = coefficient(component.predictor << low)
                  elsif reader.bit == 1
                    block[0] = coefficient(block[0].to_i | (1 << low))
                  end
                else
                  table = ac_tables[component.ac_table]? || raise ImageError.new("JPEG scan uses an AC table that was not defined")
                  end_of_band_run = if high == 0
                                      first_ac_pass(reader, table, block, first, last, low, end_of_band_run)
                                    else
                                      refine_ac_pass(reader, table, block, first, last, low, end_of_band_run)
                                    end
                end
              end
            end
          end
        end
      end
      reader.position
    end

    private def self.coefficient(value : Int32) : Int16
      value.clamp(Int16::MIN.to_i, Int16::MAX.to_i).to_i16
    end

    # The first bits of an AC band: runs of zeros and new nonzero values.
    # Returns the end-of-band run left for the blocks that follow.
    private def self.first_ac_pass(reader : BitReader, table : HuffmanTable, block : Pointer(Int16),
                                   first : Int32, last : Int32, low : Int32, run : Int32) : Int32
      return run - 1 if run > 0

      index = first
      while index <= last
        symbol = table.decode(reader)
        zeros = symbol >> 4
        size = symbol & 15
        if size == 0
          if zeros < 15
            # This block's band ends here, and so do the next few blocks'.
            run = (1 << zeros) - 1
            run += reader.unsigned(zeros) if zeros > 0
            break
          end
          index += 16
          next
        end
        index += zeros
        raise ImageError.new("JPEG block has more than 64 coefficients") if index > last
        block[ZIGZAG[index]] = coefficient(reader.signed(size) << low)
        index += 1
      end
      run
    end

    # One more bit for an AC band. Coefficients that are already nonzero get
    # a correction bit as they are passed; a zero one may become +-1 at
    # this bit position.
    private def self.refine_ac_pass(reader : BitReader, table : HuffmanTable, block : Pointer(Int16),
                                    first : Int32, last : Int32, low : Int32, run : Int32) : Int32
      plus = 1 << low
      minus = -1 << low
      index = first

      if run == 0
        while index <= last
          symbol = table.decode(reader)
          zeros = symbol >> 4
          size = symbol & 15
          value = 0
          if size != 0
            raise ImageError.new("JPEG refinement scan has a coefficient larger than one bit") unless size == 1
            value = reader.bit == 1 ? plus : minus
          elsif zeros != 15
            run = 1 << zeros
            run += reader.unsigned(zeros) if zeros > 0
            break
          end

          # Pass `zeros` coefficients that are still zero, correcting the
          # nonzero ones on the way, and stop at the next zero one.
          while index <= last
            position = ZIGZAG[index]
            if block[position] != 0
              refine(reader, block + position, plus, minus)
            else
              zeros -= 1
              break if zeros < 0
            end
            index += 1
          end

          block[ZIGZAG[index]] = coefficient(value) if value != 0 && index <= last
          index += 1
        end
      end

      if run > 0
        # The rest of this band holds no new values, only corrections.
        while index <= last
          position = ZIGZAG[index]
          refine(reader, block + position, plus, minus) if block[position] != 0
          index += 1
        end
        run -= 1
      end
      run
    end

    private def self.refine(reader : BitReader, target : Pointer(Int16), plus : Int32, minus : Int32) : Nil
      return unless reader.bit == 1
      current = target.value.to_i
      return unless current & plus == 0
      target.value = coefficient(current >= 0 ? current + plus : current + minus)
    end

    # Progressive files: dequantize every block and turn it into samples.
    private def self.reconstruct(components : Array(Component), quantization : Hash(Int32, Array(Int32))) : Nil
      coefficients = StaticArray(Int32, 64).new(0)
      workspace = StaticArray(Float64, 64).new(0.0)
      components.each do |component|
        table = quantization[component.quantization]? ||
                raise ImageError.new("JPEG component uses a quantization table that was not defined")
        # The table is stored in zigzag order; the coefficients are not.
        natural = StaticArray(Int32, 64).new(0)
        64.times { |i| natural[ZIGZAG[i]] = table[i] }

        blocks_high = component.plane_height // 8
        blocks_high.times do |block_y|
          component.blocks_wide.times do |block_x|
            source = component.coefficients.to_unsafe + (block_y * component.blocks_wide + block_x) * 64
            64.times { |i| coefficients[i] = source[i].to_i * natural[i] }
            inverse_dct(pointerof(coefficients), pointerof(workspace), component, block_x * 8, block_y * 8)
          end
        end
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
      # Samples are centred on zero; 12-bit ones are brought to 8 bits.
      top = (1 << component.precision) - 1
      center = (1 << (component.precision - 1)).to_f
      8.times do |py|
        8.times do |px|
          sum = 0.0
          8.times { |v| sum += basis[py * 8 + v] * rows[v * 8 + px] }
          value = (sum + center).round.clamp(0.0, top.to_f).to_i
          plane[(y + py) * component.plane_width + x + px] = (component.precision == 8 ? value : (value * 255 + top // 2) // top).to_u8
        end
      end
    end

    # Bring every component to full resolution and convert to gray or RGB.
    private def self.assemble(components : Array(Component), width : Int32, height : Int32,
                              adobe_transform : Int32?, adobe : Bool) : Image
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
      # Four components are cyan, magenta, yellow and black. Adobe's
      # transform 2 stores the first three as YCbCr (YCCK), and files with
      # Adobe's marker store ink inverted: 255 is no ink.
      four = components.size == 4
      ycck = four && adobe_transform == 2
      image = Image.new(width, height, 3)
      sample = StaticArray(Int32, 4).new(0)
      height.times do |y|
        width.times do |x|
          components.each_with_index do |component, i|
            source_x = x * component.horizontal // h_max
            source_y = y * component.vertical // v_max
            sample[i] = component.plane[source_y * component.plane_width + source_x].to_i
          end
          target = (y * width + x) * 3
          if four
            if ycck
              luma = sample[0].to_f
              blue = sample[1] - 128.0
              red = sample[2] - 128.0
              # The three decode as for a colour picture, and the ink value
              # is that turned over.
              sample[0] = 255 - (luma + 1.402 * red).round.clamp(0.0, 255.0).to_i
              sample[1] = 255 - (luma - 0.344136 * blue - 0.714136 * red).round.clamp(0.0, 255.0).to_i
              sample[2] = 255 - (luma + 1.772 * blue).round.clamp(0.0, 255.0).to_i
            end
            # As light let through: each ink's share times black's.
            black = adobe ? sample[3] : 255 - sample[3]
            3.times do |i|
              light = adobe ? sample[i] : 255 - sample[i]
              image.data[target + i] = ((light * black + 127) // 255).to_u8
            end
          elsif stored_rgb
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
