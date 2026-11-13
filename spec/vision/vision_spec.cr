require "spec"
require "../../src/vision/vision"
require "../../src/pattern_matching/pattern_matching_main"
require "../../src/tools/cog_tools"
require "../../src/robotics/sensory_motor"

private def hex(text : String) : Bytes
  text.hexbytes
end

# A 200x120 white scene: a red circle on the left, a blue square in the
# middle with a small yellow square inside it, and a green triangle on the right.
private def sample_scene : Vision::Image
  image = Vision::Image.new(200, 120).fill(255_u8, 255_u8, 255_u8)
  image.fill_circle(35, 60, 22, 220_u8, 20_u8, 20_u8)
  image.fill_rect(80, 40, 40, 40, 20_u8, 40_u8, 220_u8)
  image.fill_rect(95, 55, 10, 10, 240_u8, 230_u8, 20_u8)
  image.fill_triangle(165, 35, 50, 50, 20_u8, 180_u8, 40_u8)
  image
end

describe Vision::Image do
  # Encoded by an independent implementation (Python's zlib and struct),
  # one row per PNG filter type, pixel data split across two IDAT chunks.
  it "decodes PNGs using every filter type" do
    png = hex("89504e470d0a1a0a0000000d4948445200000005000000050802000000020db1b20000002649444154789c636060603762644f61629fc6cc7e82859d91d906c8e7852326661b06661b5e661b29661ba32f3228000000274944415475661b1366b60a1669792969794569797569793d16903c232f33a31433a33a33a30900580507fa44abb8f80000000049454e44ae426082")
    image = Vision::Image.from_png(png)
    {image.width, image.height, image.channels}.should eq({5, 5, 3})
    image.data.should eq(hex("000007320107640207960307c80407033c07353d14673e21993f2ecb403b0678073879216a7a3b9c7b55ce7c6f09b4073bb52e6db6559fb77cd1b8a30cf0073ef13b70f26fa2f3a3d4f4d7"))
  end

  it "composites RGBA and palette transparency over white" do
    rgba = Vision::Image.from_png(hex("89504e470d0a1a0a0000000d49484452000000030000000208060000009d74661a0000001049444154789c63399162f49f818181d162ceb9066cbe0c070000001149444154e61423c90620a771ceb9e70e006e5208c97ad317950000000049454e44ae426082"))
    {rgba.width, rgba.height}.should eq({3, 2})
    rgba.rgb(0, 0).should eq({200_u8, 100_u8, 50_u8})
    rgba.rgb(1, 1).should eq({255_u8, 255_u8, 255_u8})
    rgba.rgb(2, 0).should eq({127_u8, 127_u8, 127_u8})

    palette = Vision::Image.from_png(hex("89504e470d0a1a0a0000000d494844520000000400000002080300000048768d5100000009504c5445ff000000ff000000ff2d4acd8a0000000274524e53ff00e5b7304a0000000949444154789c63606064626462e4c68e82000000094944415462fcf71f0003360207b6396c800000000049454e44ae426082"))
    red, white, blue = {255_u8, 0_u8, 0_u8}, {255_u8, 255_u8, 255_u8}, {0_u8, 0_u8, 255_u8}
    (0...4).map { |x| palette.rgb(x, 0) }.should eq([red, white, blue, white])
    (0...4).map { |x| palette.rgb(x, 1) }.should eq([blue, blue, red, red])
  end

  it "decodes sub-byte and 16-bit PNG depths" do
    bw = Vision::Image.from_png(hex("89504e470d0a1a0a0000000d494844520000000a000000020100000000491a707d0000000e49444154789c6358d5c0c07e0000062601f2d1757ae60000000049454e44ae426082"))
    {bw.width, bw.height, bw.channels}.should eq({10, 2, 1})
    bw.data[0, 10].to_a.should eq([255, 0, 255, 0, 255, 0, 255, 0, 255, 0])
    bw.data[10, 10].to_a.should eq([0, 0, 0, 0, 0, 255, 255, 255, 255, 255])

    two_bit = Vision::Image.from_png(hex("89504e470d0a1a0a0000000d49484452000000050000000102030000006b908c600000000c504c5445ff000000ff000000ffffff00d6028f7b0000000b49444154789c63906600000039001c6eec178c0000000049454e44ae426082"))
    (0...5).map { |x| two_bit.rgb(x, 0) }.should eq([{255_u8, 0_u8, 0_u8}, {0_u8, 255_u8, 0_u8}, {0_u8, 0_u8, 255_u8},
                                                     {255_u8, 255_u8, 0_u8}, {255_u8, 0_u8, 0_u8}])

    sixteen = Vision::Image.from_png(hex("89504e470d0a1a0a0000000d49484452000000030000000110000000006e1b972b0000000f49444154789c63606068f8ffff3f000801037e0519bc080000000049454e44ae426082"))
    sixteen.data.to_a.should eq([0, 128, 255])
    four_bit = Vision::Image.from_png(hex("89504e470d0a1a0a0000000d4948445200000003000000010400000000fb7ba6690000000b49444154789c6360fd000000fd00f6aa3114fa0000000049454e44ae426082"))
    four_bit.data.to_a.should eq([0, 85, 255])
  end

  it "round-trips PNG and PPM, colour and gray" do
    scene = sample_scene
    Vision::Image.from_png(scene.to_png).should eq(scene)
    Vision::Image.from_ppm(scene.to_ppm).should eq(scene)
    gray = scene.to_gray
    gray.channels.should eq(1)
    Vision::Image.from_bytes(gray.to_png).should eq(gray)
    Vision::Image.from_bytes(gray.to_ppm).should eq(gray)

    ascii = Vision::Image.from_ppm("P3\n# a comment\n2 1\n15\n15 0 0  0 15 7\n".to_slice)
    ascii.rgb(0, 0).should eq({255_u8, 0_u8, 0_u8})
    ascii.rgb(1, 0).should eq({0_u8, 255_u8, 119_u8})

    path = File.tempname("vision", ".png")
    begin
      scene.save(path)
      Vision::Image.load(path).should eq(scene)
    ensure
      File.delete?(path)
    end
  end

  it "rejects corrupt and unsupported input" do
    png = sample_scene.to_png
    damaged = png.dup
    damaged[40] ^= 0xFF_u8
    expect_raises(Vision::ImageError, /CRC mismatch/) { Vision::Image.from_png(damaged) }
    expect_raises(Vision::ImageError, /no IEND/) { Vision::Image.from_png(png[0, png.size - 12]) }
    expect_raises(Vision::ImageError, /unrecognised image format/) { Vision::Image.from_bytes("GIF89a".to_slice) }
    expect_raises(Vision::ImageError, /truncated/) { Vision::Image.from_ppm("P6 4 4 255\nabc".to_slice) }
    expect_raises(Vision::ImageError, /cannot read/) { Vision::Image.load("/nonexistent/image.png") }
    expect_raises(Vision::ImageError, /expected 12 bytes/) { Vision::Image.new(2, 2, 3, Bytes.new(5)) }
  end

  it "reads raw sensor encodings" do
    bgr = Vision::Image.from_raw(2, 1, Bytes[10, 20, 30, 40, 50, 60], "bgr8")
    bgr.rgb(0, 0).should eq({30_u8, 20_u8, 10_u8})
    padded = Vision::Image.from_raw(1, 2, Bytes[1, 2, 3, 0, 0, 4, 5, 6], "rgb8", step: 5)
    padded.rgb(0, 1).should eq({4_u8, 5_u8, 6_u8})
    Vision::Image.from_raw(2, 1, Bytes[7, 9], "mono8").gray_at(1, 0).should eq(9)
    Vision::Image.from_raw(1, 1, Bytes[1, 2, 3, 255], "rgba8").rgb(0, 0).should eq({1_u8, 2_u8, 3_u8})
    expect_raises(Vision::ImageError, /needs 6 bytes/) { Vision::Image.from_raw(2, 1, Bytes[1, 2, 3], "rgb8") }
  end

  it "filters: gray, blur, resize, crop, threshold and edges" do
    image = Vision::Image.new(40, 40).fill(0_u8, 0_u8, 0_u8)
    image.fill_rect(10, 10, 20, 20, 255_u8, 255_u8, 255_u8)

    Vision::Image.luma(255_u8, 0_u8, 0_u8).should eq(76)
    image.mean_brightness.should eq(63.75)
    image.otsu_threshold.should be < 255
    binary = image.threshold
    binary.gray_at(20, 20).should eq(255)
    binary.gray_at(2, 2).should eq(0)

    blurred = image.gaussian_blur(2.0)
    blurred.gray_at(20, 20).should eq(255)
    (0 < blurred.gray_at(10, 20) < 255).should be_true
    blurred.gray_at(0, 0).should eq(0)
    blurred.mean_brightness.should be_close(63.75, 1.0)

    edges = image.edges
    edges.gray_at(10, 20).should eq(255) # on the square's left side
    edges.gray_at(20, 20).should eq(0)   # inside
    edges.gray_at(2, 2).should eq(0)     # outside

    half = image.resize(20, 20)
    {half.width, half.height}.should eq({20, 20})
    half.gray_at(10, 10).should eq(255)
    half.gray_at(1, 1).should eq(0)
    image.crop(10, 10, 20, 20).data.all? { |v| v == 255 }.should be_true
    expect_raises(Vision::ImageError, /leaves the/) { image.crop(30, 30, 20, 20) }
  end
