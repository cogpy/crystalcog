# Actuator System for Simulation
#
# Provides various actuator types for agents to interact with their environment,
# including movement, rotation, manipulation, and communication actuators.

module Simulation
  # Base actuator class
  abstract class Actuator
    property name : String
    property enabled : Bool = true
    property agent : Agent?

    def initialize(@name : String)
    end

    # Check if this actuator can execute a given action
    abstract def can_execute?(action : String) : Bool

    # Execute an action with parameters
    abstract def execute(action : String, params : Hash(String, Float64)) : Bool

    # Update actuator state
    def update(dt : Float64)
    end
  end

  # Movement actuator - allows agent to move
  class MovementActuator < Actuator
    property max_speed : Float64 = 5.0
    property acceleration : Float64 = 10.0

    def initialize(name : String = "movement", @max_speed : Float64 = 5.0, @acceleration : Float64 = 10.0)
      super(name)
    end

    def can_execute?(action : String) : Bool
      ["move_forward", "move_backward", "move_left", "move_right", "move_to", "stop"].includes?(action)
    end

    def execute(action : String, params : Hash(String, Float64)) : Bool
      agent = @agent
      return false unless agent

      speed = params["speed"]? || @max_speed

      case action
      when "move_forward"
        agent.velocity = agent.transform.forward * speed
        true
      when "move_backward"
        agent.velocity = agent.transform.forward * -speed
        true
      when "move_left"
        agent.velocity = agent.transform.right * -speed
        true
      when "move_right"
        agent.velocity = agent.transform.right * speed
        true
      when "move_to"
        x = params["x"]? || 0.0
        y = params["y"]? || 0.0
        z = params["z"]? || 0.0
        agent.set_goal(Vector3.new(x, y, z))
        true
      when "stop"
        agent.stop
        true
      else
        false
      end
    end
  end

  # Rotation actuator - allows agent to rotate
  class RotationActuator < Actuator
    property turn_rate : Float64 = Math::PI  # Radians per second

    def initialize(name : String = "rotation", @turn_rate : Float64 = Math::PI)
      super(name)
    end

    def can_execute?(action : String) : Bool
      ["turn_left", "turn_right", "turn_to", "look_at"].includes?(action)
    end

    def execute(action : String, params : Hash(String, Float64)) : Bool
      agent = @agent
      return false unless agent

      angle = params["angle"]? || @turn_rate * 0.1  # Default small turn

      case action
      when "turn_left"
        delta = Quaternion.from_axis_angle(Vector3.up, angle)
        agent.rotation = (agent.rotation * delta).normalized
        true
      when "turn_right"
        delta = Quaternion.from_axis_angle(Vector3.up, -angle)
        agent.rotation = (agent.rotation * delta).normalized
        true
      when "turn_to"
        yaw = params["yaw"]? || 0.0
        agent.rotation = Quaternion.from_euler(0.0, 0.0, yaw)
        true
      when "look_at"
        x = params["x"]? || 0.0
        y = params["y"]? || 0.0
        z = params["z"]? || 0.0
        agent.transform.look_at(Vector3.new(x, y, z))
        true
      else
        false
      end
    end
  end

  # Gripper actuator - allows agent to grab/release objects
  class GripperActuator < Actuator
    property grip_strength : Float64 = 10.0
    property reach : Float64 = 1.0
    @held_object : SimulationObject?

    def initialize(name : String = "gripper", @grip_strength : Float64 = 10.0, @reach : Float64 = 1.0)
      super(name)
      @held_object = nil
    end

    def can_execute?(action : String) : Bool
      ["grab", "release", "hold"].includes?(action)
    end

    def execute(action : String, params : Hash(String, Float64)) : Bool
      agent = @agent
      return false unless agent

      case action
      when "grab"
        # Try to grab nearest object
        env = agent.environment
        return false unless env

        nearest : SimulationObject? = nil
        min_dist = @reach

        env.objects.each do |obj|
          dist = agent.position.distance_to(obj.position)
          if dist < min_dist
            min_dist = dist
            nearest = obj
          end
        end

        if obj = nearest
          @held_object = obj
          CogUtil::Logger.debug("Agent '#{agent.name}' grabbed object '#{obj.name}'")
          true
        else
          false
        end

      when "release"
        if obj = @held_object
          CogUtil::Logger.debug("Agent '#{agent.name}' released object '#{obj.name}'")
          @held_object = nil
          true
        else
          false
        end

      when "hold"
        # Keep held object at agent's position
        if obj = @held_object
          offset = agent.transform.forward * @reach * 0.5
          obj.position = agent.position + offset
          true
        else
          false
        end

      else
        false
      end
    end

    def update(dt : Float64)
      # Keep held object attached
      if obj = @held_object
        if agent = @agent
          offset = agent.transform.forward * @reach * 0.5
          obj.position = agent.position + offset
        end
      end
    end

    def holding? : Bool
      @held_object != nil
    end

    def held_object : SimulationObject?
      @held_object
    end
  end

  # Communication actuator - allows agent to send messages
  class CommunicationActuator < Actuator
    property range : Float64 = 10.0
    @pending_message : String?
    @target : String?

    def initialize(name : String = "communication", @range : Float64 = 10.0)
      super(name)
    end

    def can_execute?(action : String) : Bool
      ["broadcast", "send", "signal"].includes?(action)
    end

    def execute(action : String, params : Hash(String, Float64)) : Bool
      agent = @agent
      return false unless agent
      env = agent.environment
      return false unless env

      case action
      when "broadcast"
        # Send to all agents in range
        message = @pending_message || "ping"
        count = 0

        env.agents.each do |other|
          next if other == agent
          next if agent.position.distance_to(other.position) > @range

          # Find communication sensor on target
          other.sensors.each do |sensor|
            if sensor.is_a?(CommunicationSensor)
              sensor.receive(agent.name, message)
              count += 1
            end
          end
        end

        CogUtil::Logger.debug("Agent '#{agent.name}' broadcast to #{count} agents")
        @pending_message = nil
        true

      when "send"
        # Send to specific target
        target_name = @target
        return false unless target_name

        target = env.agents.find { |a| a.name == target_name }
        return false unless target

        message = @pending_message || "ping"

        target.sensors.each do |sensor|
          if sensor.is_a?(CommunicationSensor)
            sensor.receive(agent.name, message)
          end
        end

        CogUtil::Logger.debug("Agent '#{agent.name}' sent message to '#{target_name}'")
        @pending_message = nil
        @target = nil
        true

      when "signal"
        # Simple signal (no message content)
        # Could trigger listeners
        true

      else
        false
      end
    end

    def set_message(message : String, target : String? = nil)
      @pending_message = message
      @target = target
    end
  end

  # LED/Light actuator - visual indicator
  class LightActuator < Actuator
    property color : {Float64, Float64, Float64} = {1.0, 1.0, 1.0}  # RGB
    property intensity : Float64 = 1.0
    property is_on : Bool = false

    def initialize(name : String = "light")
      super(name)
    end

    def can_execute?(action : String) : Bool
      ["turn_on", "turn_off", "set_color", "blink"].includes?(action)
    end

    def execute(action : String, params : Hash(String, Float64)) : Bool
      case action
      when "turn_on"
        @is_on = true
        @intensity = params["intensity"]? || 1.0
        true
      when "turn_off"
        @is_on = false
        true
      when "set_color"
        r = (params["r"]? || 1.0).clamp(0.0, 1.0)
        g = (params["g"]? || 1.0).clamp(0.0, 1.0)
        b = (params["b"]? || 1.0).clamp(0.0, 1.0)
        @color = {r, g, b}
        true
      when "blink"
        @is_on = !@is_on
        true
      else
        false
      end
    end
  end

  # Sound actuator - allows agent to make sounds
  class SoundActuator < Actuator
    property volume : Float64 = 1.0
    property max_range : Float64 = 20.0

    def initialize(name : String = "sound", @max_range : Float64 = 20.0)
      super(name)
    end

    def can_execute?(action : String) : Bool
      ["play", "beep", "alarm"].includes?(action)
    end

    def execute(action : String, params : Hash(String, Float64)) : Bool
      agent = @agent
      return false unless agent

      @volume = params["volume"]? || 1.0

      case action
      when "play", "beep", "alarm"
        CogUtil::Logger.debug("Agent '#{agent.name}' playing sound: #{action}")
        # In a full implementation, this would emit sound data
        true
      else
        false
      end
    end
  end

  # Marker/trail actuator - leaves visual markers
  class MarkerActuator < Actuator
    @markers : Array(NamedTuple(position: Vector3, time: Float64))

    def initialize(name : String = "marker")
      super(name)
      @markers = [] of NamedTuple(position: Vector3, time: Float64)
    end

    def can_execute?(action : String) : Bool
      ["place_marker", "clear_markers"].includes?(action)
    end

    def execute(action : String, params : Hash(String, Float64)) : Bool
      agent = @agent
      return false unless agent

      case action
      when "place_marker"
        @markers << {position: agent.position, time: Time.utc.to_unix_f}
        true
      when "clear_markers"
        @markers.clear
        true
      else
        false
      end
    end

    def markers : Array(NamedTuple(position: Vector3, time: Float64))
      @markers.dup
    end
  end
end
