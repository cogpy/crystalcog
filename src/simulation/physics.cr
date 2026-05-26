# Physics System for Simulation
#
# Provides basic physics simulation including rigid body dynamics,
# collision detection, and physics material properties.

module Simulation
  # Physics body types
  enum PhysicsBodyType
    Static     # Doesn't move, infinite mass
    Dynamic    # Affected by forces and collisions
    Kinematic  # Moved by code, not by physics
  end

  # Physics material properties
  struct PhysicsMaterial
    property friction : Float64 = 0.5
    property restitution : Float64 = 0.3  # Bounciness
    property density : Float64 = 1.0

    def initialize(@friction = 0.5, @restitution = 0.3, @density = 1.0)
    end

    def self.default : PhysicsMaterial
      PhysicsMaterial.new
    end

    def self.bouncy : PhysicsMaterial
      PhysicsMaterial.new(friction: 0.3, restitution: 0.9)
    end

    def self.slippery : PhysicsMaterial
      PhysicsMaterial.new(friction: 0.1, restitution: 0.1)
    end

    def self.rubber : PhysicsMaterial
      PhysicsMaterial.new(friction: 0.8, restitution: 0.6)
    end
  end

  # Collider shapes
  abstract class Collider
    property enabled : Bool = true
    property is_trigger : Bool = false

    abstract def contains_point?(point : Vector3) : Bool
    abstract def bounds : {Vector3, Vector3}  # min, max
  end

  # Sphere collider
  class SphereCollider < Collider
    property radius : Float64
    property center : Vector3

    def initialize(@radius : Float64 = 0.5, @center : Vector3 = Vector3.zero)
    end

    def contains_point?(point : Vector3) : Bool
      @center.distance_to(point) <= @radius
    end

    def bounds : {Vector3, Vector3}
      offset = Vector3.new(@radius, @radius, @radius)
      {@center - offset, @center + offset}
    end

    def intersects?(other : SphereCollider) : Bool
      distance = @center.distance_to(other.center)
      distance <= (@radius + other.radius)
    end
  end

  # Box (AABB) collider
  class BoxCollider < Collider
    property size : Vector3
    property center : Vector3

    def initialize(@size : Vector3 = Vector3.one, @center : Vector3 = Vector3.zero)
    end

    def contains_point?(point : Vector3) : Bool
      half = @size * 0.5
      min = @center - half
      max = @center + half

      point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y &&
        point.z >= min.z && point.z <= max.z
    end

    def bounds : {Vector3, Vector3}
      half = @size * 0.5
      {@center - half, @center + half}
    end

    def intersects?(other : BoxCollider) : Bool
      min1, max1 = bounds
      min2, max2 = other.bounds

      min1.x <= max2.x && max1.x >= min2.x &&
        min1.y <= max2.y && max1.y >= min2.y &&
        min1.z <= max2.z && max1.z >= min2.z
    end
  end

  # Physics body for simulation
  class PhysicsBody
    property position : Vector3
    property rotation : Quaternion
    property velocity : Vector3
    property angular_velocity : Vector3
    property mass : Float64
    property inverse_mass : Float64
    property body_type : PhysicsBodyType
    property material : PhysicsMaterial
    property use_gravity : Bool = true
    property linear_drag : Float64 = 0.01
    property angular_drag : Float64 = 0.05

    # Accumulated force and torque for current frame
    @accumulated_force : Vector3 = Vector3.zero
    @accumulated_torque : Vector3 = Vector3.zero

    def initialize(
      @position : Vector3 = Vector3.zero,
      @mass : Float64 = 1.0,
      @body_type : PhysicsBodyType = PhysicsBodyType::Dynamic
    )
      @rotation = Quaternion.identity
      @velocity = Vector3.zero
      @angular_velocity = Vector3.zero
      @inverse_mass = @mass > 0.0 ? 1.0 / @mass : 0.0
      @material = PhysicsMaterial.default
    end

    # Apply a force at the center of mass
    def add_force(force : Vector3)
      return if @body_type != PhysicsBodyType::Dynamic
      @accumulated_force = @accumulated_force + force
    end

    # Apply a force at a world position (can cause rotation)
    def add_force_at_position(force : Vector3, position : Vector3)
      return if @body_type != PhysicsBodyType::Dynamic
      @accumulated_force = @accumulated_force + force

      # Calculate torque
      r = position - @position
      torque = r.cross(force)
      @accumulated_torque = @accumulated_torque + torque
    end

    # Apply an impulse (immediate velocity change)
    def add_impulse(impulse : Vector3)
      return if @body_type != PhysicsBodyType::Dynamic
      @velocity = @velocity + impulse * @inverse_mass
    end

    # Apply torque
    def add_torque(torque : Vector3)
      return if @body_type != PhysicsBodyType::Dynamic
      @accumulated_torque = @accumulated_torque + torque
    end

    # Integrate physics (called by physics system)
    def integrate(dt : Float64, gravity : Vector3)
      return if @body_type == PhysicsBodyType::Static

      if @body_type == PhysicsBodyType::Dynamic
        # Apply gravity
        if @use_gravity
          @accumulated_force = @accumulated_force + gravity * @mass
        end

        # Update velocity from forces
        acceleration = @accumulated_force * @inverse_mass
        @velocity = @velocity + acceleration * dt

        # Apply linear drag
        @velocity = @velocity * (1.0 - @linear_drag * dt).clamp(0.0, 1.0)

        # Update angular velocity from torques
        # Simplified: assuming uniform sphere for inertia
        inertia = @mass * 0.4  # Approximate
        if inertia > 0.0
          angular_acceleration = @accumulated_torque / inertia
          @angular_velocity = @angular_velocity + angular_acceleration * dt
        end

        # Apply angular drag
        @angular_velocity = @angular_velocity * (1.0 - @angular_drag * dt).clamp(0.0, 1.0)
      end

      # Update position and rotation
      @position = @position + @velocity * dt

      # Update rotation from angular velocity
      if @angular_velocity.magnitude_squared > 0.0001
        angle = @angular_velocity.magnitude * dt
        axis = @angular_velocity.normalized
        delta_rotation = Quaternion.from_axis_angle(axis, angle)
        @rotation = (@rotation * delta_rotation).normalized
      end

      # Clear accumulated forces
      @accumulated_force = Vector3.zero
      @accumulated_torque = Vector3.zero
    end

    # Set velocity directly (useful for kinematic bodies)
    def set_velocity(velocity : Vector3)
      @velocity = velocity
    end

    # Teleport to position (no physics)
    def teleport(position : Vector3)
      @position = position
    end

    # Check if body is at rest
    def is_sleeping? : Bool
      @velocity.magnitude_squared < 0.0001 && @angular_velocity.magnitude_squared < 0.0001
    end

    # Make body static
    def make_static
      @body_type = PhysicsBodyType::Static
      @velocity = Vector3.zero
      @angular_velocity = Vector3.zero
      @inverse_mass = 0.0
    end

    # Make body dynamic
    def make_dynamic(mass : Float64 = 1.0)
      @body_type = PhysicsBodyType::Dynamic
      @mass = mass
      @inverse_mass = mass > 0.0 ? 1.0 / mass : 0.0
    end
  end

  # Simple collision detection result
  struct CollisionResult
    property collided : Bool
    property point : Vector3
    property normal : Vector3
    property penetration : Float64
    property entity_a : Entity?
    property entity_b : Entity?

    def initialize(
      @collided : Bool = false,
      @point : Vector3 = Vector3.zero,
      @normal : Vector3 = Vector3.up,
      @penetration : Float64 = 0.0,
      @entity_a : Entity? = nil,
      @entity_b : Entity? = nil
    )
    end

    def self.no_collision : CollisionResult
      CollisionResult.new
    end
  end

  # Physics world that manages all physics simulation
  class PhysicsWorld
    property gravity : Vector3 = Vector3.new(0.0, -9.81, 0.0)
    property bodies : Array(PhysicsBody)
    property collision_iterations : Int32 = 4

    def initialize
      @bodies = [] of PhysicsBody
    end

    def add_body(body : PhysicsBody)
      @bodies << body
    end

    def remove_body(body : PhysicsBody)
      @bodies.delete(body)
    end

    def step(dt : Float64)
      # Integrate all bodies
      @bodies.each do |body|
        body.integrate(dt, @gravity)
      end

      # Simple collision resolution could be added here
    end

    def raycast(origin : Vector3, direction : Vector3, max_distance : Float64 = Float64::MAX) : CollisionResult?
      # Simplified raycast implementation
      # In a full implementation, this would check against all colliders
      nil
    end

    def clear
      @bodies.clear
    end
  end
end
