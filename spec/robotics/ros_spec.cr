require "../spec_helper"
require "../../src/robotics/ros/ros_main"

describe CrystalCog::Robotics::ROS do
  describe CrystalCog::Robotics::ROS::Point do
    it "creates a point with coordinates" do
      point = CrystalCog::Robotics::ROS::Point.new(x: 1.0, y: 2.0, z: 3.0)
      point.x.should eq(1.0)
      point.y.should eq(2.0)
      point.z.should eq(3.0)
    end

    it "calculates distance between points" do
      p1 = CrystalCog::Robotics::ROS::Point.new(x: 0.0, y: 0.0, z: 0.0)
      p2 = CrystalCog::Robotics::ROS::Point.new(x: 3.0, y: 4.0, z: 0.0)
      p1.distance_to(p2).should eq(5.0)
    end
  end

  describe CrystalCog::Robotics::ROS::Quaternion do
    it "creates identity quaternion by default" do
      q = CrystalCog::Robotics::ROS::Quaternion.new
      q.w.should eq(1.0)
      q.x.should eq(0.0)
      q.y.should eq(0.0)
      q.z.should eq(0.0)
    end

    it "creates quaternion from euler angles" do
      q = CrystalCog::Robotics::ROS::Quaternion.from_euler(0.0, 0.0, Math::PI/2)
      q.w.should be_close(0.7071, 0.001)
      q.z.should be_close(0.7071, 0.001)
    end
  end

  describe CrystalCog::Robotics::ROS::Vector3 do
    it "calculates magnitude" do
      v = CrystalCog::Robotics::ROS::Vector3.new(x: 3.0, y: 4.0, z: 0.0)
      v.magnitude.should eq(5.0)
    end
  end

  describe CrystalCog::Robotics::ROS::Pose do
    it "creates pose with position and orientation" do
      pos = CrystalCog::Robotics::ROS::Point.new(x: 1.0, y: 2.0, z: 3.0)
      orient = CrystalCog::Robotics::ROS::Quaternion.new
      pose = CrystalCog::Robotics::ROS::Pose.new(position: pos, orientation: orient)
      
      pose.position.x.should eq(1.0)
      pose.orientation.w.should eq(1.0)
    end
  end

  describe CrystalCog::Robotics::ROS::Header do
    it "creates header with timestamp" do
      header = CrystalCog::Robotics::ROS::Header.new(seq: 1_u32, frame_id: "base_link")
      header.seq.should eq(1)
      header.frame_id.should eq("base_link")
    end
  end

  describe CrystalCog::Robotics::ROS::Twist do
    it "creates twist with linear and angular velocities" do
      linear = CrystalCog::Robotics::ROS::Vector3.new(x: 1.0, y: 0.0, z: 0.0)
      angular = CrystalCog::Robotics::ROS::Vector3.new(x: 0.0, y: 0.0, z: 0.5)
      twist = CrystalCog::Robotics::ROS::Twist.new(linear: linear, angular: angular)
      
      twist.linear.x.should eq(1.0)
      twist.angular.z.should eq(0.5)
    end
  end

  describe CrystalCog::Robotics::ROS::BridgeConfig do
    it "creates config with defaults" do
      config = CrystalCog::Robotics::ROS::BridgeConfig.new
      config.host.should eq("localhost")
      config.port.should eq(9090)
    end
  end

  describe CrystalCog::Robotics::ROS::ROSInterface do
    it "creates interface with node name" do
      interface = CrystalCog::Robotics::ROS::ROSInterface.new("test_node")
      interface.node_name.should eq("test_node")
      interface.connected?.should be_false
    end
  end
end