end

describe "Vision perception" do
  it "names colours" do
    Vision.color_name(220_u8, 20_u8, 20_u8).should eq("red")
    Vision.color_name(20_u8, 40_u8, 220_u8).should eq("blue")
    Vision.color_name(20_u8, 180_u8, 40_u8).should eq("green")
    Vision.color_name(240_u8, 230_u8, 20_u8).should eq("yellow")
    Vision.color_name(250_u8, 140_u8, 20_u8).should eq("orange")
    Vision.color_name(150_u8, 30_u8, 200_u8).should eq("purple")
    Vision.color_name(255_u8, 255_u8, 255_u8).should eq("white")
    Vision.color_name(120_u8, 120_u8, 120_u8).should eq("gray")
    Vision.color_name(10_u8, 10_u8, 10_u8).should eq("black")
    Vision.hsv(0_u8, 255_u8, 0_u8).should eq({120.0, 1.0, 1.0})
  end

  it "finds coloured shapes and where they are" do
    scene = Vision.perceive(sample_scene, "test")
    scene.detections.map(&.label).sort.should eq(["blue square", "green triangle", "red circle", "yellow square"])

    circle = scene.detections.find! { |d| d.color == "red" }
    circle.center_x.should be_close(35.0, 0.5)
    circle.center_y.should be_close(60.0, 0.5)
    {circle.width, circle.height}.should eq({45, 45})
    circle.area.should be_close(Math::PI * 22 * 22, 30)
    circle.confidence.should be > 0.8

    square = scene.detections.find! { |d| d.color == "blue" }
    {square.x0, square.y0, square.x1, square.y1}.should eq({80, 40, 119, 79})
    # The yellow square sits inside the blue one and is not part of it.
    square.area.should eq(40 * 40 - 10 * 10)
    scene.detections.first.should eq(circle) # largest first
  end

  it "relates the objects to each other" do
    scene = Vision.perceive(sample_scene, "test")
    id = ->(color : String) { scene.detections.find! { |d| d.color == color }.id }
    has = ->(name : String, a : String, b : String) do
      scene.relations.includes?(Vision::Relation.new(name, id.call(a), id.call(b)))
    end
    has.call("left-of", "red", "blue").should be_true
    has.call("left-of", "blue", "green").should be_true
    has.call("left-of", "green", "red").should be_false
    has.call("inside", "yellow", "blue").should be_true
    has.call("inside", "blue", "yellow").should be_false
    has.call("larger-than", "blue", "yellow").should be_true
    has.call("above", "red", "blue").should be_false

    text = scene.describe
    text.should start_with("4 objects:")
    text.should contain("red circle #1 at the middle left")
    text.should match(/yellow square #\d is inside blue square #\d/)
    Vision.perceive(Vision::Image.new(20, 20).fill(9_u8, 9_u8, 9_u8)).describe.should eq("Nothing stands out from the background.")
  end

  it "tells shapes apart by how they fill their bounding box" do
    image = Vision::Image.new(300, 80).fill(0_u8, 0_u8, 0_u8)
    image.fill_rect(10, 20, 60, 30, 220_u8, 20_u8, 20_u8)      # rectangle
    image.fill_circle(120, 40, 25, 20_u8, 180_u8, 40_u8)       # circle
    image.fill_triangle(190, 15, 50, 50, 20_u8, 40_u8, 220_u8) # triangle
    26.times do |row|                                          # diamond
      half = row <= 12 ? row : 25 - row
      image.fill_rect(260 - half, 27 + row, 2 * half + 1, 1, 240_u8, 230_u8, 20_u8)
    end
    shapes = Vision.detect_objects(image).to_h { |d| {d.color, d.shape} }
    shapes.should eq({"red" => "rectangle", "green" => "circle", "blue" => "triangle", "yellow" => "diamond"})
  end

  it "detects what moved between two frames" do
    before = Vision::Image.new(100, 60).fill(30_u8, 30_u8, 30_u8)
    after = before.dup
    before.fill_rect(10, 20, 12, 12, 250_u8, 250_u8, 250_u8)
    after.fill_rect(60, 20, 12, 12, 250_u8, 250_u8, 250_u8)

    moved = Vision.motion(before, after).sort_by(&.x0)
    moved.size.should eq(2) # where it left, and where it arrived
    {moved[0].x0, moved[0].width, moved[1].x0, moved[1].width}.should eq({10, 12, 60, 12})
    Vision.motion(before, before).should be_empty
    expect_raises(Vision::ImageError, /differ in size/) { Vision.motion(before, Vision::Image.new(10, 10)) }
  end
end

describe Vision::Scene do
  it "grounds what it sees in the AtomSpace, where it can be queried" do
    space = AtomSpace::AtomSpace.new
    scene = Vision.perceive(sample_scene, "desk")
    atoms = scene.ground(space)
    atoms.should_not be_empty

    red = scene.detections.find! { |d| d.color == "red" }
    blue = scene.detections.find! { |d| d.color == "blue" }
    red_node = space.get_nodes_by_name("desk:object-#{red.id}").first
    blue_node = space.get_nodes_by_name("desk:object-#{blue.id}").first

    facts = space.get_incoming(red_node).map(&.to_s)
    facts.should contain(%((MEMBERLINK (CONCEPTNODE "desk:object-#{red.id}") (CONCEPTNODE "scene:desk"))))
    facts.should contain(%((INHERITANCELINK (CONCEPTNODE "desk:object-#{red.id}") (CONCEPTNODE "circle"))))
    space.get_all_atoms.map(&.to_s).should contain(
      %((EVALUATIONLINK (PREDICATENODE "color") (LISTLINK (CONCEPTNODE "desk:object-#{red.id}") (CONCEPTNODE "red")))))
    space.get_all_atoms.map(&.to_s).should contain(
      %((EVALUATIONLINK (PREDICATENODE "position") (LISTLINK (CONCEPTNODE "desk:object-#{red.id}") (NUMBERNODE "0.175") (NUMBERNODE "0.5")))))

    # "What is the red thing to the left of?"
    pattern = AtomSpace::EvaluationLink.new(space.add_predicate_node("left-of"),
      AtomSpace::ListLink.new([red_node, AtomSpace::VariableNode.new("$what")] of AtomSpace::Atom))
    found = PatternMatching::PatternMatcher.new(space).match(PatternMatching::Pattern.new(pattern))
    found.flat_map(&.bindings.values).should contain(blue_node)

    # Grounding the same scene again adds nothing new.
    size = space.size
    scene.ground(space)
    space.size.should eq(size)
  end
end

describe "Vision in the shell and the chat tools" do
  it "looks at an image file with the see command and the see_image tool" do
    path = File.tempname("desk", ".png")
    begin
      sample_scene.save(path)
      tools = CrystalCog::CogTools.new
      output = tools.call("see_image", {"path" => path, "scene" => "desk"}.to_json)
      output.should contain("4 objects:")
      output.should contain("Added")
      output.should contain("scene:desk")
      tools.atomspace.get_nodes_by_name("scene:desk").size.should eq(1)
      tools.run("query circle").should contain(%((CONCEPTNODE "circle")))
      tools.run("list member").should contain("desk:object-1")

      tools.names.should contain("see_image")
      expect_raises(Vision::ImageError, /cannot read \/nonexistent.png/) do
        tools.call("see_image", {"path" => "/nonexistent.png"}.to_json)
      end
    ensure
      File.delete?(path)
    end
  end
end

describe Robotics::VisionSensor do
  it "reports what its current frame shows" do
    camera = Robotics::VisionSensor.new("camera", resolution: {200, 120}, field_of_view: Math::PI / 2)
    camera.activate
    camera.read.get("object_count").should be_nil
    camera.perceive.should be_nil

    camera.set_image_data(sample_scene.data)
    reading = camera.read
    reading.get_float("object_count").should eq(4.0)
    reading.get("objects").as(String).should contain("red circle")
    reading.get_float("brightness").not_nil!.should be > 150.0
    reading.get("description").as(String).should start_with("4 objects:")

    # The red circle is left of the optical axis, the green triangle right.
    scene = camera.perceive.not_nil!
    bearings = reading.get_array("bearings").not_nil!
    red = scene.detections.index! { |d| d.color == "red" }
    green = scene.detections.index! { |d| d.color == "green" }
    bearings[red].should be > 0.4
    bearings[green].should be < -0.4
    camera.bearing(100.0).should eq(0.0)
    camera.bearing(0.0).should be_close(Math::PI / 4, 1e-9)

    space = AtomSpace::AtomSpace.new
    camera.perceive_into(space).should_not be_empty
    space.get_nodes_by_name("scene:camera").size.should eq(1)

    # A decoded image sets the resolution too; BGR frames are understood.
    camera.set_image(Vision::Image.new(10, 10).fill(0_u8, 0_u8, 0_u8))
    camera.resolution.should eq({10, 10})
    camera.read.get_float("object_count").should eq(0.0)
    camera.set_image_data(Bytes.new(300) { |i| i % 3 == 0 ? 255_u8 : 0_u8 }, "bgr8")
    camera.image.not_nil!.rgb(0, 0).should eq({0_u8, 0_u8, 255_u8})
  end
end
