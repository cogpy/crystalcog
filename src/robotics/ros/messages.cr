# ROS Message Type Definitions for CrystalCog
# Standard message types compatible with ROS1/ROS2

module CrystalCog::Robotics::ROS
  # Base message interface
  abstract class Message
    abstract def to_json(json : JSON::Builder)
    abstract def message_type : String
  end

  # Standard header for timestamped messages
  class Header < Message
    property seq : UInt32 = 0_u32
    property stamp : Time = Time.utc
    property frame_id : String = ""

    def initialize(@seq = 0_u32, @stamp = Time.utc, @frame_id = "")
    end

    def message_type : String
      "std_msgs/Header"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "seq", @seq
        json.field "stamp" do
          json.object do
            json.field "secs", @stamp.to_unix
            json.field "nsecs", @stamp.nanosecond
          end
        end
        json.field "frame_id", @frame_id
      end
    end
  end

  # 3D Point
  class Point < Message
    property x : Float64 = 0.0
    property y : Float64 = 0.0
    property z : Float64 = 0.0

    def initialize(@x = 0.0, @y = 0.0, @z = 0.0)
    end

    def message_type : String
      "geometry_msgs/Point"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "x", @x
        json.field "y", @y
        json.field "z", @z
      end
    end

    def distance_to(other : Point) : Float64
      Math.sqrt((@x - other.x)**2 + (@y - other.y)**2 + (@z - other.z)**2)
    end
  end

  # Quaternion orientation
  class Quaternion < Message
    property x : Float64 = 0.0
    property y : Float64 = 0.0
    property z : Float64 = 0.0
    property w : Float64 = 1.0

    def initialize(@x = 0.0, @y = 0.0, @z = 0.0, @w = 1.0)
    end

    def message_type : String
      "geometry_msgs/Quaternion"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "x", @x
        json.field "y", @y
        json.field "z", @z
        json.field "w", @w
      end
    end

    def self.from_euler(roll : Float64, pitch : Float64, yaw : Float64) : Quaternion
      cy = Math.cos(yaw * 0.5)
      sy = Math.sin(yaw * 0.5)
      cp = Math.cos(pitch * 0.5)
      sp = Math.sin(pitch * 0.5)
      cr = Math.cos(roll * 0.5)
      sr = Math.sin(roll * 0.5)

      Quaternion.new(
        x: sr * cp * cy - cr * sp * sy,
        y: cr * sp * cy + sr * cp * sy,
        z: cr * cp * sy - sr * sp * cy,
        w: cr * cp * cy + sr * sp * sy
      )
    end
  end

  # Pose (position + orientation)
  class Pose < Message
    property position : Point
    property orientation : Quaternion

    def initialize(@position = Point.new, @orientation = Quaternion.new)
    end

    def message_type : String
      "geometry_msgs/Pose"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "position" { @position.to_json(json) }
        json.field "orientation" { @orientation.to_json(json) }
      end
    end
  end

  # 3D Vector
  class Vector3 < Message
    property x : Float64 = 0.0
    property y : Float64 = 0.0
    property z : Float64 = 0.0

    def initialize(@x = 0.0, @y = 0.0, @z = 0.0)
    end

    def message_type : String
      "geometry_msgs/Vector3"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "x", @x
        json.field "y", @y
        json.field "z", @z
      end
    end

    def magnitude : Float64
      Math.sqrt(@x**2 + @y**2 + @z**2)
    end
  end

  # Twist (linear + angular velocity)
  class Twist < Message
    property linear : Vector3
    property angular : Vector3

    def initialize(@linear = Vector3.new, @angular = Vector3.new)
    end

    def message_type : String
      "geometry_msgs/Twist"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "linear" { @linear.to_json(json) }
        json.field "angular" { @angular.to_json(json) }
      end
    end
  end

  # Laser scan data
  class LaserScan < Message
    property header : Header
    property angle_min : Float32 = 0.0_f32
    property angle_max : Float32 = 0.0_f32
    property angle_increment : Float32 = 0.0_f32
    property time_increment : Float32 = 0.0_f32
    property scan_time : Float32 = 0.0_f32
    property range_min : Float32 = 0.0_f32
    property range_max : Float32 = 0.0_f32
    property ranges : Array(Float32) = [] of Float32
    property intensities : Array(Float32) = [] of Float32

    def initialize(@header = Header.new)
    end

    def message_type : String
      "sensor_msgs/LaserScan"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "header" { @header.to_json(json) }
        json.field "angle_min", @angle_min
        json.field "angle_max", @angle_max
        json.field "angle_increment", @angle_increment
        json.field "time_increment", @time_increment
        json.field "scan_time", @scan_time
        json.field "range_min", @range_min
        json.field "range_max", @range_max
        json.field "ranges", @ranges
        json.field "intensities", @intensities
      end
    end
  end

  # Odometry
  class Odometry < Message
    property header : Header
    property child_frame_id : String = ""
    property pose : Pose
    property twist : Twist

    def initialize(@header = Header.new, @pose = Pose.new, @twist = Twist.new)
    end

    def message_type : String
      "nav_msgs/Odometry"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "header" { @header.to_json(json) }
        json.field "child_frame_id", @child_frame_id
        json.field "pose" do
          json.object do
            json.field "pose" { @pose.to_json(json) }
          end
        end
        json.field "twist" do
          json.object do
            json.field "twist" { @twist.to_json(json) }
          end
        end
      end
    end
  end

  # Image message
  class Image < Message
    property header : Header
    property height : UInt32 = 0_u32
    property width : UInt32 = 0_u32
    property encoding : String = "rgb8"
    property is_bigendian : UInt8 = 0_u8
    property step : UInt32 = 0_u32
    property data : Bytes = Bytes.empty

    def initialize(@header = Header.new)
    end

    def message_type : String
      "sensor_msgs/Image"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "header" { @header.to_json(json) }
        json.field "height", @height
        json.field "width", @width
        json.field "encoding", @encoding
        json.field "is_bigendian", @is_bigendian
        json.field "step", @step
        json.field "data", Base64.strict_encode(@data)
      end
    end
  end

  # JointState for robot arm control
  class JointState < Message
    property header : Header
    property name : Array(String) = [] of String
    property position : Array(Float64) = [] of Float64
    property velocity : Array(Float64) = [] of Float64
    property effort : Array(Float64) = [] of Float64

    def initialize(@header = Header.new)
    end

    def message_type : String
      "sensor_msgs/JointState"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "header" { @header.to_json(json) }
        json.field "name", @name
        json.field "position", @position
        json.field "velocity", @velocity
        json.field "effort", @effort
      end
    end
  end

  # Transform for TF2
  class Transform < Message
    property translation : Vector3
    property rotation : Quaternion

    def initialize(@translation = Vector3.new, @rotation = Quaternion.new)
    end

    def message_type : String
      "geometry_msgs/Transform"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "translation" { @translation.to_json(json) }
        json.field "rotation" { @rotation.to_json(json) }
      end
    end
  end

  class TransformStamped < Message
    property header : Header
    property child_frame_id : String = ""
    property transform : Transform

    def initialize(@header = Header.new, @transform = Transform.new)
    end

    def message_type : String
      "geometry_msgs/TransformStamped"
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "header" { @header.to_json(json) }
        json.field "child_frame_id", @child_frame_id
        json.field "transform" { @transform.to_json(json) }
      end
    end
  end
end
