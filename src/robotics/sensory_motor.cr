# Sensory-Motor Coordination Module for CrystalCog
#
# This module provides sensory-motor coordination capabilities including:
# - Sensor fusion and integration
# - Motor control abstraction
# - Reflexive behaviors
# - Proprioception and body schema
# - Sensorimotor learning and adaptation
#
# References:
# - Embodied Cognition: Varela, Thompson, Rosch 1991
# - Sensorimotor Theory: O'Regan & Noë 2001
# - Motor Control: Wolpert & Ghahramani 2000

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../spatial/spatial"
require "../temporal/temporal"
require "./ros_integration"

module Robotics
  # Sensor modality types
  enum SensorModality
    VISION
    AUDITION
    TOUCH
    PROPRIOCEPTION
    VESTIBULAR
    OLFACTION
    GUSTATION
    RANGE      # Distance sensors (LIDAR, sonar, etc.)
    FORCE
    TEMPERATURE
    PRESSURE
  end

  # Abstract sensor interface
  abstract class Sensor
    getter name : String
    getter modality : SensorModality
    getter frame_id : String
    getter update_rate : Float64  # Hz
    getter is_active : Bool
    getter last_update : Temporal::TimePoint?

    def initialize(@name : String, @modality : SensorModality,
                   @frame_id : String = "base_link",
                   @update_rate : Float64 = 30.0)
      @is_active = false
      @last_update = nil
    end

    abstract def read : SensorReading
    abstract def configure(params : Hash(String, Float64))

    def activate
      @is_active = true
      CogUtil::Logger.debug("Sensor #{@name} activated")
    end

    def deactivate
      @is_active = false
      CogUtil::Logger.debug("Sensor #{@name} deactivated")
    end

    def update
      return unless @is_active
      @last_update = Temporal::TimePoint.now
    end
  end

  # Sensor reading data
  class SensorReading
    getter sensor_name : String
    getter timestamp : Temporal::TimePoint
    getter modality : SensorModality
    getter data : Hash(String, Float64 | Array(Float64) | String)
    getter confidence : Float64

    def initialize(@sensor_name : String,
                   @modality : SensorModality,
                   @timestamp : Temporal::TimePoint = Temporal::TimePoint.now,
                   @confidence : Float64 = 1.0)
      @data = {} of String => Float64 | Array(Float64) | String
    end

    def set(key : String, value : Float64 | Array(Float64) | String)
      @data[key] = value
    end

    def get(key : String) : (Float64 | Array(Float64) | String)?
      @data[key]?
    end

    def get_float(key : String) : Float64?
      @data[key]?.as?(Float64)
    end

    def get_array(key : String) : Array(Float64)?
      @data[key]?.as?(Array(Float64))
    end

    def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      sensor_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, @sensor_name)
      reading_node = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        "reading_#{@timestamp.timestamp}"
      )

      # Link sensor to reading
      atoms << atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "has_reading"),
         atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [sensor_node, reading_node])]
      )

      # Add data as properties
      @data.each do |key, value|
        pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, key)
        val = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, value.to_s)
        atoms << atomspace.add_link(
          AtomSpace::AtomType::EVALUATION_LINK,
          [pred, atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [reading_node, val])]
        )
      end

      atoms
    end
  end

  # Vision sensor (camera)
  class VisionSensor < Sensor
    property resolution : Tuple(Int32, Int32)
    property field_of_view : Float64  # radians
    @image_data : Bytes?

    def initialize(name : String, frame_id : String = "camera_link",
                   @resolution : Tuple(Int32, Int32) = {640, 480},
                   @field_of_view : Float64 = 1.047)  # ~60 degrees
      super(name, SensorModality::VISION, frame_id)
      @image_data = nil
    end

    def read : SensorReading
      reading = SensorReading.new(@name, @modality)
      reading.set("width", @resolution[0].to_f64)
      reading.set("height", @resolution[1].to_f64)
      reading.set("fov", @field_of_view)
      update
      reading
    end

    def configure(params : Hash(String, Float64))
      if width = params["width"]?
        @resolution = {width.to_i, @resolution[1]}
      end
      if height = params["height"]?
        @resolution = {@resolution[0], height.to_i}
      end
      if fov = params["fov"]?
        @field_of_view = fov
      end
    end

    def set_image_data(data : Bytes)
      @image_data = data
    end
  end

  # Range sensor (LIDAR, sonar, etc.)
  class RangeSensor < Sensor
    property min_range : Float64
    property max_range : Float64
    property angle_min : Float64
    property angle_max : Float64
    property num_readings : Int32
    @ranges : Array(Float64)

    def initialize(name : String, frame_id : String = "laser_link",
                   @min_range : Float64 = 0.1,
                   @max_range : Float64 = 30.0,
                   @angle_min : Float64 = -Math::PI,
                   @angle_max : Float64 = Math::PI,
                   @num_readings : Int32 = 360)
      super(name, SensorModality::RANGE, frame_id, 10.0)
      @ranges = Array(Float64).new(@num_readings, @max_range)
    end

    def read : SensorReading
      reading = SensorReading.new(@name, @modality)
      reading.set("ranges", @ranges)
      reading.set("min_range", @min_range)
      reading.set("max_range", @max_range)
      reading.set("angle_min", @angle_min)
      reading.set("angle_max", @angle_max)
      update
      reading
    end

    def configure(params : Hash(String, Float64))
      @min_range = params["min_range"]? || @min_range
      @max_range = params["max_range"]? || @max_range
    end

    def set_ranges(ranges : Array(Float64))
      @ranges = ranges
    end

    # ROS range messages commonly carry Float32 samples. Normalize them at the
    # boundary so readings keep the module's Float64 representation.
    def set_ranges(ranges : Array(Float32))
      @ranges = ranges.map(&.to_f64)
    end

    def get_range_at_angle(angle : Float64) : Float64?
      return nil unless angle >= @angle_min && angle <= @angle_max
      index = ((@num_readings - 1) * (angle - @angle_min) / (@angle_max - @angle_min)).to_i
      @ranges[index]?
    end

    def min_reading : Float64
      @ranges.min
    end

    def obstacle_detected?(threshold : Float64 = 1.0) : Bool
      @ranges.any? { |r| r < threshold && r >= @min_range }
    end
  end

  # Proprioceptive sensor (joint positions, velocities)
  class ProprioceptiveSensor < Sensor
    getter joint_names : Array(String)
    @positions : Hash(String, Float64)
    @velocities : Hash(String, Float64)
    @efforts : Hash(String, Float64)

    def initialize(name : String, @joint_names : Array(String))
      super(name, SensorModality::PROPRIOCEPTION, "base_link", 100.0)
      @positions = {} of String => Float64
      @velocities = {} of String => Float64
      @efforts = {} of String => Float64

      @joint_names.each do |joint|
        @positions[joint] = 0.0
        @velocities[joint] = 0.0
        @efforts[joint] = 0.0
      end
    end

    def read : SensorReading
      reading = SensorReading.new(@name, @modality)
      @joint_names.each_with_index do |joint, i|
        reading.set("#{joint}_position", @positions[joint])
        reading.set("#{joint}_velocity", @velocities[joint])
        reading.set("#{joint}_effort", @efforts[joint])
      end
      update
      reading
    end

    def configure(params : Hash(String, Float64))
      # No configurable parameters for now
    end

    def set_joint_state(name : String, position : Float64, velocity : Float64 = 0.0, effort : Float64 = 0.0)
      @positions[name] = position
      @velocities[name] = velocity
      @efforts[name] = effort
    end

    def get_position(joint : String) : Float64?
      @positions[joint]?
    end

    def get_velocity(joint : String) : Float64?
      @velocities[joint]?
    end
  end

  # Touch/contact sensor
  class TouchSensor < Sensor
    property contact_threshold : Float64
    @contact_points : Array(Spatial::Vector3)
    @forces : Array(Float64)

    def initialize(name : String, frame_id : String,
                   @contact_threshold : Float64 = 0.1)
      super(name, SensorModality::TOUCH, frame_id, 100.0)
      @contact_points = [] of Spatial::Vector3
      @forces = [] of Float64
    end

    def read : SensorReading
      reading = SensorReading.new(@name, @modality)
      reading.set("num_contacts", @contact_points.size.to_f64)
      reading.set("total_force", @forces.sum)
      update
      reading
    end

    def configure(params : Hash(String, Float64))
      @contact_threshold = params["threshold"]? || @contact_threshold
    end

    def add_contact(point : Spatial::Vector3, force : Float64)
      if force >= @contact_threshold
        @contact_points << point
        @forces << force
      end
    end

    def clear_contacts
      @contact_points.clear
      @forces.clear
    end

    def has_contact? : Bool
      !@contact_points.empty?
    end
  end

  # Motor actuator types
  enum ActuatorType
    REVOLUTE     # Rotary joint
    PRISMATIC    # Linear joint
    CONTINUOUS   # Continuous rotation
    WHEEL        # Wheel drive
    GRIPPER      # End effector
  end

  # Abstract motor/actuator interface
  abstract class Actuator
    getter name : String
    getter type : ActuatorType
    getter frame_id : String
    getter position : Float64
    getter velocity : Float64
    getter effort : Float64
    getter min_position : Float64
    getter max_position : Float64
    getter max_velocity : Float64
    getter max_effort : Float64
    @is_enabled : Bool

    def initialize(@name : String, @type : ActuatorType,
                   @frame_id : String = "base_link",
                   @min_position : Float64 = -Float64::INFINITY,
                   @max_position : Float64 = Float64::INFINITY,
                   @max_velocity : Float64 = 1.0,
                   @max_effort : Float64 = 10.0)
      @position = 0.0
      @velocity = 0.0
      @effort = 0.0
      @is_enabled = false
    end

    abstract def set_target_position(position : Float64)
    abstract def set_target_velocity(velocity : Float64)
    abstract def set_target_effort(effort : Float64)

    def enable
      @is_enabled = true
      CogUtil::Logger.debug("Actuator #{@name} enabled")
    end

    def disable
      @is_enabled = false
      @velocity = 0.0
      CogUtil::Logger.debug("Actuator #{@name} disabled")
    end

    def enabled? : Bool
      @is_enabled
    end

    def at_limit? : Bool
      @position <= @min_position || @position >= @max_position
    end
  end

  # Joint actuator
  class JointActuator < Actuator
    @target_position : Float64
    @target_velocity : Float64
    @position_gain : Float64
    @velocity_gain : Float64

    def initialize(name : String, type : ActuatorType,
                   frame_id : String = "base_link",
                   min_pos : Float64 = -Math::PI,
                   max_pos : Float64 = Math::PI,
                   max_vel : Float64 = 1.0,
                   max_effort : Float64 = 10.0)
      super(name, type, frame_id, min_pos, max_pos, max_vel, max_effort)
      @target_position = 0.0
      @target_velocity = 0.0
      @position_gain = 10.0
      @velocity_gain = 1.0
    end

    def set_target_position(position : Float64)
      @target_position = position.clamp(@min_position, @max_position)
    end

    def set_target_velocity(velocity : Float64)
      @target_velocity = velocity.clamp(-@max_velocity, @max_velocity)
    end

    def set_target_effort(effort : Float64)
      @effort = effort.clamp(-@max_effort, @max_effort)
    end

    def set_gains(position_gain : Float64, velocity_gain : Float64)
      @position_gain = position_gain
      @velocity_gain = velocity_gain
    end

    def update(dt : Float64)
      return unless @is_enabled

      # Simple PD control
      position_error = @target_position - @position
      velocity_error = @target_velocity - @velocity

      commanded_effort = @position_gain * position_error + @velocity_gain * velocity_error
      commanded_effort = commanded_effort.clamp(-@max_effort, @max_effort)

      # Update state (simplified dynamics)
      @effort = commanded_effort
      @velocity = (@velocity + commanded_effort * dt).clamp(-@max_velocity, @max_velocity)
      @position = (@position + @velocity * dt).clamp(@min_position, @max_position)
    end
  end

  # Differential drive controller for wheeled robots
  class DifferentialDrive
    getter left_wheel : JointActuator
    getter right_wheel : JointActuator
    getter wheel_radius : Float64
    getter wheel_separation : Float64
    @linear_velocity : Float64
    @angular_velocity : Float64

    def initialize(@wheel_radius : Float64 = 0.1,
                   @wheel_separation : Float64 = 0.5)
      @left_wheel = JointActuator.new("left_wheel", ActuatorType::WHEEL)
      @right_wheel = JointActuator.new("right_wheel", ActuatorType::WHEEL)
      @linear_velocity = 0.0
      @angular_velocity = 0.0
    end

    def set_velocity(linear : Float64, angular : Float64)
      @linear_velocity = linear
      @angular_velocity = angular

      # Convert to wheel velocities
      left_vel = (linear - angular * @wheel_separation / 2.0) / @wheel_radius
      right_vel = (linear + angular * @wheel_separation / 2.0) / @wheel_radius

      @left_wheel.set_target_velocity(left_vel)
      @right_wheel.set_target_velocity(right_vel)
    end

    def stop
      set_velocity(0.0, 0.0)
    end

    def enable
      @left_wheel.enable
      @right_wheel.enable
    end

    def disable
      @left_wheel.disable
      @right_wheel.disable
    end

    def get_odometry(dt : Float64) : Tuple(Float64, Float64, Float64)
      # Calculate displacement from wheel velocities
      left_dist = @left_wheel.velocity * @wheel_radius * dt
      right_dist = @right_wheel.velocity * @wheel_radius * dt

      linear_dist = (left_dist + right_dist) / 2.0
      angular_dist = (right_dist - left_dist) / @wheel_separation

      {linear_dist, 0.0, angular_dist}  # dx, dy, dtheta
    end

    def update(dt : Float64)
      @left_wheel.update(dt)
      @right_wheel.update(dt)
    end
  end

  # Gripper controller
  class Gripper
    getter actuator : JointActuator
    getter max_opening : Float64
    getter grip_force : Float64
    @is_gripping : Bool

    def initialize(name : String = "gripper",
                   @max_opening : Float64 = 0.1,
                   @grip_force : Float64 = 10.0)
      @actuator = JointActuator.new(
        name,
        ActuatorType::GRIPPER,
        min_pos: 0.0,
        max_pos: @max_opening
      )
      @is_gripping = false
    end

    def open
      @actuator.set_target_position(@max_opening)
      @is_gripping = false
      CogUtil::Logger.debug("Gripper opening")
    end

    def close
      @actuator.set_target_position(0.0)
      @is_gripping = true
      CogUtil::Logger.debug("Gripper closing")
    end

    def set_position(position : Float64)
      @actuator.set_target_position(position.clamp(0.0, @max_opening))
    end

    def is_open? : Bool
      @actuator.position >= @max_opening * 0.9
    end

    def is_closed? : Bool
      @actuator.position <= @max_opening * 0.1
    end

    def is_gripping? : Bool
      @is_gripping && !is_open?
    end

    def enable
      @actuator.enable
    end

    def disable
      @actuator.disable
    end

    def update(dt : Float64)
      @actuator.update(dt)
    end
  end

  # Reflexive behavior definition
  class Reflex
    getter name : String
    getter trigger_condition : Proc(SensorReading, Bool)
    getter response : Proc(Nil)
    getter priority : Int32
    getter cooldown : Float64  # seconds
    @last_triggered : Temporal::TimePoint?
    @is_active : Bool

    def initialize(@name : String,
                   @trigger_condition : Proc(SensorReading, Bool),
                   @response : Proc(Nil),
                   @priority : Int32 = 0,
                   @cooldown : Float64 = 0.1)
      @last_triggered = nil
      @is_active = true
    end

    def check(reading : SensorReading) : Bool
      return false unless @is_active

      # Check cooldown
      if last = @last_triggered
        elapsed = (Temporal::TimePoint.now - last).to_seconds
        return false if elapsed < @cooldown
      end

      @trigger_condition.call(reading)
    end

    def trigger
      CogUtil::Logger.debug("Reflex '#{@name}' triggered")
      @last_triggered = Temporal::TimePoint.now
      @response.call
    end

    def enable
      @is_active = true
    end

    def disable
      @is_active = false
    end
  end

  # Body schema - internal model of the robot body
  class BodySchema
    getter segments : Hash(String, BodySegment)
    getter joints : Hash(String, JointInfo)
    getter end_effectors : Array(String)
    getter base_frame : String

    def initialize(@base_frame : String = "base_link")
      @segments = {} of String => BodySegment
      @joints = {} of String => JointInfo
      @end_effectors = [] of String
    end

    def add_segment(name : String, parent : String?, length : Float64,
                    mass : Float64 = 1.0)
      @segments[name] = BodySegment.new(name, parent, length, mass)
    end

    def add_joint(name : String, parent_segment : String, child_segment : String,
                  type : ActuatorType, axis : Spatial::Vector3 = Spatial::Vector3.new(0.0, 0.0, 1.0))
      @joints[name] = JointInfo.new(name, parent_segment, child_segment, type, axis)
    end

    def add_end_effector(segment : String)
      @end_effectors << segment
    end

    # Forward kinematics - compute end effector position given joint angles
    def forward_kinematics(joint_positions : Hash(String, Float64)) : Hash(String, Spatial::Vector3)
      positions = {} of String => Spatial::Vector3

      # Start from base
      positions[@base_frame] = Spatial::Vector3.new

      # Traverse kinematic chain
      @segments.each do |name, segment|
        if parent = segment.parent
          parent_pos = positions[parent]? || Spatial::Vector3.new

          # Get joint connecting parent to this segment
          joint = @joints.values.find { |j| j.child_segment == name }

          if joint && (angle = joint_positions[joint.name]?)
            # Simple rotation around joint axis
            offset = rotate_around_axis(
              Spatial::Vector3.new(segment.length, 0.0, 0.0),
              joint.axis,
              angle
            )
            positions[name] = parent_pos + offset
          else
            positions[name] = parent_pos + Spatial::Vector3.new(segment.length, 0.0, 0.0)
          end
        else
          positions[name] = Spatial::Vector3.new
        end
      end

      positions
    end

    private def rotate_around_axis(v : Spatial::Vector3, axis : Spatial::Vector3,
                                   angle : Float64) : Spatial::Vector3
      c = Math.cos(angle)
      s = Math.sin(angle)
      k = axis.normalized

      Spatial::Vector3.new(
        v.x * (c + k.x * k.x * (1 - c)) + v.y * (k.x * k.y * (1 - c) - k.z * s) + v.z * (k.x * k.z * (1 - c) + k.y * s),
        v.x * (k.y * k.x * (1 - c) + k.z * s) + v.y * (c + k.y * k.y * (1 - c)) + v.z * (k.y * k.z * (1 - c) - k.x * s),
        v.x * (k.z * k.x * (1 - c) - k.y * s) + v.y * (k.z * k.y * (1 - c) + k.x * s) + v.z * (c + k.z * k.z * (1 - c))
      )
    end
  end

  struct BodySegment
    getter name : String
    getter parent : String?
    getter length : Float64
    getter mass : Float64

    def initialize(@name : String, @parent : String?, @length : Float64, @mass : Float64)
    end
  end

  struct JointInfo
    getter name : String
    getter parent_segment : String
    getter child_segment : String
    getter type : ActuatorType
    getter axis : Spatial::Vector3

    def initialize(@name : String, @parent_segment : String, @child_segment : String,
                   @type : ActuatorType, @axis : Spatial::Vector3)
    end
  end

  # Sensor fusion - combines multiple sensor readings
  class SensorFusion
    getter sensors : Array(Sensor)
    getter fused_state : Hash(String, Float64)
    @weights : Hash(String, Float64)

    def initialize
      @sensors = [] of Sensor
      @fused_state = {} of String => Float64
      @weights = {} of String => Float64
    end

    def add_sensor(sensor : Sensor, weight : Float64 = 1.0)
      @sensors << sensor
      @weights[sensor.name] = weight
    end

    def update
      readings = @sensors.select(&.is_active).map(&.read)
      fuse_readings(readings)
    end

    private def fuse_readings(readings : Array(SensorReading))
      # Group by modality and fuse
      readings.group_by(&.modality).each do |modality, group|
        case modality
        when SensorModality::RANGE
          fuse_range_sensors(group)
        when SensorModality::PROPRIOCEPTION
          fuse_proprioceptive_sensors(group)
        else
          # Simple averaging for other modalities
          group.each do |reading|
            reading.data.each do |key, value|
              if v = value.as?(Float64)
                weight = @weights[reading.sensor_name]? || 1.0
                existing = @fused_state[key]?
                @fused_state[key] = existing ? (existing + v * weight) / 2.0 : v
              end
            end
          end
        end
      end
    end

    private def fuse_range_sensors(readings : Array(SensorReading))
      # Take minimum range (closest obstacle)
      min_range = Float64::INFINITY
      readings.each do |reading|
        if ranges = reading.get_array("ranges")
          range_min = ranges.min
          min_range = range_min if range_min < min_range
        end
      end
      @fused_state["min_obstacle_distance"] = min_range
    end

    private def fuse_proprioceptive_sensors(readings : Array(SensorReading))
      # Average joint positions (weighted by confidence)
      readings.each do |reading|
        reading.data.each do |key, value|
          if v = value.as?(Float64)
            @fused_state[key] = v
          end
        end
      end
    end

    def get_state(key : String) : Float64?
      @fused_state[key]?
    end
  end

  # Main sensory-motor coordinator
  class SensoryMotorCoordinator
    getter sensors : Hash(String, Sensor)
    getter actuators : Hash(String, Actuator)
    getter reflexes : Array(Reflex)
    getter body_schema : BodySchema
    getter sensor_fusion : SensorFusion
    @atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @sensors = {} of String => Sensor
      @actuators = {} of String => Actuator
      @reflexes = [] of Reflex
      @body_schema = BodySchema.new
      @sensor_fusion = SensorFusion.new
      CogUtil::Logger.info("SensoryMotorCoordinator initialized")
    end

    def add_sensor(sensor : Sensor)
      @sensors[sensor.name] = sensor
      @sensor_fusion.add_sensor(sensor)
      sensor.activate
    end

    def add_actuator(actuator : Actuator)
      @actuators[actuator.name] = actuator
    end

    def add_reflex(reflex : Reflex)
      @reflexes << reflex
      @reflexes.sort_by! { |r| -r.priority }  # Higher priority first
    end

    def read_sensor(name : String) : SensorReading?
      @sensors[name]?.try(&.read)
    end

    def read_all_sensors : Array(SensorReading)
      @sensors.values.select(&.is_active).map(&.read)
    end

    def set_actuator_position(name : String, position : Float64)
      if actuator = @actuators[name]?
        actuator.set_target_position(position)
      end
    end

    def set_actuator_velocity(name : String, velocity : Float64)
      if actuator = @actuators[name]?
        actuator.set_target_velocity(velocity)
      end
    end

    def update(dt : Float64)
      # Update sensor fusion
      @sensor_fusion.update

      # Check reflexes
      readings = read_all_sensors
      readings.each do |reading|
        @reflexes.each do |reflex|
          if reflex.check(reading)
            reflex.trigger
          end
        end
      end

      # Update actuators
      @actuators.each_value do |actuator|
        if actuator.is_a?(JointActuator)
          actuator.update(dt)
        end
      end
    end

    def sync_to_atomspace
      # Add sensor readings to atomspace
      read_all_sensors.each do |reading|
        reading.to_atomspace(@atomspace)
      end

      # Add body state
      robot_node = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "robot")

      @sensor_fusion.fused_state.each do |key, value|
        pred = @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, key)
        val = @atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, value.to_s)
        @atomspace.add_link(
          AtomSpace::AtomType::EVALUATION_LINK,
          [pred, @atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [robot_node, val])]
        )
      end
    end

    def enable_all_actuators
      @actuators.each_value(&.enable)
    end

    def disable_all_actuators
      @actuators.each_value(&.disable)
    end

    def emergency_stop
      CogUtil::Logger.warn("Emergency stop activated!")
      disable_all_actuators
      @reflexes.each(&.disable)
    end

    def resume
      CogUtil::Logger.info("Resuming from emergency stop")
      enable_all_actuators
      @reflexes.each(&.enable)
    end
  end

  # Module-level convenience methods
  def self.create_coordinator(atomspace : AtomSpace::AtomSpace) : SensoryMotorCoordinator
    SensoryMotorCoordinator.new(atomspace)
  end

  def self.create_range_sensor(name : String, frame : String = "laser_link") : RangeSensor
    RangeSensor.new(name, frame)
  end

  def self.create_vision_sensor(name : String, frame : String = "camera_link") : VisionSensor
    VisionSensor.new(name, frame)
  end

  def self.create_gripper(name : String = "gripper") : Gripper
    Gripper.new(name)
  end

  def self.create_differential_drive : DifferentialDrive
    DifferentialDrive.new
  end
end
