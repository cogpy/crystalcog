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

  {
    "scene_progressive"   => "chroma halved both ways",
    "progressive_444"     => "full-resolution chroma",
    "progressive_restart" => "restart markers",
  }.each do |name, what|
    it "decodes progressive #{name} (#{what})" do
      bytes = fixture("#{name}.jpg")
      # A progressive frame, sent over several scans.
      bytes.to_a.each_cons(2).count { |pair| pair == [0xFF_u8, 0xC2_u8] }.should eq(1)
      bytes.to_a.each_cons(2).count { |pair| pair == [0xFF_u8, 0xDA_u8] }.should be > 3
      image = Vision::Image.from_jpeg(bytes)
      largest_difference(image, Vision::Image.from_ppm(fixture("#{name}.ppm"))).should be <= 3
    end
  end

  it "decodes a progressive grayscale file" do
    image = Vision::Image.from_jpeg(fixture("progressive_gray.jpg"))
    image.gray?.should be_true
    largest_difference(image, Vision::Image.from_ppm(fixture("progressive_gray.pgm"))).should be <= 2
  end

  it "gives nearly the same picture for the progressive and the plain encoding" do
    plain = Vision::Image.from_jpeg(fixture("scene_444.jpg"))
    progressive = Vision::Image.from_jpeg(fixture("progressive_444.jpg"))
    largest_difference(plain, progressive).should be <= 3
  end

  it "converts a CMYK file to RGB" do
    bytes = fixture("cmyk.jpg")
    frame = (0...bytes.size - 1).find! { |i| bytes[i] == 0xFF && bytes[i + 1] == 0xC0 }
    bytes[frame + 9].should eq(4) # four components
    image = Vision::Image.from_jpeg(bytes)
    image.channels.should eq(3)
    largest_difference(image, Vision::Image.from_ppm(fixture("cmyk.ppm"))).should be <= 2
    # And it is the picture that was saved, within what JPEG loses.
    original = Vision::Image.from_png(fixture("scene.png"))
    differences = original.data.zip(image.data).map { |x, y| (x.to_i - y.to_i).abs }
    (differences.sum / differences.size).should be < 4.0
  end

  it "converts a YCCK file with subsampled components" do
    bytes = fixture("ycck_subsampled.jpg")
    # Adobe's marker with transform 2: the first three components are YCbCr.
    adobe = (0...bytes.size - 1).find! { |i| bytes[i] == 0xFF && bytes[i + 1] == 0xEE }
    String.new(bytes[adobe + 4, 5]).should eq("Adobe")
    bytes[adobe + 15].should eq(2)
    image = Vision::Image.from_jpeg(bytes)
    largest_difference(image, Vision::Image.from_ppm(fixture("ycck_subsampled.ppm"))).should be <= 3
  end

  it "reads ink the other way round without Adobe's marker" do
    bytes = fixture("cmyk.jpg")
    with_marker = Vision::Image.from_jpeg(bytes)
    # Rename the Adobe segment to a comment: the same samples now mean
    # ink, not light, so the pale background comes out dark.
    plain = bytes.dup
    adobe = (0...plain.size - 1).find! { |i| plain[i] == 0xFF && plain[i + 1] == 0xEE }
    plain[adobe + 1] = 0xFE_u8
    without_marker = Vision::Image.from_jpeg(plain)
    with_marker.rgb(0, 0).each { |value| value.should be > 200 }
    without_marker.rgb(0, 0).each { |value| value.should be < 10 }
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
    jpeg = fixture("scene_420.jpg")
    frame = (0...jpeg.size - 1).find! { |i| jpeg[i] == 0xFF && jpeg[i + 1] == 0xC0 }
    # The same file with its frame marked as arithmetic-coded, then as hierarchical.
    {0xC9_u8 => "arithmetic-coded JPEG is not supported", 0xC5_u8 => "hierarchical JPEG is not supported"}.each do |marker, message|
      other = jpeg.dup
      other[frame + 1] = marker
      expect_raises(Vision::ImageError, message) { Vision::Image.from_jpeg(other) }
    end
    # Ten bits per sample.
    deep = jpeg.dup
    deep[frame + 4] = 10_u8
    expect_raises(Vision::ImageError, "JPEG with 10 bits per sample is not supported") { Vision::Image.from_jpeg(deep) }
    # Twelve bits in a progressive frame.
    progressive = fixture("progressive_444.jpg")
    start = (0...progressive.size - 1).find! { |i| progressive[i] == 0xFF && progressive[i + 1] == 0xC2 }
    progressive[start + 4] = 12_u8
    expect_raises(Vision::ImageError, "12-bit progressive JPEG is not supported") { Vision::Image.from_jpeg(progressive) }
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

    # A frame that claims five components.
    five = jpeg.dup
    frame = (0...five.size - 1).find! { |i| five[i] == 0xFF && five[i + 1] == 0xC0 }
    five[frame + 9] = 5_u8
    expect_raises(Vision::ImageError, "5 components is not supported") { Vision::Image.from_jpeg(five) }
    # Four, with a header that only describes three.
    four = jpeg.dup
    four[frame + 9] = 4_u8
    expect_raises(Vision::ImageError, "truncated JPEG frame header") { Vision::Image.from_jpeg(four) }
  end
