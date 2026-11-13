# Vision

`src/vision` lets CrystalCog look at images. It is pure Crystal: no image library is needed.

| File | What it does |
|---|---|
| `image.cr` | `Vision::Image`: 8-bit gray or RGB pixels. Reads and writes PNG and PPM/PGM. Filters: gray, Gaussian blur, Sobel edges, Otsu threshold, resize, crop. |
| `perception.cr` | Colour naming, connected regions, shape classification, spatial relations, motion between frames. |
| `vision.cr` | `Vision::Scene` and its grounding in the AtomSpace. |

## Looking at an image

```bash
crystalcog cog --atomspace kb.json see desk.png desk
```

```
3 objects: red circle #1 at the middle left (81x81 px, 8.1% of the image); blue square #2 at the
middle centre (70x70 px, 7.7% of the image); green triangle #3 at the middle right (...).
red circle #1 is left of blue square #2; ...
Added 22 atom(s) about scene:desk
```

The same command works in `crystalcog shell`, over the CogServer's telnet and WebSocket interfaces, and as `/see` in chat. A chat model can call it as the `see_image` tool.

From code:

```crystal
scene = Vision.perceive(Vision::Image.load("desk.png"), "desk")
scene.detections.each { |d| puts "#{d.label} at #{d.center_x}, #{d.center_y}" }
scene.ground(atomspace)
```

## What it finds

- **Objects:** the colour that dominates the image border is the background. Every other connected patch of one colour, at least 0.05% of the image, is an object.
- **Colours:** black, gray, white, red, orange, yellow, green, cyan, blue, purple, pink.
- **Shapes,** from how a region fills its bounding box:
  - square or rectangle: fills the box
  - circle or ellipse: fills about pi/4 of it
  - triangle: fills about half, with its mass off-centre
  - diamond: fills about half, centred
  - blob: anything else
- **Relations:** `left-of`, `above`, `inside`, `near`, `larger-than`.
- **Motion:** `Vision.motion(previous, current)` returns the regions that changed between two frames.

This is classical image processing. It handles flat-coloured shapes on a plain background, such as diagrams, simulated scenes and simple camera views. It does not recognise photographs of real objects.

## In the AtomSpace

```
(MemberLink (Concept "desk:object-1") (Concept "scene:desk"))
(InheritanceLink (Concept "desk:object-1") (Concept "circle"))
(Evaluation (Predicate "color")    (List (Concept "desk:object-1") (Concept "red")))
(Evaluation (Predicate "position") (List (Concept "desk:object-1") (Number 0.219) (Number 0.5)))
(Evaluation (Predicate "area")     (List (Concept "desk:object-1") (Number 0.081)))
(Evaluation (Predicate "left-of")  (List (Concept "desk:object-1") (Concept "desk:object-2")))
```

Positions are the object's centre as fractions of the image width and height; area is its share of the image. The pattern matcher and PLN can then answer questions such as "what is the red thing to the left of?".

## Image formats

- **PNG:** grayscale, RGB, palette, gray+alpha and RGBA, at 1 to 16 bits per sample, non-interlaced. Alpha is composited over white. 16-bit samples keep their high byte. Interlaced PNGs are not supported.
- **PPM/PGM:** binary (P5, P6) and ASCII (P2, P3).
- **Raw frames:** `Vision::Image.from_raw` takes the ROS encodings `rgb8`, `bgr8`, `rgba8`, `bgra8` and `mono8`.

## Robot camera

`Robotics::VisionSensor` uses this module. After `set_image_data(bytes, encoding)` or `set_image(image)`, a reading includes `brightness`, `object_count`, `objects`, `description` and `bearings` (each object's horizontal angle from the optical axis, in radians). `perceive_into(atomspace)` grounds the current frame.
