# Spatial Reasoning Module for CrystalCog
#
# This module provides spatial reasoning capabilities including:
# - 3D coordinate systems and transformations
# - Spatial relationships (above, below, near, inside, etc.)
# - Navigation and pathfinding algorithms
# - Spatial indexing for efficient queries
#
# References:
# - Qualitative Spatial Reasoning: https://en.wikipedia.org/wiki/Qualitative_spatial_reasoning
# - Region Connection Calculus (RCC): Randell, Cui, Cohn 1992

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Spatial
  VERSION = "0.1.0"

  # Exception classes
  class SpatialException < Exception
  end

  class InvalidCoordinateException < SpatialException
  end

  class PathNotFoundException < SpatialException
  end

  # 3D Vector representation
  struct Vector3
    property x : Float64
    property y : Float64
    property z : Float64

    def initialize(@x : Float64 = 0.0, @y : Float64 = 0.0, @z : Float64 = 0.0)
    end

    def +(other : Vector3) : Vector3
      Vector3.new(@x + other.x, @y + other.y, @z + other.z)
    end

    def -(other : Vector3) : Vector3
      Vector3.new(@x - other.x, @y - other.y, @z - other.z)
    end

    def *(scalar : Float64) : Vector3
      Vector3.new(@x * scalar, @y * scalar, @z * scalar)
    end

    def /(scalar : Float64) : Vector3
      raise InvalidCoordinateException.new("Division by zero") if scalar == 0.0
      Vector3.new(@x / scalar, @y / scalar, @z / scalar)
    end

    def magnitude : Float64
      Math.sqrt(@x * @x + @y * @y + @z * @z)
    end

    def normalized : Vector3
      mag = magnitude
      return Vector3.new if mag == 0.0
      self / mag
    end

    def distance_to(other : Vector3) : Float64
      (self - other).magnitude
    end

    def dot(other : Vector3) : Float64
      @x * other.x + @y * other.y + @z * other.z
    end

    def cross(other : Vector3) : Vector3
      Vector3.new(
        @y * other.z - @z * other.y,
        @z * other.x - @x * other.z,
        @x * other.y - @y * other.x
      )
    end

    def to_s(io : IO)
      io << "(#{@x}, #{@y}, #{@z})"
    end

    def ==(other : Vector3) : Bool
      (@x - other.x).abs < 1e-10 &&
        (@y - other.y).abs < 1e-10 &&
        (@z - other.z).abs < 1e-10
    end
  end

  # Axis-aligned bounding box
  struct BoundingBox
    property min : Vector3
    property max : Vector3

    def initialize(@min : Vector3, @max : Vector3)
    end

    def self.from_center(center : Vector3, size : Vector3) : BoundingBox
      half = size / 2.0
      new(center - half, center + half)
    end

    def center : Vector3
      (@min + @max) / 2.0
    end

    def size : Vector3
      @max - @min
    end

    def contains?(point : Vector3) : Bool
      point.x >= @min.x && point.x <= @max.x &&
        point.y >= @min.y && point.y <= @max.y &&
        point.z >= @min.z && point.z <= @max.z
    end

    def intersects?(other : BoundingBox) : Bool
      @min.x <= other.max.x && @max.x >= other.min.x &&
        @min.y <= other.max.y && @max.y >= other.min.y &&
        @min.z <= other.max.z && @max.z >= other.min.z
    end

    def expand(point : Vector3) : BoundingBox
      BoundingBox.new(
        Vector3.new(
          Math.min(@min.x, point.x),
          Math.min(@min.y, point.y),
          Math.min(@min.z, point.z)
        ),
        Vector3.new(
          Math.max(@max.x, point.x),
          Math.max(@max.y, point.y),
          Math.max(@max.z, point.z)
        )
      )
    end
  end

  # Spatial relationship types (based on RCC-8)
  enum SpatialRelation
    DISCONNECTED           # DC: No contact
    EXTERNALLY_CONNECTED   # EC: Touch at boundary
    PARTIALLY_OVERLAPPING  # PO: Overlap but neither contains other
    EQUAL                  # EQ: Identical regions
    TANGENTIAL_PROPER_PART # TPP: Inside, touching boundary
    NON_TANGENTIAL_PROPER_PART # NTPP: Completely inside
    TANGENTIAL_PROPER_PART_INVERSE # TPPi: Contains, touching boundary
    NON_TANGENTIAL_PROPER_PART_INVERSE # NTPPi: Completely contains

    # Additional relations for positioning
    ABOVE
    BELOW
    LEFT_OF
    RIGHT_OF
    IN_FRONT_OF
    BEHIND
    NEAR
    FAR
  end

  # Represents a spatial object with position and extent
  class SpatialObject
    property id : String
    property position : Vector3
    property bounds : BoundingBox
    property velocity : Vector3
    property orientation : Vector3  # Euler angles (pitch, yaw, roll)
    property properties : Hash(String, String | Float64 | Bool)

    def initialize(@id : String, @position : Vector3,
                   bounds_size : Vector3 = Vector3.new(1.0, 1.0, 1.0))
      @bounds = BoundingBox.from_center(@position, bounds_size)
      @velocity = Vector3.new
      @orientation = Vector3.new
      @properties = {} of String => String | Float64 | Bool
    end

    def update_position(new_position : Vector3)
      offset = new_position - @position
      @position = new_position
      @bounds = BoundingBox.new(@bounds.min + offset, @bounds.max + offset)
    end

    def distance_to(other : SpatialObject) : Float64
      @position.distance_to(other.position)
    end

    def is_near?(other : SpatialObject, threshold : Float64 = 5.0) : Bool
      distance_to(other) <= threshold
    end

    # Convert to AtomSpace representation
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      # Create object node
      obj_node = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        @id
      )
      atoms << obj_node

      # Add position as evaluation link
      pos_pred = atomspace.add_node(
        AtomSpace::AtomType::PREDICATE_NODE,
        "has_position"
      )

      pos_value = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        "(#{@position.x}, #{@position.y}, #{@position.z})"
      )

      pos_link = atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [pos_pred, atomspace.add_link(
          AtomSpace::AtomType::LIST_LINK,
          [obj_node, pos_value]
        )]
      )
      atoms << pos_link

      atoms
    end
  end

  # Spatial map for managing objects and querying relationships
  class SpatialMap
    getter objects : Hash(String, SpatialObject)
    getter grid_size : Float64
    getter spatial_index : Hash(Tuple(Int32, Int32, Int32), Array(String))

    def initialize(@grid_size : Float64 = 10.0)
      @objects = {} of String => SpatialObject
      @spatial_index = {} of Tuple(Int32, Int32, Int32) => Array(String)
      CogUtil::Logger.info("SpatialMap initialized with grid size #{@grid_size}")
    end

    # Add object to map
    def add_object(obj : SpatialObject)
      @objects[obj.id] = obj
      index_object(obj)
      CogUtil::Logger.debug("Added spatial object: #{obj.id}")
    end

    # Remove object from map
    def remove_object(id : String)
      if obj = @objects.delete(id)
        unindex_object(obj)
      end
    end

    # Get object by ID
    def get_object(id : String) : SpatialObject?
      @objects[id]?
    end

    # Find objects within radius
    def find_nearby(position : Vector3, radius : Float64) : Array(SpatialObject)
      result = [] of SpatialObject

      # Calculate grid cells to check
      min_cell = position_to_cell(position - Vector3.new(radius, radius, radius))
      max_cell = position_to_cell(position + Vector3.new(radius, radius, radius))

      (min_cell[0]..max_cell[0]).each do |x|
        (min_cell[1]..max_cell[1]).each do |y|
          (min_cell[2]..max_cell[2]).each do |z|
            cell = {x, y, z}
            if ids = @spatial_index[cell]?
              ids.each do |id|
                if obj = @objects[id]?
                  if obj.position.distance_to(position) <= radius
                    result << obj
                  end
                end
              end
            end
          end
        end
      end

      result
    end

    # Find objects in bounding box
    def find_in_bounds(bounds : BoundingBox) : Array(SpatialObject)
      result = [] of SpatialObject

      min_cell = position_to_cell(bounds.min)
      max_cell = position_to_cell(bounds.max)

      (min_cell[0]..max_cell[0]).each do |x|
        (min_cell[1]..max_cell[1]).each do |y|
          (min_cell[2]..max_cell[2]).each do |z|
            cell = {x, y, z}
            if ids = @spatial_index[cell]?
              ids.each do |id|
                if obj = @objects[id]?
                  if bounds.contains?(obj.position)
                    result << obj
                  end
                end
              end
            end
          end
        end
      end

      result
    end

    # Compute spatial relationship between two objects
    def get_relation(obj1 : SpatialObject, obj2 : SpatialObject) : SpatialRelation
      distance = obj1.distance_to(obj2)

      # Check if objects' bounds intersect
      if obj1.bounds.intersects?(obj2.bounds)
        if obj1.bounds.contains?(obj2.position) && obj2.bounds.contains?(obj1.position)
          return SpatialRelation::EQUAL
        elsif obj1.bounds.contains?(obj2.position)
          return SpatialRelation::NON_TANGENTIAL_PROPER_PART_INVERSE
        elsif obj2.bounds.contains?(obj1.position)
          return SpatialRelation::NON_TANGENTIAL_PROPER_PART
        else
          return SpatialRelation::PARTIALLY_OVERLAPPING
        end
      end

      # Directional relationships
      diff = obj2.position - obj1.position

      if diff.y.abs > diff.x.abs && diff.y.abs > diff.z.abs
        return diff.y > 0 ? SpatialRelation::ABOVE : SpatialRelation::BELOW
      elsif diff.x.abs > diff.z.abs
        return diff.x > 0 ? SpatialRelation::RIGHT_OF : SpatialRelation::LEFT_OF
      else
        return diff.z > 0 ? SpatialRelation::IN_FRONT_OF : SpatialRelation::BEHIND
      end
    end

    # Find all relationships for an object
    def get_all_relations(obj_id : String) : Array(Tuple(String, SpatialRelation))
      relations = [] of Tuple(String, SpatialRelation)

      if obj = @objects[obj_id]?
        @objects.each do |id, other|
          next if id == obj_id
          relation = get_relation(obj, other)
          relations << {id, relation}
        end
      end

      relations
    end

    # Convert entire map to AtomSpace
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      @objects.each_value do |obj|
        atoms.concat(obj.to_atomspace(atomspace))
      end

      # Add spatial relationships
      @objects.each do |id1, obj1|
        @objects.each do |id2, obj2|
          next if id1 >= id2  # Avoid duplicates

          relation = get_relation(obj1, obj2)
          atoms.concat(create_relation_atoms(atomspace, obj1, obj2, relation))
        end
      end

      atoms
    end

    private def position_to_cell(pos : Vector3) : Tuple(Int32, Int32, Int32)
      {
        (pos.x / @grid_size).floor.to_i,
        (pos.y / @grid_size).floor.to_i,
        (pos.z / @grid_size).floor.to_i,
      }
    end

    private def index_object(obj : SpatialObject)
      cell = position_to_cell(obj.position)
      @spatial_index[cell] ||= [] of String
      @spatial_index[cell] << obj.id unless @spatial_index[cell].includes?(obj.id)
    end

    private def unindex_object(obj : SpatialObject)
      cell = position_to_cell(obj.position)
      if ids = @spatial_index[cell]?
        ids.delete(obj.id)
      end
    end

    private def create_relation_atoms(atomspace : AtomSpace::AtomSpace,
                                      obj1 : SpatialObject, obj2 : SpatialObject,
                                      relation : SpatialRelation) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      obj1_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, obj1.id)
      obj2_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, obj2.id)
      relation_node = atomspace.add_node(
        AtomSpace::AtomType::PREDICATE_NODE,
        relation.to_s.downcase
      )

      eval_link = atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [relation_node, atomspace.add_link(
          AtomSpace::AtomType::LIST_LINK,
          [obj1_node, obj2_node]
        )]
      )
      atoms << eval_link

      atoms
    end
  end

  # A* pathfinding algorithm
  class Pathfinder
    getter spatial_map : SpatialMap
    getter obstacles : Set(String)
    getter step_size : Float64

    def initialize(@spatial_map : SpatialMap, @step_size : Float64 = 1.0)
      @obstacles = Set(String).new
    end

    def add_obstacle(id : String)
      @obstacles.add(id)
    end

    def remove_obstacle(id : String)
      @obstacles.delete(id)
    end

    # Find path using A* algorithm
    def find_path(start : Vector3, goal : Vector3, max_iterations : Int32 = 1000) : Array(Vector3)?
      CogUtil::Logger.debug("Finding path from #{start} to #{goal}")

      open_set = [{start, 0.0, heuristic(start, goal)}]
      came_from = {} of Vector3 => Vector3
      g_score = {start => 0.0}
      f_score = {start => heuristic(start, goal)}

      iterations = 0

      while !open_set.empty? && iterations < max_iterations
        iterations += 1

        # Get node with lowest f_score
        open_set.sort_by! { |n| n[2] }
        current, _, _ = open_set.shift

        if current.distance_to(goal) < @step_size
          return reconstruct_path(came_from, current, goal)
        end

        # Expand neighbors
        get_neighbors(current).each do |neighbor|
          tentative_g = g_score[current] + current.distance_to(neighbor)

          if tentative_g < (g_score[neighbor]? || Float64::INFINITY)
            came_from[neighbor] = current
            g_score[neighbor] = tentative_g
            f = tentative_g + heuristic(neighbor, goal)
            f_score[neighbor] = f

            unless open_set.any? { |n| n[0] == neighbor }
              open_set << {neighbor, tentative_g, f}
            end
          end
        end
      end

      CogUtil::Logger.warn("Path not found after #{iterations} iterations")
      nil
    end

    private def heuristic(a : Vector3, b : Vector3) : Float64
      a.distance_to(b)
    end

    private def get_neighbors(pos : Vector3) : Array(Vector3)
      neighbors = [] of Vector3

      # 6-connected (cardinal directions)
      directions = [
        Vector3.new(@step_size, 0.0, 0.0),
        Vector3.new(-@step_size, 0.0, 0.0),
        Vector3.new(0.0, @step_size, 0.0),
        Vector3.new(0.0, -@step_size, 0.0),
        Vector3.new(0.0, 0.0, @step_size),
        Vector3.new(0.0, 0.0, -@step_size),
      ]

      directions.each do |dir|
        neighbor = pos + dir
        neighbors << neighbor unless is_blocked?(neighbor)
      end

      neighbors
    end

    private def is_blocked?(pos : Vector3) : Bool
      @obstacles.any? do |id|
        if obj = @spatial_map.get_object(id)
          obj.bounds.contains?(pos)
        else
          false
        end
      end
    end

    private def reconstruct_path(came_from : Hash(Vector3, Vector3),
                                 current : Vector3, goal : Vector3) : Array(Vector3)
      path = [goal, current]

      while came_from.has_key?(current)
        current = came_from[current]
        path << current
      end

      path.reverse
    end
  end

  # Module-level convenience methods
  def self.create_map(grid_size : Float64 = 10.0) : SpatialMap
    SpatialMap.new(grid_size)
  end

  def self.create_object(id : String, x : Float64, y : Float64, z : Float64) : SpatialObject
    SpatialObject.new(id, Vector3.new(x, y, z))
  end

  def self.distance(obj1 : SpatialObject, obj2 : SpatialObject) : Float64
    obj1.distance_to(obj2)
  end
end
