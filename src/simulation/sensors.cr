# Sensor System for Simulation
#
# Provides various sensor types for agents to perceive their environment,
# including position, orientation, range, vision, and touch sensors.

module Simulation
  # Base sensor class
  abstract class Sensor
    property name : String
    property enabled : Bool = true
    property update_rate : Float64 = 0.0  # 0 = every frame
    property agent : Agent?

    @last_update : Float64 = 0.0
    @time_since_update : Float64 = 0.0

    def initialize(@name : String)
    end

    # Get current sensor value
    abstract def value : Float64 | Bool | Array(Float64)

    # Update sensor (called each frame)
    def update(dt : Float64)
      @time_since_update += dt

      if @update_rate <= 0.0 || @time_since_update >= @update_rate
        read
        @time_since_update = 0.0
      end
    end

    # Perform sensor reading
    protected abstract def read
  end

  # Position sensor - returns agent's position
  class PositionSensor < Sensor
    @cached_value : Array(Float64) = [0.0, 0.0, 0.0]

    def initialize(name : String = "position")
      super(name)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    protected def read
      if agent = @agent
        pos = agent.position
        @cached_value = [pos.x, pos.y, pos.z]
      end
    end
  end

  # Orientation sensor - returns agent's rotation as Euler angles
  class OrientationSensor < Sensor
    @cached_value : Array(Float64) = [0.0, 0.0, 0.0]

    def initialize(name : String = "orientation")
      super(name)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    protected def read
      if agent = @agent
        roll, pitch, yaw = agent.rotation.to_euler
        @cached_value = [roll, pitch, yaw]
      end
    end
  end

  # Velocity sensor - returns agent's velocity
  class VelocitySensor < Sensor
    @cached_value : Float64 = 0.0

    def initialize(name : String = "velocity")
      super(name)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    protected def read
      if agent = @agent
        @cached_value = agent.velocity.magnitude
      end
    end
  end

  # Range sensor - distance to nearest object in forward direction
  class RangeSensor < Sensor
    property range : Float64
    property field_of_view : Float64  # In radians
    @cached_value : Float64 = Float64::MAX

    def initialize(name : String = "range", @range : Float64 = 10.0, @field_of_view : Float64 = 0.0)
      super(name)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    protected def read
      agent = @agent
      return unless agent
      env = agent.environment
      return unless env

      # Simple implementation: find nearest entity in front
      forward = agent.transform.forward
      min_distance = @range

      env.entities_in_radius(agent.position, @range).each do |entity|
        next if entity == agent

        to_entity = entity.position - agent.position
        distance = to_entity.magnitude

        # Check if in field of view
        if @field_of_view > 0.0
          angle = Math.acos((forward.dot(to_entity.normalized)).clamp(-1.0, 1.0))
          next if angle > @field_of_view / 2
        end

        min_distance = Math.min(min_distance, distance)
      end

      @cached_value = min_distance
    end

    # Check if something is detected
    def detected? : Bool
      @cached_value < @range
    end
  end

  # Multi-ray range sensor (like LIDAR)
  class LidarSensor < Sensor
    property range : Float64
    property num_rays : Int32
    property scan_angle : Float64  # Total scan angle in radians
    @cached_value : Array(Float64) = [] of Float64

    def initialize(
      name : String = "lidar",
      @range : Float64 = 10.0,
      @num_rays : Int32 = 36,
      @scan_angle : Float64 = 2 * Math::PI
    )
      super(name)
      @cached_value = Array.new(@num_rays, @range)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    protected def read
      agent = @agent
      return unless agent
      env = agent.environment
      return unless env

      angle_step = @scan_angle / @num_rays
      start_angle = -@scan_angle / 2

      @cached_value = Array.new(@num_rays) do |i|
        angle = start_angle + angle_step * i
        direction = Quaternion.from_axis_angle(Vector3.up, angle).rotate(agent.transform.forward)

        # Simple raycast
        min_distance = @range
        env.entities_in_radius(agent.position, @range).each do |entity|
          next if entity == agent

          to_entity = entity.position - agent.position
          # Project onto ray direction
          dist_along_ray = to_entity.dot(direction)
          next if dist_along_ray < 0

          # Check perpendicular distance (simple sphere check with radius 0.5)
          closest_point = agent.position + direction * dist_along_ray
          perp_dist = entity.position.distance_to(closest_point)
          if perp_dist < 0.5 && dist_along_ray < min_distance
            min_distance = dist_along_ray
          end
        end

        min_distance
      end
    end

    # Get readings in a specific direction
    def reading_at_angle(angle : Float64) : Float64
      index = ((angle + @scan_angle / 2) / @scan_angle * @num_rays).to_i.clamp(0, @num_rays - 1)
      @cached_value[index]
    end
  end

  # Touch/collision sensor
  class TouchSensor < Sensor
    property detection_radius : Float64
    @cached_value : Bool = false
    @touching_entities : Array(Entity) = [] of Entity

    def initialize(name : String = "touch", @detection_radius : Float64 = 0.5)
      super(name)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    def touching : Array(Entity)
      @touching_entities.dup
    end

    protected def read
      agent = @agent
      return unless agent
      env = agent.environment
      return unless env

      @touching_entities.clear

      env.entities_in_radius(agent.position, @detection_radius).each do |entity|
        next if entity == agent
        @touching_entities << entity
      end

      @cached_value = !@touching_entities.empty?
    end
  end

  # Goal proximity sensor
  class GoalSensor < Sensor
    @cached_value : Float64 = Float64::MAX

    def initialize(name : String = "goal_distance")
      super(name)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    protected def read
      if agent = @agent
        if goal = agent.current_goal
          @cached_value = agent.position.distance_to(goal)
        else
          @cached_value = Float64::MAX
        end
      end
    end

    def has_goal? : Bool
      agent = @agent
      return false unless agent
      agent.current_goal != nil
    end
  end

  # Light/intensity sensor
  class LightSensor < Sensor
    property sensitivity : Float64 = 1.0
    @cached_value : Float64 = 0.0

    def initialize(name : String = "light", @sensitivity : Float64 = 1.0)
      super(name)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    protected def read
      # In a full implementation, this would read from light sources
      # For now, return ambient light level (simulated)
      @cached_value = 0.5 * @sensitivity
    end
  end

  # Communication sensor - detects messages from other agents
  class CommunicationSensor < Sensor
    @received_messages : Array(NamedTuple(sender: String, message: String, time: Float64))
    @cached_value : Float64 = 0.0  # Number of unread messages

    def initialize(name : String = "communication")
      super(name)
      @received_messages = [] of NamedTuple(sender: String, message: String, time: Float64)
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    def messages : Array(NamedTuple(sender: String, message: String, time: Float64))
      @received_messages.dup
    end

    def receive(sender : String, message : String)
      @received_messages << {sender: sender, message: message, time: Time.utc.to_unix_f}
    end

    def clear_messages
      @received_messages.clear
    end

    protected def read
      @cached_value = @received_messages.size.to_f64
    end
  end

  # Energy/battery sensor
  class EnergySensor < Sensor
    property max_energy : Float64 = 100.0
    property current_energy : Float64 = 100.0
    @cached_value : Float64 = 100.0

    def initialize(name : String = "energy", @max_energy : Float64 = 100.0)
      super(name)
      @current_energy = @max_energy
    end

    def value : Float64 | Bool | Array(Float64)
      @cached_value
    end

    def consume(amount : Float64)
      @current_energy = (@current_energy - amount).clamp(0.0, @max_energy)
    end

    def recharge(amount : Float64)
      @current_energy = (@current_energy + amount).clamp(0.0, @max_energy)
    end

    def percentage : Float64
      @current_energy / @max_energy * 100.0
    end

    protected def read
      @cached_value = @current_energy
    end
  end
end
