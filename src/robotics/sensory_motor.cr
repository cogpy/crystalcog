# Sensory-Motor Coordination for CrystalCog Robotics
#
# This module implements sensory processing and motor control primitives,
# enabling agents to perceive their environment and execute actions.

require "../cogutil/cogutil"
require "./spatial_reasoning"

module Robotics
  module SensoryMotor
    VERSION = "0.1.0"

    class SensoryMotorException < Exception
    end

    # --- Sensor abstractions ---

    # A raw sensor reading (distance, angle, intensity, etc.)
    struct SensorReading
      getter sensor_id : String
      getter value : Float64
      getter timestamp : Time
      getter valid : Bool

      def initialize(@sensor_id : String, @value : Float64, @valid : Bool = true)
        @timestamp = Time.utc
      end
    end

    # Sonar / distance sensor
    class RangeSensor
      getter id : String
      getter max_range : Float64
      getter noise_stddev : Float64

      def initialize(@id : String, @max_range : Float64 = 10.0, @noise_stddev : Float64 = 0.02)
      end

      # Simulate a distance measurement given actual distance
      def measure(actual_distance : Float64) : SensorReading
        noisy = actual_distance + (Random.new.next_float * 2.0 - 1.0) * @noise_stddev
        noisy = noisy.clamp(0.0, @max_range)
        SensorReading.new(@id, noisy, noisy < @max_range)
      end
    end

    # Camera-like sensor that returns a list of detected object labels and positions
    struct Detection
      getter label : String
      getter position : SpatialReasoning::Position
      getter confidence : Float64

      def initialize(@label : String, @position : SpatialReasoning::Position, @confidence : Float64 = 1.0)
      end
    end

    class VisionSensor
      getter id : String
      getter field_of_view : Float64   # radians
      getter range : Float64

      def initialize(@id : String, @field_of_view : Float64 = Math::PI / 2.0, @range : Float64 = 5.0)
      end

      # Given a list of entities, return those visible from robot pose
      def detect(robot_pose : SpatialReasoning::Pose, entities : Hash(String, SpatialReasoning::SpatialEntity)) : Array(Detection)
        results = [] of Detection
        robot_pos = robot_pose.position
        robot_yaw = robot_pose.orientation.yaw

        entities.each do |_id, entity|
          diff = entity.position - robot_pos
          dist = diff.magnitude
          next if dist > @range

          angle_to = Math.atan2(diff.y, diff.x)
          angle_diff = angle_to - robot_yaw
          # Normalize angle
          while angle_diff > Math::PI; angle_diff -= 2.0 * Math::PI; end
          while angle_diff < -Math::PI; angle_diff += 2.0 * Math::PI; end

          if angle_diff.abs <= @field_of_view / 2.0
            confidence = 1.0 - dist / @range
            results << Detection.new(entity.name, entity.position, confidence)
          end
        end

        results
      end
    end

    # --- Motor abstractions ---

    # Command sent to actuators
    struct MotorCommand
      getter linear_velocity : Float64   # m/s forward
      getter angular_velocity : Float64  # rad/s turning

      def initialize(@linear_velocity : Float64 = 0.0, @angular_velocity : Float64 = 0.0)
      end

      def stop? : Bool
        @linear_velocity == 0.0 && @angular_velocity == 0.0
      end
    end

    # Simulates a differential-drive robot base
    class DifferentialDrive
      getter pose : SpatialReasoning::Pose
      getter wheel_base : Float64   # distance between wheels (m)
      getter max_speed : Float64    # m/s

      def initialize(initial_pose : SpatialReasoning::Pose, @wheel_base : Float64 = 0.5, @max_speed : Float64 = 1.0)
        @pose = initial_pose
      end

      # Apply motor command for a time step (seconds) and update pose
      def apply(command : MotorCommand, dt : Float64 = 0.1)
        v = command.linear_velocity.clamp(-@max_speed, @max_speed)
        omega = command.angular_velocity

        yaw = @pose.orientation.yaw
        new_yaw = yaw + omega * dt

        new_x = @pose.position.x + v * Math.cos(yaw) * dt
        new_y = @pose.position.y + v * Math.sin(yaw) * dt

        @pose = SpatialReasoning::Pose.new(
          SpatialReasoning::Position.new(new_x, new_y, @pose.position.z),
          SpatialReasoning::Orientation.new(0.0, 0.0, new_yaw)
        )
      end
    end

    # --- Sensory-Motor Loop ---

    # Reactive behavior: pairs a condition on sensor data with a motor response
    class ReactiveBehavior
      getter name : String

      def initialize(@name : String, &@condition : Array(SensorReading) -> Bool)
        @action = Proc(Array(SensorReading), MotorCommand).new { |_| MotorCommand.new }
      end

      def on_trigger(&block : Array(SensorReading) -> MotorCommand)
        @action = block
        self
      end

      def evaluate(readings : Array(SensorReading)) : MotorCommand?
        if @condition.call(readings)
          @action.call(readings)
        else
          nil
        end
      end
    end

    # Coordinates sensors and actuators for a robot agent
    class SensoryMotorSystem
      getter sensors : Hash(String, RangeSensor)
      getter drive : DifferentialDrive
      getter behaviors : Array(ReactiveBehavior)

      def initialize(drive : DifferentialDrive)
        @drive = drive
        @sensors = {} of String => RangeSensor
        @behaviors = [] of ReactiveBehavior
        CogUtil::Logger.info("SensoryMotorSystem initialized")
      end

      def add_sensor(sensor : RangeSensor)
        @sensors[sensor.id] = sensor
      end

      def add_behavior(behavior : ReactiveBehavior)
        @behaviors << behavior
      end

      # Process one control cycle: gather readings, select behavior, apply command
      def tick(distances : Hash(String, Float64), dt : Float64 = 0.1) : MotorCommand
        readings = @sensors.map do |id, sensor|
          dist = distances[id]? || sensor.max_range
          sensor.measure(dist)
        end

        # Priority: first matching behavior wins
        command = @behaviors.each do |behavior|
          cmd = behavior.evaluate(readings)
          break cmd if cmd
        end

        cmd = command.is_a?(MotorCommand) ? command : MotorCommand.new(0.5, 0.0)
        @drive.apply(cmd, dt)
        cmd
      end
    end
  end
end
