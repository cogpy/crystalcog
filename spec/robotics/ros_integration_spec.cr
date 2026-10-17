require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/spatial/spatial"
require "../../src/temporal/temporal"
require "../../src/robotics/ros_integration"

describe Robotics do
  describe Robotics::MessageTypes::Point do
    it "creates a point with default values" do
      point = Robotics::MessageTypes::Point.new
      point.x.should eq(0.0)
      point.y.should eq(0.0)
      point.z.should eq(0.0)
    end

    it "creates a point from spatial vector" do
      vec = Spatial::Vector3.new(1.0, 2.0, 3.0)
      point = Robotics::MessageTypes::Point.from_vector(vec)
      point.x.should eq(1.0)
      point.y.should eq(2.0)
      point.z.should eq(3.0)
    end

    it "converts to spatial vector" do
      point = Robotics::MessageTypes::Point.new(1.0, 2.0, 3.0)
      vec = point.to_vector
      vec.x.should eq(1.0)
      vec.y.should eq(2.0)
      vec.z.should eq(3.0)
    end
  end

  describe Robotics::MessageTypes::Quaternion do
    it "creates identity quaternion" do
      quat = Robotics::MessageTypes::Quaternion.new
      quat.w.should eq(1.0)
      quat.x.should eq(0.0)
      quat.y.should eq(0.0)
      quat.z.should eq(0.0)
    end

    it "creates quaternion from euler angles" do
      quat = Robotics::MessageTypes::Quaternion.from_euler(0.0, 0.0, Math::PI / 2)
      quat.w.should be_close(0.7071, 0.01)
      quat.z.should be_close(0.7071, 0.01)
    end

    it "converts quaternion to euler angles" do
      quat = Robotics::MessageTypes::Quaternion.from_euler(0.1, 0.2, 0.3)
      roll, pitch, yaw = quat.to_euler
      roll.should be_close(0.1, 0.01)
      pitch.should be_close(0.2, 0.01)
      yaw.should be_close(0.3, 0.01)
    end
  end

  describe Robotics::Transform do
    it "creates identity transform" do
      tf = Robotics::Transform.new("world", "base_link")
      tf.frame_id.should eq("world")
      tf.child_frame_id.should eq("base_link")
    end

    it "applies transform to point" do
      translation = Spatial::Vector3.new(1.0, 0.0, 0.0)
      tf = Robotics::Transform.new("world", "base_link", translation)

      point = Spatial::Vector3.new(0.0, 0.0, 0.0)
      result = tf.apply(point)

      result.x.should be_close(1.0, 0.01)
      result.y.should be_close(0.0, 0.01)
      result.z.should be_close(0.0, 0.01)
    end

    it "computes inverse transform" do
      translation = Spatial::Vector3.new(1.0, 2.0, 3.0)
      tf = Robotics::Transform.new("world", "base_link", translation)

      inv = tf.inverse
      inv.frame_id.should eq("base_link")
      inv.child_frame_id.should eq("world")
    end
  end

  describe Robotics::TransformBuffer do
    it "stores and retrieves transforms" do
      buffer = Robotics::TransformBuffer.new

      tf = Robotics::Transform.new("world", "base_link")
      buffer.set_transform(tf)

      result = buffer.lookup_transform("world", "base_link")
      result.should_not be_nil
      result.not_nil!.frame_id.should eq("world")
    end

    it "retrieves inverse transform" do
      buffer = Robotics::TransformBuffer.new

      tf = Robotics::Transform.new("world", "base_link")
      buffer.set_transform(tf)

      result = buffer.lookup_transform("base_link", "world")
      result.should_not be_nil
      result.not_nil!.frame_id.should eq("base_link")
    end

    it "checks if transform exists" do
      buffer = Robotics::TransformBuffer.new

      tf = Robotics::Transform.new("world", "base_link")
      buffer.set_transform(tf)

      buffer.can_transform("world", "base_link").should be_true
      buffer.can_transform("world", "camera").should be_false
    end
  end

  describe Robotics::ROSNode do
    it "creates node with name and namespace" do
      node = Robotics::ROSNode.new("test_node", "my_namespace")
      node.name.should eq("test_node")
      node.namespace.should eq("my_namespace")
      node.full_name.should eq("my_namespace/test_node")
    end

    it "starts and stops node" do
      node = Robotics::ROSNode.new("test_node")
      node.running?.should be_false

      node.start
      node.running?.should be_true

      node.stop
      node.running?.should be_false
    end

    it "manages parameters" do
      node = Robotics::ROSNode.new("test_node")

      node.set_parameter("max_speed", 1.5)
      result = node.get_parameter("max_speed", 0.0)
      result.should eq(1.5)

      # Default value when parameter doesn't exist
      result = node.get_parameter("unknown", 42.0)
      result.should eq(42.0)
    end
  end

  describe Robotics::RobotState do
    it "creates robot state" do
      state = Robotics::RobotState.new
      state.battery_level.should eq(1.0)
      state.is_emergency_stop.should be_false
      state.is_operational?.should be_true
    end

    it "updates battery level" do
      state = Robotics::RobotState.new
      state.set_battery_level(0.5)
      state.battery_level.should eq(0.5)

      # Clamping
      state.set_battery_level(1.5)
      state.battery_level.should eq(1.0)
    end

    it "handles emergency stop" do
      state = Robotics::RobotState.new
      state.is_operational?.should be_true

      state.set_emergency_stop(true)
      state.is_operational?.should be_false
    end

    it "converts to atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      state = Robotics::RobotState.new

      atoms = state.to_atomspace(atomspace)
      atoms.should_not be_empty
    end
  end

  describe Robotics::ROSBridge do
    it "creates ROS bridge" do
      atomspace = AtomSpace::AtomSpace.new
      bridge = Robotics::ROSBridge.new(atomspace)

      bridge.is_connected?.should be_false

      bridge.connect
      bridge.is_connected?.should be_true

      bridge.disconnect
      bridge.is_connected?.should be_false
    end

    it "syncs robot state to atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      bridge = Robotics::ROSBridge.new(atomspace)

      bridge.sync_to_atomspace
      atomspace.size.should be > 0
    end
  end

  describe "Module convenience methods" do
    it "creates node" do
      node = Robotics.create_node("test_node")
      node.name.should eq("test_node")
    end

    it "creates bridge" do
      atomspace = AtomSpace::AtomSpace.new
      bridge = Robotics.create_bridge(atomspace)
      bridge.should_not be_nil
    end

    it "creates point" do
      point = Robotics.point(1.0, 2.0, 3.0)
      point.x.should eq(1.0)
      point.y.should eq(2.0)
      point.z.should eq(3.0)
    end

    it "creates pose" do
      pose = Robotics.pose(1.0, 2.0, 0.5)
      pose.position.x.should eq(1.0)
      pose.position.y.should eq(2.0)
    end
  end
end
