# Spatial Reasoning for CrystalCog Robotics
#
# This module implements spatial reasoning and representation capabilities,
# enabling agents to reason about positions, orientations, distances, and
# spatial relationships in 2D and 3D environments.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Robotics
  module SpatialReasoning
    VERSION = "0.1.0"

    class SpatialException < Exception
    end

    # 3D position in space
    struct Position
      getter x : Float64
      getter y : Float64
      getter z : Float64

      def initialize(@x : Float64, @y : Float64, @z : Float64 = 0.0)
      end

      def distance_to(other : Position) : Float64
        Math.sqrt(
          (@x - other.x) ** 2 +
          (@y - other.y) ** 2 +
          (@z - other.z) ** 2
        )
      end

      def +(other : Position) : Position
        Position.new(@x + other.x, @y + other.y, @z + other.z)
      end

      def -(other : Position) : Position
        Position.new(@x - other.x, @y - other.y, @z - other.z)
      end

      def *(scalar : Float64) : Position
        Position.new(@x * scalar, @y * scalar, @z * scalar)
      end

      def magnitude : Float64
        Math.sqrt(@x ** 2 + @y ** 2 + @z ** 2)
      end

      def normalize : Position
        mag = magnitude
        return Position.new(0.0, 0.0, 0.0) if mag == 0.0
        Position.new(@x / mag, @y / mag, @z / mag)
      end

      def to_s : String
        "(#{@x.round(3)}, #{@y.round(3)}, #{@z.round(3)})"
      end
    end

    # 3D orientation using Euler angles (radians)
    struct Orientation
      getter roll : Float64  # rotation around x-axis
      getter pitch : Float64 # rotation around y-axis
      getter yaw : Float64   # rotation around z-axis

      def initialize(@roll : Float64 = 0.0, @pitch : Float64 = 0.0, @yaw : Float64 = 0.0)
      end

      def to_s : String
        "(roll=#{@roll.round(3)}, pitch=#{@pitch.round(3)}, yaw=#{@yaw.round(3)})"
      end
    end

    # Pose combines position and orientation
    struct Pose
      getter position : Position
      getter orientation : Orientation

      def initialize(@position : Position, @orientation : Orientation = Orientation.new)
      end

      def to_s : String
        "pos=#{@position} orient=#{@orientation}"
      end
    end

    # Bounding box for an object in space
    struct BoundingBox
      getter min : Position
      getter max : Position

      def initialize(@min : Position, @max : Position)
      end

      def contains?(pos : Position) : Bool
        pos.x >= @min.x && pos.x <= @max.x &&
          pos.y >= @min.y && pos.y <= @max.y &&
          pos.z >= @min.z && pos.z <= @max.z
      end

      def center : Position
        Position.new(
          (@min.x + @max.x) / 2.0,
          (@min.y + @max.y) / 2.0,
          (@min.z + @max.z) / 2.0
        )
      end

      def intersects?(other : BoundingBox) : Bool
        @min.x <= other.max.x && @max.x >= other.min.x &&
          @min.y <= other.max.y && @max.y >= other.min.y &&
          @min.z <= other.max.z && @max.z >= other.min.z
      end
    end

    # Represents an entity in the spatial map
    class SpatialEntity
      getter id : String
      getter name : String
      property pose : Pose
      property bounding_box : BoundingBox?
      property properties : Hash(String, String)

      def initialize(@id : String, @name : String, @pose : Pose)
        @bounding_box = nil
        @properties = {} of String => String
      end

      def position : Position
        @pose.position
      end

      def distance_to(other : SpatialEntity) : Float64
        position.distance_to(other.position)
      end
    end

    # Spatial relationship types
    enum SpatialRelation
      NEAR
      FAR
      LEFT_OF
      RIGHT_OF
      IN_FRONT_OF
      BEHIND
      ABOVE
      BELOW
      INSIDE
      OUTSIDE
      TOUCHING
      OVERLAPPING
    end

    # Manages spatial knowledge about the environment
    class SpatialMap
      getter entities : Hash(String, SpatialEntity)

      NEAR_THRESHOLD = 2.0

      def initialize
        @entities = {} of String => SpatialEntity
        CogUtil::Logger.info("SpatialMap initialized")
      end

      def add_entity(entity : SpatialEntity)
        @entities[entity.id] = entity
        CogUtil::Logger.debug("Added entity '#{entity.name}' at #{entity.position}")
      end

      def remove_entity(id : String) : Bool
        if @entities.has_key?(id)
          @entities.delete(id)
          true
        else
          false
        end
      end

      def get_entity(id : String) : SpatialEntity?
        @entities[id]?
      end

      def update_pose(id : String, pose : Pose) : Bool
        entity = @entities[id]?
        return false unless entity
        entity.pose = pose
        true
      end

      # Find entities within a radius
      def entities_within_radius(center : Position, radius : Float64) : Array(SpatialEntity)
        @entities.values.select { |e| e.position.distance_to(center) <= radius }
      end

      # Find the nearest entity to a position
      def nearest_entity(pos : Position, exclude_id : String? = nil) : SpatialEntity?
        candidates = @entities.values
        candidates = candidates.reject { |e| e.id == exclude_id } if exclude_id
        candidates.min_by? { |e| e.position.distance_to(pos) }
      end

      # Compute spatial relation between two entities
      def relation_between(id1 : String, id2 : String) : SpatialRelation?
        e1 = @entities[id1]?
        e2 = @entities[id2]?
        return nil unless e1 && e2

        compute_relation(e1, e2)
      end

      # Store spatial knowledge in AtomSpace
      def to_atomspace(atomspace : AtomSpace::AtomSpace)
        @entities.each do |id, entity|
          # Create entity node
          entity_node = atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            entity.name
          )

          # Add position properties
          pos = entity.position
          atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            "position_#{id}_(#{pos.x.round(2)},#{pos.y.round(2)},#{pos.z.round(2)})"
          )
        end

        # Add spatial relations
        @entities.each do |id1, e1|
          @entities.each do |id2, e2|
            next if id1 >= id2
            rel = compute_relation(e1, e2)
            add_relation_to_atomspace(atomspace, e1.name, e2.name, rel)
          end
        end
      end

      private def compute_relation(e1 : SpatialEntity, e2 : SpatialEntity) : SpatialRelation
        diff = e2.position - e1.position
        dist = e1.distance_to(e2)

        # Check bounding boxes for overlap/inside
        bb1 = e1.bounding_box
        bb2 = e2.bounding_box
        if bb1 && bb2
          return SpatialRelation::OVERLAPPING if bb1.intersects?(bb2)
          return SpatialRelation::INSIDE if bb1.contains?(e2.position)
        end

        return SpatialRelation::NEAR if dist <= NEAR_THRESHOLD

        # Determine dominant direction
        if diff.z.abs > diff.x.abs && diff.z.abs > diff.y.abs
          diff.z > 0 ? SpatialRelation::ABOVE : SpatialRelation::BELOW
        elsif diff.x.abs > diff.y.abs
          diff.x > 0 ? SpatialRelation::RIGHT_OF : SpatialRelation::LEFT_OF
        else
          diff.y > 0 ? SpatialRelation::IN_FRONT_OF : SpatialRelation::BEHIND
        end
      end

      private def add_relation_to_atomspace(atomspace : AtomSpace::AtomSpace, name1 : String, name2 : String, rel : SpatialRelation)
        n1 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, name1)
        n2 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, name2)
        pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, rel.to_s.downcase)
        list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [n1, n2])
        atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [pred, list])
      end
    end
  end
end
