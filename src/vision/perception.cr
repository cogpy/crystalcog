# From pixels to things: colour naming, segmentation into regions, shape
# classification, spatial relations between the objects found, and motion
# between frames.

require "./image"

module Vision
  COLOR_NAMES = %w(black gray white red orange yellow green cyan blue purple pink)

  # The everyday name of a colour, decided in HSV space.
  def self.color_name(r : UInt8, g : UInt8, b : UInt8) : String
    hue, saturation, value = hsv(r, g, b)
    return "black" if value < 0.2
    return value > 0.85 ? "white" : "gray" if saturation < 0.18
    case hue
    when ...15.0  then "red"
    when ...45.0  then "orange"
    when ...70.0  then "yellow"
    when ...165.0 then "green"
    when ...200.0 then "cyan"
    when ...260.0 then "blue"
    when ...300.0 then "purple"
    when ...345.0 then "pink"
    else               "red"
    end
  end

  # Hue in degrees [0, 360), saturation and value in [0, 1].
  def self.hsv(r : UInt8, g : UInt8, b : UInt8) : {Float64, Float64, Float64}
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    max = {rf, gf, bf}.max
    min = {rf, gf, bf}.min
    delta = max - min
    hue = if delta == 0.0
            0.0
          elsif max == rf
            60.0 * (((gf - bf) / delta) % 6.0)
          elsif max == gf
            60.0 * ((bf - rf) / delta + 2.0)
          else
            60.0 * ((rf - gf) / delta + 4.0)
          end
    {hue < 0 ? hue + 360.0 : hue, max == 0.0 ? 0.0 : delta / max, max}
  end

  # A connected group of pixels of one class.
  class Region
    getter label : Int32
    getter area : Int32 = 0
    getter x0 : Int32
    getter y0 : Int32
    getter x1 : Int32
    getter y1 : Int32
    # Pixels of the region that touch a pixel outside it.
    property perimeter : Int32 = 0
    @sum_x : Int64 = 0
    @sum_y : Int64 = 0
    @sum_r : Int64 = 0
    @sum_g : Int64 = 0
    @sum_b : Int64 = 0

    def initialize(@label : Int32, x : Int32, y : Int32)
      @x0 = @x1 = x
      @y0 = @y1 = y
    end

    def add(x : Int32, y : Int32, color : {UInt8, UInt8, UInt8}) : Nil
      @area += 1
      @x0 = x if x < @x0
      @x1 = x if x > @x1
      @y0 = y if y < @y0
      @y1 = y if y > @y1
      @sum_x += x
      @sum_y += y
      @sum_r += color[0]
      @sum_g += color[1]
      @sum_b += color[2]
    end

    def width : Int32
      @x1 - @x0 + 1
    end

    def height : Int32
      @y1 - @y0 + 1
    end

    def centroid : {Float64, Float64}
      {@sum_x.to_f / @area, @sum_y.to_f / @area}
    end

    def mean_color : {UInt8, UInt8, UInt8}
      {(@sum_r // @area).to_u8, (@sum_g // @area).to_u8, (@sum_b // @area).to_u8}
    end

    # Share of the bounding box the region fills.
    def extent : Float64
      @area.to_f / (width.to_i64 * height)
    end
  end

  # Connected regions of equal class in a per-pixel class map (8-connected).
  # Pixels of class `ignore` belong to no region. Regions smaller than
  # `min_area` are dropped.
  def self.connected_regions(classes : Array(Int32), image : Image, ignore : Int32 = -1, min_area : Int32 = 1) : Array(Region)
    width, height = image.width, image.height
    raise ImageError.new("class map does not match the image") unless classes.size == width * height
    visited = Array(Bool).new(classes.size, false)
    regions = [] of Region
    stack = [] of Int32

    classes.size.times do |start|
      next if visited[start] || classes[start] == ignore
      label = classes[start]
      region = Region.new(label, start % width, start // width)
      visited[start] = true
      stack << start
      until stack.empty?
        index = stack.pop
        x = index % width
        y = index // width
        region.add(x, y, image.rgb(x, y))
        boundary = false
        (-1..1).each do |dy|
          (-1..1).each do |dx|
            next if dx == 0 && dy == 0
            nx, ny = x + dx, y + dy
            inside = image.in_bounds?(nx, ny) && classes[ny * width + nx] == label
            boundary = true if !inside && (dx == 0 || dy == 0)
            next unless inside
            neighbour = ny * width + nx
            next if visited[neighbour]
            visited[neighbour] = true
            stack << neighbour
          end
        end
        region.perimeter += 1 if boundary
      end
      regions << region if region.area >= min_area
    end
    regions
  end

  # Something seen in an image.
  record Detection,
    id : Int32,
    color : String,
    shape : String,
    x0 : Int32, y0 : Int32, x1 : Int32, y1 : Int32,
    center_x : Float64, center_y : Float64,
    area : Int32,
    confidence : Float64 do
    def label : String
      "#{color} #{shape}"
    end

    def width : Int32
      x1 - x0 + 1
    end

    def height : Int32
      y1 - y0 + 1
    end
  end

  # A spatial relation between two detections: left-of, above, inside,
  # near or larger-than.
  record Relation, name : String, subject : Int32, object : Int32

  # The shape of a region, from how it fills its bounding box, with a
  # confidence in [0, 1].
  #
  #   rectangle / square   fills the box
  #   ellipse / circle     fills pi/4 of it
  #   triangle             fills half, with its mass off-centre
  #   diamond              fills half, centred
  def self.classify_shape(region : Region) : {String, Float64}
    extent = region.extent
    aspect = region.width.to_f / region.height
    squarish = 0.8 <= aspect <= 1.25
    if extent >= 0.9
      {squarish ? "square" : "rectangle", closeness(extent, 1.0, 0.1)}
    elsif extent >= 0.68
      {squarish ? "circle" : "ellipse", closeness(extent, Math::PI / 4, 0.12)}
    elsif extent >= 0.38 && extent <= 0.64
      cx, cy = region.centroid
      offset_x = (cx - (region.x0 + region.x1) / 2.0).abs / region.width
      offset_y = (cy - (region.y0 + region.y1) / 2.0).abs / region.height
      shape = Math.max(offset_x, offset_y) >= 0.08 ? "triangle" : "diamond"
      {shape, closeness(extent, 0.5, 0.14)}
    else
      {"blob", 0.5}
    end
  end

  private def self.closeness(value : Float64, ideal : Float64, tolerance : Float64) : Float64
    (1.0 - (value - ideal).abs / tolerance * 0.5).clamp(0.5, 1.0)
  end

  # Find the coloured objects in an image. The colour that dominates the
  # image border is taken as background; every other connected patch of one
  # colour, at least `min_area` pixels (default: 0.05% of the image, 12 at
  # least), is an object. Largest objects come first.
  def self.detect_objects(image : Image, min_area : Int32? = nil) : Array(Detection)
    classes = Array(Int32).new(image.width * image.height) do |i|
      r, g, b = image.rgb(i % image.width, i // image.width)
      COLOR_NAMES.index!(color_name(r, g, b))
    end

    border = Array(Int32).new(COLOR_NAMES.size, 0)
    image.width.times do |x|
      border[classes[x]] += 1
      border[classes[(image.height - 1) * image.width + x]] += 1
    end
    image.height.times do |y|
      border[classes[y * image.width]] += 1
      border[classes[y * image.width + image.width - 1]] += 1
    end
    background = border.index!(border.max)

    floor = min_area || Math.max(12, image.width * image.height // 2000)
    regions = connected_regions(classes, image, ignore: background, min_area: floor)
    regions.sort_by! { |region| {-region.area, region.y0, region.x0} }
    regions.map_with_index do |region, i|
      shape, confidence = classify_shape(region)
      cx, cy = region.centroid
      Detection.new(i + 1, COLOR_NAMES[region.label], shape, region.x0, region.y0, region.x1, region.y1,
        cx, cy, region.area, confidence)
    end
  end

  # Spatial relations among detections.
  def self.relations(detections : Array(Detection)) : Array(Relation)
    found = [] of Relation
    detections.each do |a|
      detections.each do |b|
        next if a.id == b.id
        found << Relation.new("larger-than", a.id, b.id) if a.area > b.area * 1.5
        inside = a.x0 >= b.x0 && a.x1 <= b.x1 && a.y0 >= b.y0 && a.y1 <= b.y1
        if inside
          found << Relation.new("inside", a.id, b.id)
          next
        end
        next if b.x0 >= a.x0 && b.x1 <= a.x1 && b.y0 >= a.y0 && b.y1 <= a.y1 # b inside a
        found << Relation.new("left-of", a.id, b.id) if a.x1 < b.x0
        found << Relation.new("above", a.id, b.id) if a.y1 < b.y0
        if a.id < b.id
          distance = Math.sqrt((a.center_x - b.center_x) ** 2 + (a.center_y - b.center_y) ** 2)
          reach = (a.width + a.height + b.width + b.height) / 2.0
          found << Relation.new("near", a.id, b.id) if distance < reach
        end
      end
    end
    found
  end

  # What changed between two frames of equal size: regions where brightness
  # moved by more than `threshold`, at least `min_area` pixels each.
  def self.motion(previous : Image, current : Image, threshold : Int32 = 30, min_area : Int32 = 12) : Array(Region)
    unless previous.width == current.width && previous.height == current.height
      raise ImageError.new("frames differ in size: #{previous.width}x#{previous.height} and #{current.width}x#{current.height}")
    end
    before = previous.to_gray
    after = current.to_gray
    changed = Array(Int32).new(before.data.size) do |i|
      (before.data[i].to_i - after.data[i].to_i).abs > threshold ? 1 : 0
    end
    connected_regions(changed, current, ignore: 0, min_area: min_area)
  end

  # A sentence or two saying what was seen.
  def self.describe(detections : Array(Detection), relations : Array(Relation), width : Int32, height : Int32) : String
    return "Nothing stands out from the background." if detections.empty?

    names = detections.to_h { |d| {d.id, "#{d.label} ##{d.id}"} }
    lines = detections.map do |d|
      horizontal = d.center_x < width / 3.0 ? "left" : (d.center_x > width * 2.0 / 3.0 ? "right" : "centre")
      vertical = d.center_y < height / 3.0 ? "top" : (d.center_y > height * 2.0 / 3.0 ? "bottom" : "middle")
      share = (100.0 * d.area / (width.to_i64 * height)).round(1)
      "#{names[d.id]} at the #{vertical} #{horizontal} (#{d.width}x#{d.height} px, #{share}% of the image)"
    end
    text = "#{detections.size} object#{detections.size == 1 ? "" : "s"}: #{lines.join("; ")}."
    shown = relations.reject { |r| r.name == "larger-than" }.first(12)
    unless shown.empty?
      text += " " + shown.map { |r| "#{names[r.subject]} is #{r.name.tr("-", " ")} #{names[r.object]}" }.join("; ") + "."
    end
    text
  end
end
