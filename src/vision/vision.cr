# Vision: perception for CrystalCog.
#
#   image.cr       images, PNG and PPM/PGM codecs, filters
#   perception.cr  colour naming, regions, shapes, relations, motion
#   vision.cr      scenes, and their grounding in the AtomSpace
#
# A scene is what one image shows. Grounding writes it into the AtomSpace
# so that reasoning and queries can use what was seen:
#
#   (MemberLink (Concept "kitchen:object-1") (Concept "scene:kitchen"))
#   (InheritanceLink (Concept "kitchen:object-1") (Concept "circle"))
#   (Evaluation (Predicate "color") (List (Concept "kitchen:object-1") (Concept "red")))
#   (Evaluation (Predicate "position") (List (Concept "kitchen:object-1") (Number 0.25) (Number 0.5)))
#   (Evaluation (Predicate "left-of") (List (Concept "kitchen:object-1") (Concept "kitchen:object-2")))

require "../atomspace/atomspace_main"
require "./perception"

module Vision
  VERSION = "0.1.0"

  class Scene
    getter name : String
    getter width : Int32
    getter height : Int32
    getter detections : Array(Detection)
    getter relations : Array(Relation)

    def initialize(@name : String, @width : Int32, @height : Int32, @detections : Array(Detection),
                   @relations : Array(Relation))
    end

    def describe : String
      Vision.describe(@detections, @relations, @width, @height)
    end

    def object_name(id : Int32) : String
      "#{@name}:object-#{id}"
    end

    # Write the scene into the AtomSpace; returns the atoms that state it.
    # Positions are the object's centre as fractions of the image size, and
    # area is its share of the image, so they do not depend on resolution.
    def ground(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom
      scene = atomspace.add_concept_node("scene:#{@name}")
      color = atomspace.add_predicate_node("color")
      position = atomspace.add_predicate_node("position")
      area = atomspace.add_predicate_node("area")

      nodes = {} of Int32 => AtomSpace::Atom
      @detections.each do |d|
        object = atomspace.add_concept_node(object_name(d.id))
        nodes[d.id] = object
        atoms << atomspace.add_link(AtomSpace::AtomType::MEMBER_LINK, [object, scene])
        atoms << atomspace.add_inheritance_link(object, atomspace.add_concept_node(d.shape),
          AtomSpace::SimpleTruthValue.new(d.confidence, 0.9))
        atoms << atomspace.add_evaluation_link(color, atomspace.add_list_link([object, atomspace.add_concept_node(d.color)]))
        x = number(atomspace, d.center_x / @width)
        y = number(atomspace, d.center_y / @height)
        atoms << atomspace.add_evaluation_link(position, atomspace.add_list_link([object, x, y]))
        share = number(atomspace, d.area.to_f / (@width.to_i64 * @height))
        atoms << atomspace.add_evaluation_link(area, atomspace.add_list_link([object, share]))
      end

      @relations.each do |relation|
        subject = nodes[relation.subject]? || next
        object = nodes[relation.object]? || next
        predicate = atomspace.add_predicate_node(relation.name)
        atoms << atomspace.add_evaluation_link(predicate, atomspace.add_list_link([subject, object]))
      end
      atoms
    end

    private def number(atomspace : AtomSpace::AtomSpace, value : Float64) : AtomSpace::Atom
      atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, value.round(3).to_s)
    end
  end

  # Look at an image: find its objects and how they relate.
  def self.perceive(image : Image, name : String = "scene", min_area : Int32? = nil) : Scene
    detections = detect_objects(image, min_area)
    Scene.new(name, image.width, image.height, detections, relations(detections))
  end

  # Look at an image file (PNG, PGM or PPM).
  def self.perceive_file(path : String, name : String? = nil) : Scene
    perceive(Image.load(path), name || File.basename(path, File.extname(path)))
  end
end
