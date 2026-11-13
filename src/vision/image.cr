# Images for the vision module: 8-bit grayscale or RGB pixel grids, read
# from and written to PNG and PPM/PGM with no external libraries, plus the
# filters perception is built from.

require "compress/zlib"
require "digest/crc32"

module Vision
  class ImageError < Exception
  end

  class Image
    getter width : Int32
    getter height : Int32
    # 1 (grayscale) or 3 (RGB).
    getter channels : Int32
    # Row-major, `channels` bytes per pixel.
    getter data : Bytes

    def initialize(@width : Int32, @height : Int32, @channels : Int32 = 3, data : Bytes? = nil)
      raise ImageError.new("image size must be positive, got #{@width}x#{@height}") unless @width > 0 && @height > 0
      raise ImageError.new("channels must be 1 or 3, got #{@channels}") unless @channels == 1 || @channels == 3
      expected = @width.to_i64 * @height * @channels
      raise ImageError.new("image too large") if expected > Int32::MAX
      @data = data || Bytes.new(expected.to_i32)
      raise ImageError.new("expected #{expected} bytes of pixels, got #{@data.size}") unless @data.size == expected
    end

    # An image from raw sensor bytes in a ROS encoding: rgb8, bgr8, rgba8,
    # bgra8 or mono8. Rows may be padded to `step` bytes.
    def self.from_raw(width : Int32, height : Int32, bytes : Bytes, encoding : String = "rgb8", step : Int32? = nil) : Image
      source_channels = case encoding.downcase
                        when "mono8"          then 1
                        when "rgb8", "bgr8"   then 3
                        when "rgba8", "bgra8" then 4
                        else                       raise ImageError.new("unsupported encoding #{encoding.inspect}")
                        end
      row_bytes = step || width * source_channels
      needed = row_bytes.to_i64 * (height - 1) + width.to_i64 * source_channels
      raise ImageError.new("#{encoding} #{width}x#{height} needs #{needed} bytes, got #{bytes.size}") if bytes.size < needed

      image = Image.new(width, height, source_channels == 1 ? 1 : 3)
      swap = encoding.downcase.starts_with?("bgr")
      height.times do |y|
        width.times do |x|
          source = y * row_bytes + x * source_channels
          target = (y * width + x) * image.channels
          if source_channels == 1
            image.data[target] = bytes[source]
          else
            image.data[target] = bytes[source + (swap ? 2 : 0)]
            image.data[target + 1] = bytes[source + 1]
            image.data[target + 2] = bytes[source + (swap ? 0 : 2)]
          end
        end
      end
      image
    end

    def gray? : Bool
      @channels == 1
    end

    @[AlwaysInline]
    def offset(x : Int32, y : Int32) : Int32
      (y * @width + x) * @channels
    end

    # The pixel as {r, g, b}; a gray pixel repeats its value.
    def rgb(x : Int32, y : Int32) : {UInt8, UInt8, UInt8}
      i = offset(x, y)
      gray? ? {@data[i], @data[i], @data[i]} : {@data[i], @data[i + 1], @data[i + 2]}
    end

    def set_rgb(x : Int32, y : Int32, r : UInt8, g : UInt8, b : UInt8) : Nil
      i = offset(x, y)
      if gray?
        @data[i] = Image.luma(r, g, b)
      else
        @data[i] = r
        @data[i + 1] = g
        @data[i + 2] = b
      end
    end

    # Brightness of a pixel, 0-255.
    def gray_at(x : Int32, y : Int32) : UInt8
      i = offset(x, y)
      gray? ? @data[i] : Image.luma(@data[i], @data[i + 1], @data[i + 2])
    end

    # Rec. 601 luma.
    def self.luma(r : UInt8, g : UInt8, b : UInt8) : UInt8
      ((299 * r.to_i + 587 * g.to_i + 114 * b.to_i + 500) // 1000).to_u8
    end

    def in_bounds?(x : Int32, y : Int32) : Bool
      0 <= x < @width && 0 <= y < @height
    end

    def dup : Image
      Image.new(@width, @height, @channels, @data.dup)
    end

    def ==(other : Image) : Bool
      @width == other.width && @height == other.height && @channels == other.channels && @data == other.data
    end

    # ------------------------------------------------------------ drawing

    def fill(r : UInt8, g : UInt8, b : UInt8) : self
      @height.times { |y| @width.times { |x| set_rgb(x, y, r, g, b) } }
      self
    end

    def fill_rect(x0 : Int32, y0 : Int32, w : Int32, h : Int32, r : UInt8, g : UInt8, b : UInt8) : self
      (y0...y0 + h).each do |y|
        (x0...x0 + w).each { |x| set_rgb(x, y, r, g, b) if in_bounds?(x, y) }
      end
      self
    end

    def fill_circle(cx : Int32, cy : Int32, radius : Int32, r : UInt8, g : UInt8, b : UInt8) : self
      (cy - radius..cy + radius).each do |y|
        (cx - radius..cx + radius).each do |x|
          set_rgb(x, y, r, g, b) if in_bounds?(x, y) && (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2
        end
      end
      self
    end

    # A filled triangle with a horizontal base: apex at (cx, top), base
    # `base` wide at `top + height - 1`.
    def fill_triangle(cx : Int32, top : Int32, base : Int32, height : Int32, r : UInt8, g : UInt8, b : UInt8) : self
      height.times do |row|
        half = (base * (row + 1)) // (2 * height)
        (cx - half..cx + half).each { |x| set_rgb(x, top + row, r, g, b) if in_bounds?(x, top + row) }
      end
      self
    end

    # ------------------------------------------------------------ filters

    def to_gray : Image
      return dup if gray?
      result = Image.new(@width, @height, 1)
      (@width * @height).times do |p|
        result.data[p] = Image.luma(@data[p * 3], @data[p * 3 + 1], @data[p * 3 + 2])
      end
      result
    end

    def crop(x0 : Int32, y0 : Int32, w : Int32, h : Int32) : Image
      raise ImageError.new("crop #{w}x#{h} at #{x0},#{y0} leaves the #{@width}x#{@height} image") unless x0 >= 0 && y0 >= 0 && w > 0 && h > 0 && x0 + w <= @width && y0 + h <= @height
      result = Image.new(w, h, @channels)
      h.times do |y|
        source = offset(x0, y0 + y)
        result.data[y * w * @channels, w * @channels].copy_from(@data[source, w * @channels])
      end
      result
    end

    # Bilinear resampling.
    def resize(new_width : Int32, new_height : Int32) : Image
      result = Image.new(new_width, new_height, @channels)
      x_scale = @width.to_f / new_width
      y_scale = @height.to_f / new_height
      new_height.times do |y|
        sy = ((y + 0.5) * y_scale - 0.5).clamp(0.0, @height - 1.0)
        y0 = sy.to_i
        y1 = Math.min(y0 + 1, @height - 1)
        fy = sy - y0
        new_width.times do |x|
          sx = ((x + 0.5) * x_scale - 0.5).clamp(0.0, @width - 1.0)
          x0 = sx.to_i
          x1 = Math.min(x0 + 1, @width - 1)
          fx = sx - x0
          @channels.times do |c|
            top = @data[offset(x0, y0) + c] * (1 - fx) + @data[offset(x1, y0) + c] * fx
            bottom = @data[offset(x0, y1) + c] * (1 - fx) + @data[offset(x1, y1) + c] * fx
            result.data[result.offset(x, y) + c] = (top * (1 - fy) + bottom * fy).round.clamp(0.0, 255.0).to_u8
          end
        end
      end
      result
    end

    # Gaussian blur, applied as two one-dimensional passes. Edges repeat.
    def gaussian_blur(sigma : Float64 = 1.0) : Image
      return dup if sigma <= 0.0
      radius = (sigma * 3).ceil.to_i
      kernel = (-radius..radius).map { |i| Math.exp(-(i * i) / (2 * sigma * sigma)) }
      total = kernel.sum
      kernel.map! { |v| v / total }

      horizontal = Array(Float64).new(@data.size, 0.0)
      @height.times do |y|
        @width.times do |x|
          @channels.times do |c|
            sum = 0.0
            kernel.each_with_index { |weight, k| sum += weight * @data[offset((x + k - radius).clamp(0, @width - 1), y) + c] }
            horizontal[offset(x, y) + c] = sum
          end
        end
      end
      result = Image.new(@width, @height, @channels)
      @height.times do |y|
        @width.times do |x|
          @channels.times do |c|
            sum = 0.0
            kernel.each_with_index { |weight, k| sum += weight * horizontal[offset(x, (y + k - radius).clamp(0, @height - 1)) + c] }
            result.data[offset(x, y) + c] = sum.round.clamp(0.0, 255.0).to_u8
          end
        end
      end
      result
    end

    # Sobel gradients of brightness: magnitude and direction (radians) per pixel.
    def sobel : {Array(Float64), Array(Float64)}
      gray = to_gray
      magnitude = Array(Float64).new(@width * @height, 0.0)
      direction = Array(Float64).new(@width * @height, 0.0)
      @height.times do |y|
        @width.times do |x|
          at = ->(dx : Int32, dy : Int32) { gray.data[(y + dy).clamp(0, @height - 1) * @width + (x + dx).clamp(0, @width - 1)].to_i }
          gx = at.call(1, -1) + 2 * at.call(1, 0) + at.call(1, 1) - at.call(-1, -1) - 2 * at.call(-1, 0) - at.call(-1, 1)
          gy = at.call(-1, 1) + 2 * at.call(0, 1) + at.call(1, 1) - at.call(-1, -1) - 2 * at.call(0, -1) - at.call(1, -1)
          magnitude[y * @width + x] = Math.sqrt((gx * gx + gy * gy).to_f)
          direction[y * @width + x] = Math.atan2(gy.to_f, gx.to_f)
        end
      end
      {magnitude, direction}
    end

    # Edge map: white where the brightness gradient exceeds `threshold`.
    def edges(threshold : Float64 = 100.0) : Image
      magnitude, _ = sobel
      result = Image.new(@width, @height, 1)
      magnitude.each_with_index { |value, i| result.data[i] = value >= threshold ? 255_u8 : 0_u8 }
      result
    end

    # Brightness histogram, 256 bins.
    def histogram : Array(Int32)
      bins = Array(Int32).new(256, 0)
      gray = to_gray
      gray.data.each { |value| bins[value] += 1 }
      bins
    end

    # The threshold that best separates dark from bright pixels (Otsu).
    def otsu_threshold : Int32
      bins = histogram
      total = @width * @height
      sum_all = bins.each_with_index.sum { |count, value| count.to_i64 * value }
      weight_background = 0_i64
      sum_background = 0_i64
      best = 0
      best_variance = -1.0
      256.times do |value|
        weight_background += bins[value]
        next if weight_background == 0
        weight_foreground = total - weight_background
        break if weight_foreground == 0
        sum_background += bins[value].to_i64 * value
        mean_background = sum_background.to_f / weight_background
        mean_foreground = (sum_all - sum_background).to_f / weight_foreground
        variance = weight_background.to_f * weight_foreground * (mean_background - mean_foreground) ** 2
        if variance > best_variance
          best_variance = variance
          best = value
        end
      end
      best
    end

    # White where brightness is above `level` (Otsu's level by default).
    def threshold(level : Int32? = nil) : Image
      cut = level || otsu_threshold
      gray = to_gray
      result = Image.new(@width, @height, 1)
      gray.data.each_with_index { |value, i| result.data[i] = value > cut ? 255_u8 : 0_u8 }
      result
    end

    def mean_brightness : Float64
      gray = to_gray
      gray.data.sum(&.to_i64).to_f / gray.data.size
    end

    # ---------------------------------------------------------- PPM / PGM

    # Binary PGM (P5) for gray images, PPM (P6) for RGB.
    def to_ppm : Bytes
      io = IO::Memory.new
      io << (gray? ? "P5" : "P6") << '\n' << @width << ' ' << @height << "\n255\n"
      io.write(@data)
      io.to_slice
    end

    def self.from_ppm(bytes : Bytes) : Image
      position = 0
      token = -> do
        loop do
          raise ImageError.new("truncated PNM header") if position >= bytes.size
          if bytes[position].unsafe_chr.ascii_whitespace?
            position += 1
          elsif bytes[position] == '#'.ord
            while position < bytes.size && bytes[position] != '\n'.ord
              position += 1
            end
          else
            break
          end
        end
        start = position
        while position < bytes.size && !bytes[position].unsafe_chr.ascii_whitespace?
          position += 1
        end
        String.new(bytes[start, position - start])
      end

      magic = token.call
      channels = case magic
                 when "P2", "P5" then 1
                 when "P3", "P6" then 3
                 else                 raise ImageError.new("not a PGM/PPM file (magic #{magic.inspect})")
                 end
      width = token.call.to_i? || raise ImageError.new("bad PNM width")
      height = token.call.to_i? || raise ImageError.new("bad PNM height")
      max = token.call.to_i? || raise ImageError.new("bad PNM maximum")
      raise ImageError.new("only 8-bit PNM is supported (maximum #{max})") unless 0 < max <= 255
      image = Image.new(width, height, channels)
      scale = ->(value : Int32) { max == 255 ? value.to_u8 : ((value * 255 + max // 2) // max).clamp(0, 255).to_u8 }

      if magic == "P5" || magic == "P6"
        position += 1 # the single whitespace byte after the maximum
        raise ImageError.new("truncated PNM pixel data") if bytes.size - position < image.data.size
        image.data.size.times { |i| image.data[i] = scale.call(bytes[position + i].to_i) }
      else
        image.data.size.times do |i|
          image.data[i] = scale.call(token.call.to_i? || raise ImageError.new("bad PNM sample"))
        end
      end
      image
    end

    # ---------------------------------------------------------------- PNG

    PNG_SIGNATURE = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    def to_png : Bytes
      io = IO::Memory.new
      io.write(PNG_SIGNATURE)
      header = IO::Memory.new
      header.write_bytes(@width.to_u32, IO::ByteFormat::BigEndian)
      header.write_bytes(@height.to_u32, IO::ByteFormat::BigEndian)
      header.write(Bytes[8, gray? ? 0 : 2, 0, 0, 0])
      Image.write_chunk(io, "IHDR", header.to_slice)

      raw = IO::Memory.new
      row_bytes = @width * @channels
      @height.times do |y|
        raw.write_byte(0_u8) # filter: none
        raw.write(@data[y * row_bytes, row_bytes])
      end
      compressed = IO::Memory.new
      Compress::Zlib::Writer.open(compressed) { |zlib| zlib.write(raw.to_slice) }
      Image.write_chunk(io, "IDAT", compressed.to_slice)
      Image.write_chunk(io, "IEND", Bytes.empty)
      io.to_slice
    end

    # CRC-32 over a chunk's type and payload. (An empty payload is skipped:
    # zlib treats a null buffer as "reset" and would return 0.)
    protected def self.chunk_crc(type : Bytes, payload : Bytes) : UInt32
      crc = Digest::CRC32.checksum(type)
      payload.empty? ? crc : Digest::CRC32.update(payload, crc)
    end

    protected def self.write_chunk(io : IO, type : String, payload : Bytes) : Nil
      io.write_bytes(payload.size.to_u32, IO::ByteFormat::BigEndian)
      io << type
      io.write(payload)
      io.write_bytes(chunk_crc(type.to_slice, payload), IO::ByteFormat::BigEndian)
    end

    # Where each Adam7 pass puts its pixels: first column, first row,
    # column step, row step.
    ADAM7_PASSES = [{0, 0, 8, 8}, {4, 0, 8, 8}, {0, 4, 4, 8}, {2, 0, 4, 4}, {0, 2, 2, 4}, {1, 0, 2, 2}, {0, 1, 1, 2}]

    # Decode a PNG: grayscale, RGB, palette, gray+alpha or RGBA at any
    # standard bit depth, plain or Adam7 interlaced. Alpha is composited
    # over white and 16-bit samples keep their high byte.
    def self.from_png(bytes : Bytes) : Image
      raise ImageError.new("not a PNG file") unless bytes.size >= 8 && bytes[0, 8] == PNG_SIGNATURE
      position = 8
      width = height = 0
      depth = 8
      color_type = -1
      palette = Bytes.empty
      transparency = Bytes.empty
      compressed = IO::Memory.new
      seen_end = false
      interlace = 0

      while position + 8 <= bytes.size
        length = IO::ByteFormat::BigEndian.decode(UInt32, bytes[position, 4]).to_i64
        type_bytes = bytes[position + 4, 4]
        type = String.new(type_bytes).scrub
        raise ImageError.new("truncated PNG chunk #{type}") if position + 12 + length > bytes.size
        payload = bytes[position + 8, length.to_i32]
        stored = IO::ByteFormat::BigEndian.decode(UInt32, bytes[position + 8 + length.to_i32, 4])
        raise ImageError.new("PNG chunk #{type} is corrupt (CRC mismatch)") unless stored == chunk_crc(type_bytes, payload)
        case type
        when "IHDR"
          width = IO::ByteFormat::BigEndian.decode(UInt32, payload[0, 4]).to_i32
          height = IO::ByteFormat::BigEndian.decode(UInt32, payload[4, 4]).to_i32
          depth = payload[8].to_i
          color_type = payload[9].to_i
          allowed = case color_type
                    when 0 then {1, 2, 4, 8, 16}
                    when 3 then {1, 2, 4, 8}
                    else        {8, 16}
                    end
          raise ImageError.new("PNG bit depth #{depth} is not valid for colour type #{color_type}") unless allowed.includes?(depth)
          interlace = payload[12].to_i
          raise ImageError.new("unknown PNG interlace method #{interlace}") unless interlace == 0 || interlace == 1
        when "PLTE" then palette = payload
        when "tRNS" then transparency = payload
        when "IDAT" then compressed.write(payload)
        when "IEND"
          seen_end = true
          break
        end
        position += 12 + length.to_i32
      end
      raise ImageError.new("PNG has no IHDR") if color_type < 0
      raise ImageError.new("PNG has no IEND") unless seen_end

      samples = case color_type
                when 0 then 1 # gray
                when 2 then 3 # RGB
                when 3 then 1 # palette index
                when 4 then 2 # gray + alpha
                when 6 then 4 # RGBA
                else        raise ImageError.new("unknown PNG colour type #{color_type}")
                end
      raise ImageError.new("PNG is too large") if width.to_i64 * height * samples * 2 > Int32::MAX
      bits = samples * depth
      # Filters work on whole bytes: the distance to the "previous pixel".
      stride = Math.max(bits // 8, 1)
      compressed.rewind
      raw = Compress::Zlib::Reader.open(compressed, &.getb_to_end)

      # One byte per sample, whatever the stored depth. Gray samples are
      # scaled to 0-255; palette indices stay as they are. An interlaced
      # file stores seven reduced images one after the other, each filtered
      # on its own; a plain file is one pass over every pixel.
      pixels = Bytes.new(width * height * samples)
      passes = interlace == 1 ? ADAM7_PASSES : [{0, 0, 1, 1}]
      consumed = 0
      passes.each do |(x0, y0, dx, dy)|
        pass_width = (width - x0 + dx - 1) // dx
        pass_height = (height - y0 + dy - 1) // dy
        next if pass_width <= 0 || pass_height <= 0

        row_bytes = (pass_width * bits + 7) // 8
        needed = (row_bytes + 1) * pass_height
        raise ImageError.new("PNG pixel data is truncated") if raw.size - consumed < needed
        unfiltered = unfilter_png(raw[consumed, needed], row_bytes, pass_height, stride)
        consumed += needed

        pass_height.times do |pass_y|
          row = unfiltered[pass_y * row_bytes, row_bytes]
          target = ((y0 + pass_y * dy) * width + x0) * samples
          (pass_width * samples).times do |i|
            value = case depth
                    when  8 then row[i]
                    when 16 then row[i * 2]
                    else
                      shift = 8 - depth - (i * depth) % 8
                      packed = (row[i * depth // 8].to_i >> shift) & ((1 << depth) - 1)
                      color_type == 3 ? packed.to_u8 : (packed * 255 // ((1 << depth) - 1)).to_u8
                    end
            pixels[target + (i // samples) * dx * samples + i % samples] = value
          end
        end
      end

      over_white = ->(value : UInt8, alpha : UInt8) { ((value.to_i * alpha + 255 * (255 - alpha.to_i) + 127) // 255).to_u8 }
      image = Image.new(width, height, color_type == 0 || color_type == 4 ? 1 : 3)
      (width * height).times do |p|
        case color_type
        when 0 then image.data[p] = pixels[p]
        when 2 then image.data[p * 3, 3].copy_from(pixels[p * 3, 3])
        when 3
          index = pixels[p].to_i
          raise ImageError.new("PNG palette index #{index} out of range") if index * 3 + 2 >= palette.size
          alpha = transparency[index]? || 255_u8
          3.times { |c| image.data[p * 3 + c] = over_white.call(palette[index * 3 + c], alpha) }
        when 4 then image.data[p] = over_white.call(pixels[p * 2], pixels[p * 2 + 1])
        when 6 then 3.times { |c| image.data[p * 3 + c] = over_white.call(pixels[p * 4 + c], pixels[p * 4 + 3]) }
        end
      end
      image
    end

    # Undo PNG's per-row filters for one pass of `rows` rows.
    protected def self.unfilter_png(raw : Bytes, row_bytes : Int32, rows : Int32, stride : Int32) : Bytes
      unfiltered = Bytes.new(row_bytes * rows)
      rows.times do |y|
        filter = raw[y * (row_bytes + 1)]
        line = raw[y * (row_bytes + 1) + 1, row_bytes]
        row_bytes.times do |i|
          left = i >= stride ? unfiltered[y * row_bytes + i - stride].to_i : 0
          up = y > 0 ? unfiltered[(y - 1) * row_bytes + i].to_i : 0
          up_left = y > 0 && i >= stride ? unfiltered[(y - 1) * row_bytes + i - stride].to_i : 0
          predicted = case filter
                      when 0 then 0
                      when 1 then left
                      when 2 then up
                      when 3 then (left + up) // 2
                      when 4
                        estimate = left + up - up_left
                        dl = (estimate - left).abs
                        du = (estimate - up).abs
                        dul = (estimate - up_left).abs
                        dl <= du && dl <= dul ? left : (du <= dul ? up : up_left)
                      else raise ImageError.new("unknown PNG filter #{filter}")
                      end
          unfiltered[y * row_bytes + i] = ((line[i].to_i + predicted) & 0xFF).to_u8
        end
      end
      unfiltered
    end

    # Read a PNG, JPEG, PGM or PPM file, by content.
    def self.load(path : String) : Image
      bytes = File.open(path, &.getb_to_end)
      from_bytes(bytes)
    rescue ex : File::Error
      raise ImageError.new("cannot read #{path}: #{ex.message}")
    end

    def self.from_bytes(bytes : Bytes) : Image
      if bytes.size >= 8 && bytes[0, 8] == PNG_SIGNATURE
        from_png(bytes)
      elsif bytes.size >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
        from_jpeg(bytes)
      elsif bytes.size >= 2 && bytes[0] == 'P'.ord
        from_ppm(bytes)
      else
        raise ImageError.new("unrecognised image format (PNG, JPEG, PGM and PPM are supported)")
      end
    end

    # Decode a baseline JPEG (see `Vision::JPEG`).
    def self.from_jpeg(bytes : Bytes) : Image
      JPEG.decode(bytes)
    end

    # Write as PNG, or as PGM/PPM when the path ends in .pgm, .ppm or .pnm.
    def save(path : String) : Nil
      extension = File.extname(path).downcase
      File.write(path, {".pgm", ".ppm", ".pnm"}.includes?(extension) ? to_ppm : to_png)
    end
  end
end

require "./jpeg"
