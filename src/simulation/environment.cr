# Simulation Environment Abstraction
#
# Provides the core interface and implementations for simulation environments.
# Supports both local simulation and external simulators.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Simulation
  # 3D Vector for positions, velocities, etc.
  struct Vector3
    getter x : Float64
    getter y : Float64
    getter z : Float64

    def initialize(@x : Float64 = 0.0, @y : Float64 = 0.0, @z : Float64 = 0.0)
    end

    def self.zero : Vector3
      Vector3.new(0.0, 0.0, 0.0)
    end

    def self.one : Vector3
      Vector3.new(1.0, 1.0, 1.0)
    end

    def self.up : Vector3
      Vector3.new(0.0, 1.0, 0.0)
    end

    def self.forward : Vector3
      Vector3.new(0.0, 0.0, 1.0)
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
      return Vector3.zero if scalar == 0.0
      Vector3.new(@x / scalar, @y / scalar, @z / scalar)
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

    def magnitude : Float64
      Math.sqrt(@x * @x + @y * @y + @z * @z)
    end

    def magnitude_squared : Float64
      @x * @x + @y * @y + @z * @z
    end

    def normalized : Vector3
      mag = magnitude
      return Vector3.zero if mag == 0.0
      self / mag
    end

    def distance_to(other : Vector3) : Float64
      (self - other).magnitude
    end

    def lerp(other : Vector3, t : Float64) : Vector3
      self + (other - self) * t.clamp(0.0, 1.0)
    end

    def to_s : String
      "(#{@x}, #{@y}, #{@z})"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "x", @x
        json.field "y", @y
        json.field "z", @z
      end
    end
  end

  # Quaternion for rotations
  struct Quaternion
    getter x : Float64
    getter y : Float64
    getter z : Float64
    getter w : Float64

    def initialize(@x : Float64 = 0.0, @y : Float64 = 0.0, @z : Float64 = 0.0, @w : Float64 = 1.0)
    end

    def self.identity : Quaternion
      Quaternion.new(0.0, 0.0, 0.0, 1.0)
    end

    def self.from_euler(roll : Float64, pitch : Float64, yaw : Float64) : Quaternion
      cy = Math.cos(yaw * 0.5)
      sy = Math.sin(yaw * 0.5)
      cp = Math.cos(pitch * 0.5)
      sp = Math.sin(pitch * 0.5)
      cr = Math.cos(roll * 0.5)
      sr = Math.sin(roll * 0.5)

      Quaternion.new(
        sr * cp * cy - cr * sp * sy,
        cr * sp * cy + sr * cp * sy,
        cr * cp * sy - sr * sp * cy,
        cr * cp * cy + sr * sp * sy
      )
    end

    def self.from_axis_angle(axis : Vector3, angle : Float64) : Quaternion
      half_angle = angle * 0.5
      s = Math.sin(half_angle)
      Quaternion.new(
        axis.x * s,
        axis.y * s,
        axis.z * s,
        Math.cos(half_angle)
      )
    end

    def to_euler : {Float64, Float64, Float64}
      # Roll (x-axis rotation)
      sinr_cosp = 2.0 * (@w * @x + @y * @z)
      cosr_cosp = 1.0 - 2.0 * (@x * @x + @y * @y)
      roll = Math.atan2(sinr_cosp, cosr_cosp)

      # Pitch (y-axis rotation)
      sinp = 2.0 * (@w * @y - @z * @x)
      pitch = if sinp.abs >= 1.0
                Math.copysign(Math::PI / 2, sinp)
              else
                Math.asin(sinp)
              end

      # Yaw (z-axis rotation)
      siny_cosp = 2.0 * (@w * @z + @x * @y)
      cosy_cosp = 1.0 - 2.0 * (@y * @y + @z * @z)
      yaw = Math.atan2(siny_cosp, cosy_cosp)

      {roll, pitch, yaw}
    end

    def *(other : Quaternion) : Quaternion
      Quaternion.new(
        @w * other.x + @x * other.w + @y * other.z - @z * other.y,
        @w * other.y - @x * other.z + @y * other.w + @z * other.x,
        @w * other.z + @x * other.y - @y * other.x + @z * other.w,
        @w * other.w - @x * other.x - @y * other.y - @z * other.z
      )
    end

    def rotate(v : Vector3) : Vector3
      q_vec = Vector3.new(@x, @y, @z)
      t = q_vec.cross(v) * 2.0
      v + (t * @w) + q_vec.cross(t)
    end

    def normalized : Quaternion
      mag = Math.sqrt(@x * @x + @y * @y + @z * @z + @w * @w)
      return Quaternion.identity if mag == 0.0
      Quaternion.new(@x / mag, @y / mag, @z / mag, @w / mag)
    end

    def slerp(other : Quaternion, t : Float64) : Quaternion
      t = t.clamp(0.0, 1.0)
      dot = @x * other.x + @y * other.y + @z * other.z + @w * other.w

      # If dot is negative, negate one quaternion to take shorter path
      other_adj = dot < 0 ? Quaternion.new(-other.x, -other.y, -other.z, -other.w) : other
      dot = dot.abs

      if dot > 0.9995
        # Linear interpolation for very similar quaternions
        Quaternion.new(
          @x + t * (other_adj.x - @x),
          @y + t * (other_adj.y - @y),
          @z + t * (other_adj.z - @z),
          @w + t * (other_adj.w - @w)
        ).normalized
      else
        theta = Math.acos(dot)
        sin_theta = Math.sin(theta)
        s0 = Math.sin((1 - t) * theta) / sin_theta
        s1 = Math.sin(t * theta) / sin_theta
        Quaternion.new(
          s0 * @x + s1 * other_adj.x,
          s0 * @y + s1 * other_adj.y,
          s0 * @z + s1 * other_adj.z,
          s0 * @w + s1 * other_adj.w
        )
      end
    end

    def to_s : String
      "(#{@x}, #{@y}, #{@z}, #{@w})"
    end
  end

  # Transform representing position and rotation
  struct Transform
    property position : Vector3
    property rotation : Quaternion
    property scale : Vector3

    def initialize(
      @position : Vector3 = Vector3.zero,
      @rotation : Quaternion = Quaternion.identity,
      @scale : Vector3 = Vector3.one
    )
    end

    def self.identity : Transform
      Transform.new
    end

    def forward : Vector3
      @rotation.rotate(Vector3.forward)
    end

    def up : Vector3
      @rotation.rotate(Vector3.up)
    end

    def right : Vector3
      @rotation.rotate(Vector3.new(1.0, 0.0, 0.0))
    end

    def translate(offset : Vector3)
      @position = @position + offset
    end

    def rotate(q : Quaternion)
      @rotation = @rotation * q
    end

    def look_at(target : Vector3, up : Vector3 = Vector3.up)
      direction = (target - @position).normalized
      return if direction.magnitude_squared < 0.0001

      # Calculate rotation to face direction
      forward = Vector3.forward
      dot = forward.dot(direction)

      if (dot - 1.0).abs < 0.0001
        @rotation = Quaternion.identity
      elsif (dot + 1.0).abs < 0.0001
        @rotation = Quaternion.from_axis_angle(up, Math::PI)
      else
        axis = forward.cross(direction).normalized
        angle = Math.acos(dot.clamp(-1.0, 1.0))
        @rotation = Quaternion.from_axis_angle(axis, angle)
      end
    end
  end

  # Entity types in the simulation
  enum EntityType
    Agent
    Object
    Sensor
    Actuator
    Trigger
    Environment
  end

  # Base entity in the simulation
  abstract class Entity
    property name : String
    property transform : Transform
    property enabled : Bool = true
    property entity_type : EntityType

    @id : UInt64 = 0_u64
    @@next_id : UInt64 = 1_u64

    def initialize(@name : String, @entity_type : EntityType)
      @transform = Transform.identity
      @id = @@next_id
      @@next_id += 1
    end

    def id : UInt64
      @id
    end

    def position : Vector3
      @transform.position
    end

    def position=(pos : Vector3)
      @transform.position = pos
    end

    def rotation : Quaternion
      @transform.rotation
    end

    def rotation=(rot : Quaternion)
      @transform.rotation = rot
    end

    # Called each simulation step
    abstract def update(dt : Float64)

    # Convert to AtomSpace representation
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom
      entity_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "entity:#{@name}")

      # Add position
      pos = @transform.position
      pos_x = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, pos.x.to_s)
      pos_y = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, pos.y.to_s)
      pos_z = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, pos.z.to_s)
      pos_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "position")
      pos_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [entity_node, pos_x, pos_y, pos_z])
      atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [pos_pred, pos_list])

      # Add entity type
      type_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, @entity_type.to_s)
      type_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "entity_type")
      type_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [entity_node, type_node])
      atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [type_pred, type_list])

      entity_node
    end
  end

  # Abstract simulation environment interface
  abstract class SimulationEnvironment
    getter name : String
    getter time_manager : TimeManager
    getter agents : Array(Agent)
    getter objects : Array(SimulationObject)

    def initialize(@name : String)
      @time_manager = TimeManager.new
      @agents = [] of Agent
      @objects = [] of SimulationObject
    end

    # Add an agent to the environment
    def add_agent(agent : Agent)
      @agents << agent
      agent.environment = self
      CogUtil::Logger.debug("Added agent '#{agent.name}' to environment '#{@name}'")
    end

    # Remove an agent from the environment
    def remove_agent(agent : Agent) : Bool
      if @agents.delete(agent)
        CogUtil::Logger.debug("Removed agent '#{agent.name}' from environment '#{@name}'")
        true
      else
        false
      end
    end

    # Add a simulation object
    def add_object(obj : SimulationObject)
      @objects << obj
    end

    # Remove a simulation object
    def remove_object(obj : SimulationObject) : Bool
      @objects.delete(obj) != nil
    end

    # Step the simulation forward
    abstract def step(dt : Float64)

    # Get current simulation time
    def current_time : Float64
      @time_manager.current_time
    end

    # Check if environment is connected (for external simulators)
    def connected? : Bool
      true
    end

    # Find entity by name
    def find_entity(name : String) : Entity?
      @agents.find { |a| a.name == name } || @objects.find { |o| o.name == name }
    end

    # Get all entities within a radius
    def entities_in_radius(center : Vector3, radius : Float64) : Array(Entity)
      result = [] of Entity

      @agents.each do |agent|
        if center.distance_to(agent.position) <= radius
          result << agent.as(Entity)
        end
      end

      @objects.each do |obj|
        if center.distance_to(obj.position) <= radius
          result << obj.as(Entity)
        end
      end

      result
    end
  end

  # Local simulation environment (runs locally without external simulator)
  class LocalEnvironment < SimulationEnvironment
    property gravity : Vector3 = Vector3.new(0.0, -9.81, 0.0)
    property physics_enabled : Bool = true

    def initialize(name : String = "local")
      super(name)
    end

    def step(dt : Float64)
      @time_manager.advance(dt)

      # Update physics
      if @physics_enabled
        update_physics(dt)
      end

      # Update all agents
      @agents.each do |agent|
        agent.update(dt) if agent.enabled
      end

      # Update all objects
      @objects.each do |obj|
        obj.update(dt) if obj.enabled
      end
    end

    private def update_physics(dt : Float64)
      # Simple physics integration
      @objects.each do |obj|
        if obj.responds_to?(:physics_body) && obj.physics_body
          body = obj.physics_body.not_nil!
          body.integrate(dt, @gravity)
          obj.position = body.position
        end
      end
    end
  end

  # Simulation object (non-agent entity)
  class SimulationObject < Entity
    property physics_body : PhysicsBody?
    property collider : Collider?
    property visible : Bool = true

    def initialize(name : String)
      super(name, EntityType::Object)
    end

    def update(dt : Float64)
      # Base objects don't do much
    end
  end
end
