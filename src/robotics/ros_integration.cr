# ROS (Robot Operating System) Integration Module for CrystalCog
#
# This module provides integration with ROS for robotic platforms including:
# - ROS message types and serialization
# - Topic publishing and subscribing
# - Service clients and servers
# - Action interfaces
# - Parameter management
# - TF (Transform) integration
#
# References:
# - ROS 2: https://docs.ros.org/en/rolling/
# - ROS Messages: https://wiki.ros.org/msg
# - ROS Actions: https://design.ros2.org/articles/actions.html

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../spatial/spatial"
require "../temporal/temporal"

module Robotics
  VERSION = "0.1.0"

  # Exception classes
  class RoboticsException < Exception
  end

  class ROSConnectionException < RoboticsException
  end

  class MessageSerializationException < RoboticsException
  end

  class ServiceTimeoutException < RoboticsException
  end

  class ActionFailedException < RoboticsException
  end

  # ROS Message Types
  module MessageTypes
    # Standard message types
    enum PrimitiveType
      BOOL
      INT8
      UINT8
      INT16
      UINT16
      INT32
      UINT32
      INT64
      UINT64
      FLOAT32
      FLOAT64
      STRING
      TIME
      DURATION
    end

    # Generic ROS message structure
    abstract class ROSMessage
      abstract def serialize : Bytes
      abstract def message_type : String
    end

    # Header message (std_msgs/Header)
    class Header < ROSMessage
      property seq : UInt32
      property stamp : Temporal::TimePoint
      property frame_id : String

      def initialize(@seq : UInt32 = 0_u32,
                     @stamp : Temporal::TimePoint = Temporal::TimePoint.now,
                     @frame_id : String = "")
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write_bytes(@seq, IO::ByteFormat::LittleEndian)
        io.write_bytes(@stamp.timestamp.to_u64, IO::ByteFormat::LittleEndian)
        io.write_bytes(@frame_id.bytesize.to_u32, IO::ByteFormat::LittleEndian)
        io.write(@frame_id.to_slice)
        io.to_slice
      end

      def message_type : String
        "std_msgs/Header"
      end
    end

    # Point message (geometry_msgs/Point)
    class Point < ROSMessage
      property x : Float64
      property y : Float64
      property z : Float64

      def initialize(@x : Float64 = 0.0, @y : Float64 = 0.0, @z : Float64 = 0.0)
      end

      def self.from_vector(v : Spatial::Vector3) : Point
        new(v.x, v.y, v.z)
      end

      def to_vector : Spatial::Vector3
        Spatial::Vector3.new(@x, @y, @z)
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write_bytes(@x, IO::ByteFormat::LittleEndian)
        io.write_bytes(@y, IO::ByteFormat::LittleEndian)
        io.write_bytes(@z, IO::ByteFormat::LittleEndian)
        io.to_slice
      end

      def message_type : String
        "geometry_msgs/Point"
      end
    end

    # Quaternion message (geometry_msgs/Quaternion)
    class Quaternion < ROSMessage
      property x : Float64
      property y : Float64
      property z : Float64
      property w : Float64

      def initialize(@x : Float64 = 0.0, @y : Float64 = 0.0,
                     @z : Float64 = 0.0, @w : Float64 = 1.0)
      end

      def self.from_euler(roll : Float64, pitch : Float64, yaw : Float64) : Quaternion
        cy = Math.cos(yaw * 0.5)
        sy = Math.sin(yaw * 0.5)
        cp = Math.cos(pitch * 0.5)
        sp = Math.sin(pitch * 0.5)
        cr = Math.cos(roll * 0.5)
        sr = Math.sin(roll * 0.5)

        new(
          sr * cp * cy - cr * sp * sy,
          cr * sp * cy + sr * cp * sy,
          cr * cp * sy - sr * sp * cy,
          cr * cp * cy + sr * sp * sy
        )
      end

      def to_euler : Tuple(Float64, Float64, Float64)
        # Roll (x-axis rotation)
        sinr_cosp = 2.0 * (@w * @x + @y * @z)
        cosr_cosp = 1.0 - 2.0 * (@x * @x + @y * @y)
        roll = Math.atan2(sinr_cosp, cosr_cosp)

        # Pitch (y-axis rotation)
        sinp = 2.0 * (@w * @y - @z * @x)
        pitch = sinp.abs >= 1.0 ? Math.copysign(Math::PI / 2, sinp) : Math.asin(sinp)

        # Yaw (z-axis rotation)
        siny_cosp = 2.0 * (@w * @z + @x * @y)
        cosy_cosp = 1.0 - 2.0 * (@y * @y + @z * @z)
        yaw = Math.atan2(siny_cosp, cosy_cosp)

        {roll, pitch, yaw}
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write_bytes(@x, IO::ByteFormat::LittleEndian)
        io.write_bytes(@y, IO::ByteFormat::LittleEndian)
        io.write_bytes(@z, IO::ByteFormat::LittleEndian)
        io.write_bytes(@w, IO::ByteFormat::LittleEndian)
        io.to_slice
      end

      def message_type : String
        "geometry_msgs/Quaternion"
      end
    end

    # Pose message (geometry_msgs/Pose)
    class Pose < ROSMessage
      property position : Point
      property orientation : Quaternion

      def initialize(@position : Point = Point.new,
                     @orientation : Quaternion = Quaternion.new)
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write(@position.serialize)
        io.write(@orientation.serialize)
        io.to_slice
      end

      def message_type : String
        "geometry_msgs/Pose"
      end
    end

    # PoseStamped message (geometry_msgs/PoseStamped)
    class PoseStamped < ROSMessage
      property header : Header
      property pose : Pose

      def initialize(@header : Header = Header.new, @pose : Pose = Pose.new)
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write(@header.serialize)
        io.write(@pose.serialize)
        io.to_slice
      end

      def message_type : String
        "geometry_msgs/PoseStamped"
      end
    end

    # Twist message (geometry_msgs/Twist)
    class Twist < ROSMessage
      property linear : Point
      property angular : Point

      def initialize(@linear : Point = Point.new, @angular : Point = Point.new)
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write(@linear.serialize)
        io.write(@angular.serialize)
        io.to_slice
      end

      def message_type : String
        "geometry_msgs/Twist"
      end
    end

    # Odometry message (nav_msgs/Odometry)
    class Odometry < ROSMessage
      property header : Header
      property child_frame_id : String
      property pose : Pose
      property twist : Twist

      def initialize(@header : Header = Header.new,
                     @child_frame_id : String = "",
                     @pose : Pose = Pose.new,
                     @twist : Twist = Twist.new)
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write(@header.serialize)
        io.write_bytes(@child_frame_id.bytesize.to_u32, IO::ByteFormat::LittleEndian)
        io.write(@child_frame_id.to_slice)
        io.write(@pose.serialize)
        io.write(@twist.serialize)
        io.to_slice
      end

      def message_type : String
        "nav_msgs/Odometry"
      end
    end

    # LaserScan message (sensor_msgs/LaserScan)
    class LaserScan < ROSMessage
      property header : Header
      property angle_min : Float32
      property angle_max : Float32
      property angle_increment : Float32
      property time_increment : Float32
      property scan_time : Float32
      property range_min : Float32
      property range_max : Float32
      property ranges : Array(Float32)
      property intensities : Array(Float32)

      def initialize(@header : Header = Header.new)
        @angle_min = 0.0_f32
        @angle_max = Math::PI.to_f32 * 2
        @angle_increment = 0.01_f32
        @time_increment = 0.0_f32
        @scan_time = 0.1_f32
        @range_min = 0.1_f32
        @range_max = 30.0_f32
        @ranges = [] of Float32
        @intensities = [] of Float32
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write(@header.serialize)
        io.write_bytes(@angle_min, IO::ByteFormat::LittleEndian)
        io.write_bytes(@angle_max, IO::ByteFormat::LittleEndian)
        io.write_bytes(@angle_increment, IO::ByteFormat::LittleEndian)
        io.write_bytes(@time_increment, IO::ByteFormat::LittleEndian)
        io.write_bytes(@scan_time, IO::ByteFormat::LittleEndian)
        io.write_bytes(@range_min, IO::ByteFormat::LittleEndian)
        io.write_bytes(@range_max, IO::ByteFormat::LittleEndian)
        io.write_bytes(@ranges.size.to_u32, IO::ByteFormat::LittleEndian)
        @ranges.each { |r| io.write_bytes(r, IO::ByteFormat::LittleEndian) }
        io.write_bytes(@intensities.size.to_u32, IO::ByteFormat::LittleEndian)
        @intensities.each { |i| io.write_bytes(i, IO::ByteFormat::LittleEndian) }
        io.to_slice
      end

      def message_type : String
        "sensor_msgs/LaserScan"
      end
    end

    # Image message (sensor_msgs/Image)
    class Image < ROSMessage
      property header : Header
      property height : UInt32
      property width : UInt32
      property encoding : String
      property is_bigendian : UInt8
      property step : UInt32
      property data : Bytes

      def initialize(@header : Header = Header.new,
                     @height : UInt32 = 0_u32,
                     @width : UInt32 = 0_u32,
                     @encoding : String = "rgb8")
        @is_bigendian = 0_u8
        @step = @width * 3  # Assuming RGB8
        @data = Bytes.new(0)
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write(@header.serialize)
        io.write_bytes(@height, IO::ByteFormat::LittleEndian)
        io.write_bytes(@width, IO::ByteFormat::LittleEndian)
        io.write_bytes(@encoding.bytesize.to_u32, IO::ByteFormat::LittleEndian)
        io.write(@encoding.to_slice)
        io.write_bytes(@is_bigendian, IO::ByteFormat::LittleEndian)
        io.write_bytes(@step, IO::ByteFormat::LittleEndian)
        io.write_bytes(@data.size.to_u32, IO::ByteFormat::LittleEndian)
        io.write(@data)
        io.to_slice
      end

      def message_type : String
        "sensor_msgs/Image"
      end
    end

    # JointState message (sensor_msgs/JointState)
    class JointState < ROSMessage
      property header : Header
      property name : Array(String)
      property position : Array(Float64)
      property velocity : Array(Float64)
      property effort : Array(Float64)

      def initialize(@header : Header = Header.new)
        @name = [] of String
        @position = [] of Float64
        @velocity = [] of Float64
        @effort = [] of Float64
      end

      def serialize : Bytes
        io = IO::Memory.new
        io.write(@header.serialize)
        # Names
        io.write_bytes(@name.size.to_u32, IO::ByteFormat::LittleEndian)
        @name.each do |n|
          io.write_bytes(n.bytesize.to_u32, IO::ByteFormat::LittleEndian)
          io.write(n.to_slice)
        end
        # Positions
        io.write_bytes(@position.size.to_u32, IO::ByteFormat::LittleEndian)
        @position.each { |p| io.write_bytes(p, IO::ByteFormat::LittleEndian) }
        # Velocities
        io.write_bytes(@velocity.size.to_u32, IO::ByteFormat::LittleEndian)
        @velocity.each { |v| io.write_bytes(v, IO::ByteFormat::LittleEndian) }
        # Efforts
        io.write_bytes(@effort.size.to_u32, IO::ByteFormat::LittleEndian)
        @effort.each { |e| io.write_bytes(e, IO::ByteFormat::LittleEndian) }
        io.to_slice
      end

      def message_type : String
        "sensor_msgs/JointState"
      end
    end
  end

  # ROS Topic abstraction
  class Topic(T)
    getter name : String
    getter message_type : String
    getter queue_size : Int32
    @subscribers : Array(Proc(T, Nil))
    @messages : Array(T)

    def initialize(@name : String, @message_type : String, @queue_size : Int32 = 10)
      @subscribers = [] of Proc(T, Nil)
      @messages = [] of T
      CogUtil::Logger.debug("Created topic: #{@name} (#{@message_type})")
    end

    def subscribe(&callback : Proc(T, Nil))
      @subscribers << callback
    end

    def publish(message : T)
      @messages << message
      @messages.shift if @messages.size > @queue_size

      @subscribers.each do |callback|
        begin
          callback.call(message)
        rescue ex
          CogUtil::Logger.error("Error in topic callback: #{ex.message}")
        end
      end
    end

    def latest : T?
      @messages.last?
    end
  end

  # ROS Service abstraction
  class Service(TReq, TRes)
    getter name : String
    getter request_type : String
    getter response_type : String
    @handler : Proc(TReq, TRes)?

    def initialize(@name : String, @request_type : String, @response_type : String)
      @handler = nil
      CogUtil::Logger.debug("Created service: #{@name}")
    end

    def set_handler(&handler : Proc(TReq, TRes))
      @handler = handler
    end

    def call(request : TReq, timeout : Float64 = 5.0) : TRes
      if handler = @handler
        handler.call(request)
      else
        raise ServiceTimeoutException.new("Service #{@name} has no handler")
      end
    end
  end

  # ROS Action Goal Status
  enum GoalStatus
    PENDING
    ACTIVE
    PREEMPTED
    SUCCEEDED
    ABORTED
    REJECTED
    PREEMPTING
    RECALLING
    RECALLED
    LOST
  end

  # ROS Action abstraction
  class Action(TGoal, TResult, TFeedback)
    getter name : String
    getter status : GoalStatus
    @goal_handler : Proc(TGoal, Proc(TFeedback, Nil), TResult)?
    @feedback_callback : Proc(TFeedback, Nil)?
    @result : TResult?

    def initialize(@name : String)
      @status = GoalStatus::PENDING
      @goal_handler = nil
      @feedback_callback = nil
      @result = nil
      CogUtil::Logger.debug("Created action: #{@name}")
    end

    def set_handler(&handler : Proc(TGoal, Proc(TFeedback, Nil), TResult))
      @goal_handler = handler
    end

    def send_goal(goal : TGoal, &feedback_callback : Proc(TFeedback, Nil)) : Bool
      @feedback_callback = feedback_callback
      @status = GoalStatus::ACTIVE

      if handler = @goal_handler
        begin
          @result = handler.call(goal, feedback_callback)
          @status = GoalStatus::SUCCEEDED
          true
        rescue ex
          CogUtil::Logger.error("Action failed: #{ex.message}")
          @status = GoalStatus::ABORTED
          false
        end
      else
        @status = GoalStatus::REJECTED
        false
      end
    end

    def cancel
      @status = GoalStatus::PREEMPTED
    end

    def result : TResult?
      @result
    end
  end

  # Transform between coordinate frames
  struct Transform
    property translation : Spatial::Vector3
    property rotation : MessageTypes::Quaternion
    property frame_id : String
    property child_frame_id : String
    property timestamp : Temporal::TimePoint

    def initialize(@frame_id : String, @child_frame_id : String,
                   @translation : Spatial::Vector3 = Spatial::Vector3.new,
                   @rotation : MessageTypes::Quaternion = MessageTypes::Quaternion.new,
                   @timestamp : Temporal::TimePoint = Temporal::TimePoint.now)
    end

    def apply(point : Spatial::Vector3) : Spatial::Vector3
      # Apply rotation then translation
      rotated = rotate_by_quaternion(point, @rotation)
      rotated + @translation
    end

    def inverse : Transform
      # Inverse rotation
      inv_rotation = MessageTypes::Quaternion.new(-@rotation.x, -@rotation.y, -@rotation.z, @rotation.w)
      # Inverse translation (rotated)
      inv_translation = rotate_by_quaternion(@translation * -1.0, inv_rotation)

      Transform.new(@child_frame_id, @frame_id, inv_translation, inv_rotation, @timestamp)
    end

    private def rotate_by_quaternion(v : Spatial::Vector3, q : MessageTypes::Quaternion) : Spatial::Vector3
      # Quaternion rotation: q * v * q^-1
      u = Spatial::Vector3.new(q.x, q.y, q.z)
      s = q.w

      Spatial::Vector3.new(
        2.0 * u.dot(v) * u.x + (s * s - u.dot(u)) * v.x + 2.0 * s * (u.y * v.z - u.z * v.y),
        2.0 * u.dot(v) * u.y + (s * s - u.dot(u)) * v.y + 2.0 * s * (u.z * v.x - u.x * v.z),
        2.0 * u.dot(v) * u.z + (s * s - u.dot(u)) * v.z + 2.0 * s * (u.x * v.y - u.y * v.x)
      )
    end
  end

  # Transform buffer for TF lookups
  class TransformBuffer
    getter transforms : Hash(Tuple(String, String), Transform)
    @buffer_duration : Temporal::Duration

    def initialize(@buffer_duration : Temporal::Duration = Temporal::Duration.seconds(10))
      @transforms = {} of Tuple(String, String) => Transform
      CogUtil::Logger.info("TransformBuffer initialized")
    end

    def set_transform(transform : Transform)
      key = {transform.frame_id, transform.child_frame_id}
      @transforms[key] = transform
    end

    def lookup_transform(target_frame : String, source_frame : String) : Transform?
      # Direct lookup
      if tf = @transforms[{target_frame, source_frame}]?
        return tf
      end

      # Try inverse
      if tf = @transforms[{source_frame, target_frame}]?
        return tf.inverse
      end

      # TODO: Implement transform chain resolution
      nil
    end

    def can_transform(target_frame : String, source_frame : String) : Bool
      !lookup_transform(target_frame, source_frame).nil?
    end

    def clear
      @transforms.clear
    end
  end

  # ROS Node abstraction
  class ROSNode
    getter name : String
    getter namespace : String
    getter topics : Hash(String, Topic(MessageTypes::ROSMessage))
    getter transform_buffer : TransformBuffer
    getter parameters : Hash(String, String | Int32 | Float64 | Bool)
    @running : Bool

    def initialize(@name : String, @namespace : String = "")
      @topics = {} of String => Topic(MessageTypes::ROSMessage)
      @transform_buffer = TransformBuffer.new
      @parameters = {} of String => String | Int32 | Float64 | Bool
      @running = false
      CogUtil::Logger.info("ROSNode '#{full_name}' initialized")
    end

    def full_name : String
      @namespace.empty? ? @name : "#{@namespace}/#{@name}"
    end

    # Passing the message class makes the generic type inferable at the call site,
    # e.g. create_topic(MessageTypes::Twist, "cmd_vel").
    def create_topic(message_type : T.class, name : String, queue_size : Int32 = 10) : Topic(T) forall T
      topic_name = resolve_name(name)
      topic = Topic(T).new(topic_name, message_type.name, queue_size)
      CogUtil::Logger.debug("Created topic: #{topic_name}")
      topic
    end

    def set_parameter(name : String, value : String | Int32 | Float64 | Bool)
      @parameters[name] = value
      CogUtil::Logger.debug("Set parameter #{name} = #{value}")
    end

    def get_parameter(name : String, default : String | Int32 | Float64 | Bool) : String | Int32 | Float64 | Bool
      @parameters[name]? || default
    end

    def start
      @running = true
      CogUtil::Logger.info("ROSNode '#{full_name}' started")
    end

    def stop
      @running = false
      CogUtil::Logger.info("ROSNode '#{full_name}' stopped")
    end

    def running? : Bool
      @running
    end

    def spin_once
      # Process pending callbacks (simulated)
    end

    private def resolve_name(name : String) : String
      if name.starts_with?("/")
        name
      elsif name.starts_with?("~")
        "/#{full_name}#{name[1..]}"
      else
        @namespace.empty? ? "/#{name}" : "/#{@namespace}/#{name}"
      end
    end
  end

  # Navigation Goal for move_base
  class NavigationGoal
    property target_pose : MessageTypes::PoseStamped
    property tolerance : Float64

    def initialize(@target_pose : MessageTypes::PoseStamped, @tolerance : Float64 = 0.1)
    end
  end

  # Navigation Result
  struct NavigationResult
    property success : Bool
    property final_pose : MessageTypes::PoseStamped
    property distance_traveled : Float64
    property time_elapsed : Temporal::Duration

    def initialize(@success : Bool,
                   @final_pose : MessageTypes::PoseStamped,
                   @distance_traveled : Float64 = 0.0,
                   @time_elapsed : Temporal::Duration = Temporal::Duration.zero)
    end
  end

  # Navigation interface for move_base integration
  class Navigator
    getter node : ROSNode
    getter current_pose : MessageTypes::PoseStamped?
    getter goal_tolerance : Float64
    @odom_topic : Topic(MessageTypes::Odometry)?
    @cmd_vel_topic : Topic(MessageTypes::Twist)?

    def initialize(@node : ROSNode, @goal_tolerance : Float64 = 0.1)
      @current_pose = nil
      setup_topics
      CogUtil::Logger.info("Navigator initialized")
    end

    def go_to(goal : NavigationGoal) : NavigationResult
      CogUtil::Logger.info("Navigating to goal at (#{goal.target_pose.pose.position.x}, #{goal.target_pose.pose.position.y})")

      start_time = Temporal::TimePoint.now
      distance = 0.0

      # Simulated navigation loop
      if current = @current_pose
        target_point = goal.target_pose.pose.position.to_vector
        current_point = current.pose.position.to_vector
        distance = current_point.distance_to(target_point)

        # Simulate reaching the goal
        @current_pose = goal.target_pose

        elapsed = Temporal::TimePoint.now - start_time
        CogUtil::Logger.info("Navigation completed in #{elapsed}")

        NavigationResult.new(
          success: true,
          final_pose: goal.target_pose,
          distance_traveled: distance,
          time_elapsed: elapsed
        )
      else
        CogUtil::Logger.warn("No current pose available")
        NavigationResult.new(
          success: false,
          final_pose: goal.target_pose,
          distance_traveled: 0.0,
          time_elapsed: Temporal::Duration.zero
        )
      end
    end

    def cancel_goal
      CogUtil::Logger.info("Navigation goal cancelled")
    end

    def set_velocity(linear : Float64, angular : Float64)
      twist = MessageTypes::Twist.new(
        MessageTypes::Point.new(linear, 0.0, 0.0),
        MessageTypes::Point.new(0.0, 0.0, angular)
      )

      if topic = @cmd_vel_topic
        topic.publish(twist)
      end
    end

    def update_pose(pose : MessageTypes::PoseStamped)
      @current_pose = pose
    end

    private def setup_topics
      @cmd_vel_topic = @node.create_topic(MessageTypes::Twist, "cmd_vel")
      @odom_topic = @node.create_topic(MessageTypes::Odometry, "odom")
    end
  end

  # Robot state representation
  class RobotState
    getter pose : MessageTypes::PoseStamped?
    getter velocity : MessageTypes::Twist?
    getter joint_states : MessageTypes::JointState?
    getter battery_level : Float64
    getter is_emergency_stop : Bool
    getter sensors : Hash(String, MessageTypes::ROSMessage)

    def initialize
      @pose = nil
      @velocity = nil
      @joint_states = nil
      @battery_level = 1.0
      @is_emergency_stop = false
      @sensors = {} of String => MessageTypes::ROSMessage
    end

    def update_pose(pose : MessageTypes::PoseStamped)
      @pose = pose
    end

    def update_velocity(velocity : MessageTypes::Twist)
      @velocity = velocity
    end

    def update_joint_states(states : MessageTypes::JointState)
      @joint_states = states
    end

    def update_sensor(name : String, data : MessageTypes::ROSMessage)
      @sensors[name] = data
    end

    def set_battery_level(level : Float64)
      @battery_level = level.clamp(0.0, 1.0)
    end

    def set_emergency_stop(active : Bool)
      @is_emergency_stop = active
    end

    def is_operational? : Bool
      !@is_emergency_stop && @battery_level > 0.1
    end

    # Convert to AtomSpace representation
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      robot_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "robot")
      atoms << robot_node

      # Add pose
      if pose = @pose
        pose_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "has_pose")
        pos = pose.pose.position
        pose_val = atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          "(#{pos.x}, #{pos.y}, #{pos.z})"
        )
        atoms << atomspace.add_link(
          AtomSpace::AtomType::EVALUATION_LINK,
          [pose_pred, atomspace.add_link(
            AtomSpace::AtomType::LIST_LINK,
            [robot_node, pose_val]
          )]
        )
      end

      # Add battery level
      battery_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "battery_level")
      battery_val = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, @battery_level.to_s)
      atoms << atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [battery_pred, atomspace.add_link(
          AtomSpace::AtomType::LIST_LINK,
          [robot_node, battery_val]
        )]
      )

      # Add operational status
      status_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "is_operational")
      status_val = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        is_operational?.to_s
      )
      atoms << atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [status_pred, atomspace.add_link(
          AtomSpace::AtomType::LIST_LINK,
          [robot_node, status_val]
        )]
      )

      atoms
    end
  end

  # ROS Bridge - main interface for ROS integration
  class ROSBridge
    getter node : ROSNode
    getter robot_state : RobotState
    getter navigator : Navigator
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace,
                   node_name : String = "crystalcog_bridge",
                   namespace : String = "")
      @node = ROSNode.new(node_name, namespace)
      @robot_state = RobotState.new
      @navigator = Navigator.new(@node)
      CogUtil::Logger.info("ROSBridge initialized")
    end

    def connect
      @node.start
      CogUtil::Logger.info("ROSBridge connected")
    end

    def disconnect
      @node.stop
      CogUtil::Logger.info("ROSBridge disconnected")
    end

    def sync_to_atomspace
      @robot_state.to_atomspace(@atomspace)
    end

    def navigate_to(x : Float64, y : Float64, theta : Float64 = 0.0) : NavigationResult
      pose = MessageTypes::PoseStamped.new(
        MessageTypes::Header.new(frame_id: "map"),
        MessageTypes::Pose.new(
          MessageTypes::Point.new(x, y, 0.0),
          MessageTypes::Quaternion.from_euler(0.0, 0.0, theta)
        )
      )
      goal = NavigationGoal.new(pose)
      @navigator.go_to(goal)
    end

    def get_robot_pose : MessageTypes::PoseStamped?
      @robot_state.pose
    end

    def is_connected? : Bool
      @node.running?
    end
  end

  # Module-level convenience methods
  def self.create_node(name : String, namespace : String = "") : ROSNode
    ROSNode.new(name, namespace)
  end

  def self.create_bridge(atomspace : AtomSpace::AtomSpace) : ROSBridge
    ROSBridge.new(atomspace)
  end

  def self.point(x : Float64, y : Float64, z : Float64 = 0.0) : MessageTypes::Point
    MessageTypes::Point.new(x, y, z)
  end

  def self.pose(x : Float64, y : Float64, theta : Float64 = 0.0) : MessageTypes::Pose
    MessageTypes::Pose.new(
      MessageTypes::Point.new(x, y, 0.0),
      MessageTypes::Quaternion.from_euler(0.0, 0.0, theta)
    )
  end
end