end

# The files in this part were written by libjpeg-turbo 3. Those it has no
# option for (restart intervals, a point transform, subsampled components
# and one component per scan in a lossless file) were written by a small
# encoder made from the standard, and libjpeg-turbo decoded each back to
# exactly what was encoded. Every reference is libjpeg-turbo's decode,
# brought to 8 bits as (v * 255 + max / 2) / max.
private def frame_of(bytes : Bytes, marker : UInt8) : Int32
  (0...bytes.size - 1).find! { |i| bytes[i] == 0xFF && bytes[i + 1] == marker }
end

private def reference(name : String) : Vision::Image
  path = File.join(FIXTURES, "#{name}.ppm")
  Vision::Image.from_ppm(fixture(File.exists?(path) ? "#{name}.ppm" : "#{name}.pgm"))
end

describe "Vision::JPEG lossless" do
  (1..7).each do |predictor|
    it "decodes predictor #{predictor} exactly" do
      bytes = fixture("lossless_p#{predictor}.jpg")
      sof = frame_of(bytes, 0xC3_u8)
      bytes[sof + 4].should eq(8)
      scan = frame_of(bytes, 0xDA_u8)
      bytes[scan + 11].should eq(predictor) # the scan's spectral start
      image = Vision::Image.from_jpeg(bytes)
      image.channels.should eq(3)
      largest_difference(image, reference("lossless_p#{predictor}")).should eq(0)
    end
  end

  {
    "lossless_gray"    => "grayscale",
    "lossless_gray12"  => "12-bit grayscale",
    "lossless_gray16"  => "16-bit grayscale",
    "lossless_rgb12"   => "12-bit colour",
    "lossless_restart" => "restart markers every two lines",
    "lossless_point"   => "a point transform of three, 12 bits, a restart every line",
    "lossless_sub"     => "a full-resolution component beside two halved both ways",
    "lossless_planar"  => "one component per scan",
  }.each do |name, what|
    it "decodes #{name} (#{what}) exactly" do
      largest_difference(Vision::Image.from_jpeg(fixture("#{name}.jpg")), reference(name)).should eq(0)
    end
  end

  it "is the picture that was encoded" do
    original = Vision::Image.from_png(fixture("scene.png"))
    Vision::Image.from_jpeg(fixture("lossless_p4.jpg")).should eq(original)
    Vision::Image.from_jpeg(fixture("lossless_restart.jpg")).should eq(original)
    Vision::Image.from_jpeg(fixture("lossless_planar.jpg")).should eq(original)
  end

  it "keeps the low bits of deep samples" do
    # The 12-bit file's samples were spread with a pattern in their low
    # four bits, which the 8-bit picture then shows in its last bit or two.
    deep = Vision::Image.from_jpeg(fixture("lossless_gray12.jpg"))
    eight = Vision::Image.from_jpeg(fixture("lossless_gray.jpg"))
    largest_difference(deep, eight).should be > 0
    largest_difference(deep, eight).should be <= 2
  end

  it "refuses what a lossless file cannot hold" do
    bytes = fixture("lossless_gray.jpg")
    scan = frame_of(bytes, 0xDA_u8)
    no_predictor = bytes.dup
    no_predictor[scan + 7] = 0_u8
    expect_raises(Vision::ImageError, "lossless JPEG predictor 0 is not valid") { Vision::Image.from_jpeg(no_predictor) }
    too_far = bytes.dup
    too_far[scan + 9] = 8_u8 # point transform as large as the precision
    expect_raises(Vision::ImageError, "point transform 8 is too large") { Vision::Image.from_jpeg(too_far) }
    shallow = bytes.dup
    shallow[frame_of(bytes, 0xC3_u8) + 4] = 1_u8
    expect_raises(Vision::ImageError, "lossless JPEG with 1 bits per sample is not valid") { Vision::Image.from_jpeg(shallow) }
  end
end

describe "Vision::JPEG 12-bit" do
  {
    "deep12_gray" => "grayscale",
    "deep12_444"  => "full-resolution chroma",
    "deep12_420"  => "chroma halved both ways",
  }.each do |name, what|
    it "decodes #{name} (#{what})" do
      bytes = fixture("#{name}.jpg")
      sof = frame_of(bytes, 0xC1_u8)
      bytes[sof + 4].should eq(12)
      image = Vision::Image.from_jpeg(bytes)
      largest_difference(image, reference(name)).should be <= 3
    end
  end

  it "stays close to the picture that was compressed" do
    original = Vision::Image.from_png(fixture("scene.png"))
    decoded = Vision::Image.from_jpeg(fixture("deep12_444.jpg"))
    differences = original.data.zip(decoded.data).map { |x, y| (x.to_i - y.to_i).abs }
    (differences.sum / differences.size).should be < 4.0
  end
end
