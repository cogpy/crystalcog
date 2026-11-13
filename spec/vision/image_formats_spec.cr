require "spec"
require "../../src/vision/vision"

# The fixtures were written by Pillow and ImageMagick. Each `.ppm`/`.pgm`
# is the same picture decoded by one of those tools (JPEG chroma upsampled
# by plain repetition), so the decoders here are checked against an
# independent implementation.
private FIXTURES = File.join(__DIR__, "fixtures")

private def fixture(name : String) : Bytes
  File.open(File.join(FIXTURES, name), &.getb_to_end)
end

private def largest_difference(a : Vision::Image, b : Vision::Image) : Int32
  {a.width, a.height, a.channels}.should eq({b.width, b.height, b.channels})
  a.data.zip(b.data).max_of { |x, y| (x.to_i - y.to_i).abs }
end

describe "Vision::Image interlaced PNG" do
  {
    "adam7_rgb"     => "ppm",
    "adam7_gray"    => "pgm",
    "adam7_gray16"  => "pgm",
    "adam7_bilevel" => "pgm",
    "adam7_palette" => "ppm",
    "adam7_rgba"    => "ppm",
    "adam7_1x1"     => "ppm",
    "adam7_3x2"     => "ppm",
    "adam7_5x9"     => "ppm",
  }.each do |name, reference|
    it "decodes #{name}" do
      image = Vision::Image.from_png(fixture("#{name}.png"))
      expected = Vision::Image.from_ppm(fixture("#{name}.#{reference}"))
      largest_difference(image, expected).should eq(0)
    end
  end

  it "gives the same pixels as the plain file it was made from" do
    interlaced = Vision::Image.from_png(fixture("adam7_rgb.png"))
    plain = Vision::Image.from_png(fixture("scene.png"))
    {plain.width, plain.height}.should eq({37, 29})
    interlaced.should eq(plain)
  end

  it "rejects an unknown interlace method and truncated passes" do
    png = fixture("adam7_rgb.png").dup
    # IHDR's interlace byte, then its CRC.
    png[28] = 2_u8
    header = png[12, 17]
    IO::ByteFormat::BigEndian.encode(Digest::CRC32.checksum(header), png[29, 4])
    expect_raises(Vision::ImageError, "unknown PNG interlace method 2") { Vision::Image.from_png(png) }

    # A plain image's data is too short for the seven passes of the same size.
    plain = fixture("scene.png").dup
    plain[28] = 1_u8
    IO::ByteFormat::BigEndian.encode(Digest::CRC32.checksum(plain[12, 17]), plain[29, 4])
    expect_raises(Vision::ImageError, "PNG pixel data is truncated") { Vision::Image.from_png(plain) }
  end
end

describe Vision::JPEG do
  {
    "scene_444"     => "full-resolution chroma",
    "scene_420"     => "chroma halved both ways",
    "scene_422"     => "chroma halved across",
    "scene_restart" => "restart markers",
    "one_pixel"     => "a single pixel",
  }.each do |name, what|
    it "decodes #{name} (#{what})" do
      image = Vision::Image.from_jpeg(fixture("#{name}.jpg"))
      expected = Vision::Image.from_ppm(fixture("#{name}.ppm"))
      image.channels.should eq(3)
      # Inverse DCTs may round a sample differently; nothing more.
      largest_difference(image, expected).should be <= 3
    end
  end

  it "decodes a grayscale file to one channel" do
    image = Vision::Image.from_jpeg(fixture("scene_gray.jpg"))
    image.gray?.should be_true
    largest_difference(image, Vision::Image.from_ppm(fixture("scene_gray.pgm"))).should be <= 2
  end

  it "stays close to the picture that was compressed" do
    original = Vision::Image.from_png(fixture("scene.png"))
    decoded = Vision::Image.from_jpeg(fixture("scene_444.jpg"))
    differences = original.data.zip(decoded.data).map { |x, y| (x.to_i - y.to_i).abs }
    (differences.sum / differences.size).should be < 4.0
  end

  it "is found by content, whatever the file is called" do
    Vision::Image.from_bytes(fixture("scene_420.jpg")).width.should eq(37)
    path = File.tempname("jpeg-as", ".dat")
    File.write(path, fixture("scene_gray.jpg"))
    begin
      Vision::Image.load(path).height.should eq(29)
    ensure
      File.delete(path)
    end
  end

  it "perceives the shapes in a photograph-style file" do
    scene = Vision.perceive_file(File.join(FIXTURES, "shapes.jpg"))
    {scene.width, scene.height}.should eq({160, 120})
    scene.detections.map(&.label).sort.should eq(["blue circle", "green triangle", "red square"])
    scene.describe.should contain("red square #1 is left of blue circle #2")
  end

  it "says which kinds of JPEG it does not read" do
    expect_raises(Vision::ImageError, "progressive JPEG is not supported") do
      Vision::Image.from_jpeg(fixture("scene_progressive.jpg"))
    end
    expect_raises(Vision::ImageError, "not a JPEG file") { Vision::Image.from_jpeg(fixture("scene.png")) }
  end

  it "reports damaged files instead of returning a wrong picture" do
    jpeg = fixture("scene_420.jpg")
    # Cut inside the compressed data: the end-of-image marker is gone.
    expect_raises(Vision::ImageError) { Vision::Image.from_jpeg(jpeg[0, jpeg.size // 2]) }
    # Cut inside the headers.
    expect_raises(Vision::ImageError, "truncated JPEG segment") { Vision::Image.from_jpeg(jpeg[0, 30]) }
    # No scan at all: start and end markers only.
    expect_raises(Vision::ImageError, "JPEG has no image data") { Vision::Image.from_jpeg(Bytes[0xFF, 0xD8, 0xFF, 0xD9]) }

    # A frame of four components (CMYK).
    cmyk = jpeg.dup
    frame = (0...cmyk.size - 1).find! { |i| cmyk[i] == 0xFF && cmyk[i + 1] == 0xC0 }
    cmyk[frame + 9] = 4_u8
    expect_raises(Vision::ImageError, "4 components is not supported") { Vision::Image.from_jpeg(cmyk) }
  end
end
