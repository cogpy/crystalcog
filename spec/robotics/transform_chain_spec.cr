require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/spatial/spatial"
require "../../src/temporal/temporal"
require "../../src/robotics/ros_integration"

private def vec(x, y, z)
  Spatial::Vector3.new(x, y, z)
end

private def close(a : Spatial::Vector3, b : Spatial::Vector3)
  a.x.should be_close(b.x, 1e-9)
  a.y.should be_close(b.y, 1e-9)
  a.z.should be_close(b.z, 1e-9)
end

describe Robotics::TransformBuffer do
  it "resolves a multi-hop chain world <- base_link <- camera" do
    buffer = Robotics::TransformBuffer.new
    buffer.set_transform(Robotics::Transform.new("world", "base_link", vec(1.0, 0.0, 0.0)))
    yaw90 = Robotics::MessageTypes::Quaternion.from_euler(0.0, 0.0, Math::PI / 2)
    buffer.set_transform(Robotics::Transform.new("base_link", "camera", vec(0.0, 2.0, 0.0), yaw90))

    tf = buffer.lookup_transform("world", "camera").not_nil!
    tf.frame_id.should eq("world")
    tf.child_frame_id.should eq("camera")
    # camera x-axis point rotates to base_link +y, then offsets (0,2,0) and (1,0,0)
    close(tf.apply(vec(1.0, 0.0, 0.0)), vec(1.0, 3.0, 0.0))
  end

  it "walks edges against their stored direction" do
    buffer = Robotics::TransformBuffer.new
    buffer.set_transform(Robotics::Transform.new("map", "odom", vec(5.0, 0.0, 0.0)))
    buffer.set_transform(Robotics::Transform.new("map", "dock", vec(0.0, 5.0, 0.0)))

    tf = buffer.lookup_transform("odom", "dock").not_nil!
    close(tf.apply(vec(0.0, 0.0, 0.0)), vec(-5.0, 5.0, 0.0))
  end

  it "round-trips a chain with its reverse lookup" do
    buffer = Robotics::TransformBuffer.new
    q = Robotics::MessageTypes::Quaternion.from_euler(0.1, 0.2, 0.3)
    buffer.set_transform(Robotics::Transform.new("a", "b", vec(1.0, 2.0, 3.0), q))
    buffer.set_transform(Robotics::Transform.new("b", "c", vec(-1.0, 0.5, 0.0), q))

    forward = buffer.lookup_transform("a", "c").not_nil!
    backward = buffer.lookup_transform("c", "a").not_nil!
    p = vec(0.3, -0.7, 1.1)
    close(backward.apply(forward.apply(p)), p)
  end

  it "returns nil for disconnected frames and identity for same frame" do
    buffer = Robotics::TransformBuffer.new
    buffer.set_transform(Robotics::Transform.new("world", "base_link"))
    buffer.set_transform(Robotics::Transform.new("island", "rock"))

    buffer.lookup_transform("world", "rock").should be_nil
    buffer.can_transform("base_link", "island").should be_false
    close(buffer.lookup_transform("world", "world").not_nil!.apply(vec(1.0, 2.0, 3.0)), vec(1.0, 2.0, 3.0))
  end
end
