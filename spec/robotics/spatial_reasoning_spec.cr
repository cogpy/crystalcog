require "spec"
require "../../src/robotics/spatial_reasoning"

describe Robotics::SpatialReasoning do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe "Position" do
    it "creates a 3D position" do
      pos = Robotics::SpatialReasoning::Position.new(1.0, 2.0, 3.0)
      pos.x.should eq(1.0)
      pos.y.should eq(2.0)
      pos.z.should eq(3.0)
    end

    it "creates a 2D position (z defaults to 0)" do
      pos = Robotics::SpatialReasoning::Position.new(1.0, 2.0)
      pos.z.should eq(0.0)
    end

    it "computes distance between positions" do
      p1 = Robotics::SpatialReasoning::Position.new(0.0, 0.0, 0.0)
      p2 = Robotics::SpatialReasoning::Position.new(3.0, 4.0, 0.0)
      p1.distance_to(p2).should be_close(5.0, 0.0001)
    end

    it "adds two positions" do
      p1 = Robotics::SpatialReasoning::Position.new(1.0, 2.0)
      p2 = Robotics::SpatialReasoning::Position.new(3.0, 4.0)
      result = p1 + p2
      result.x.should eq(4.0)
      result.y.should eq(6.0)
    end

    it "subtracts two positions" do
      p1 = Robotics::SpatialReasoning::Position.new(5.0, 3.0)
      p2 = Robotics::SpatialReasoning::Position.new(2.0, 1.0)
      result = p1 - p2
      result.x.should eq(3.0)
      result.y.should eq(2.0)
    end

    it "scales a position" do
      pos = Robotics::SpatialReasoning::Position.new(2.0, 3.0)
      scaled = pos * 2.0
      scaled.x.should eq(4.0)
      scaled.y.should eq(6.0)
    end

    it "normalizes a position vector" do
      pos = Robotics::SpatialReasoning::Position.new(3.0, 4.0)
      norm = pos.normalize
      norm.magnitude.should be_close(1.0, 0.0001)
    end

    it "computes magnitude" do
      pos = Robotics::SpatialReasoning::Position.new(3.0, 4.0)
      pos.magnitude.should be_close(5.0, 0.0001)
    end
  end

  describe "Orientation" do
    it "creates default orientation (all zeros)" do
      orient = Robotics::SpatialReasoning::Orientation.new
      orient.roll.should eq(0.0)
      orient.pitch.should eq(0.0)
      orient.yaw.should eq(0.0)
    end

    it "creates orientation with custom angles" do
      orient = Robotics::SpatialReasoning::Orientation.new(0.1, 0.2, 0.3)
      orient.roll.should eq(0.1)
      orient.pitch.should eq(0.2)
      orient.yaw.should eq(0.3)
    end
  end

  describe "BoundingBox" do
    it "detects containment" do
      min = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      max = Robotics::SpatialReasoning::Position.new(2.0, 2.0)
      bb = Robotics::SpatialReasoning::BoundingBox.new(min, max)
      inside = Robotics::SpatialReasoning::Position.new(1.0, 1.0)
      outside = Robotics::SpatialReasoning::Position.new(3.0, 3.0)
      bb.contains?(inside).should be_true
      bb.contains?(outside).should be_false
    end

    it "computes center" do
      min = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      max = Robotics::SpatialReasoning::Position.new(4.0, 6.0)
      bb = Robotics::SpatialReasoning::BoundingBox.new(min, max)
      center = bb.center
      center.x.should eq(2.0)
      center.y.should eq(3.0)
    end

    it "detects intersection between bounding boxes" do
      min1 = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      max1 = Robotics::SpatialReasoning::Position.new(2.0, 2.0)
      min2 = Robotics::SpatialReasoning::Position.new(1.0, 1.0)
      max2 = Robotics::SpatialReasoning::Position.new(3.0, 3.0)
      bb1 = Robotics::SpatialReasoning::BoundingBox.new(min1, max1)
      bb2 = Robotics::SpatialReasoning::BoundingBox.new(min2, max2)
      bb1.intersects?(bb2).should be_true
    end
  end

  describe "SpatialMap" do
    it "adds and retrieves entities" do
      map = Robotics::SpatialReasoning::SpatialMap.new
      pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(1.0, 2.0))
      entity = Robotics::SpatialReasoning::SpatialEntity.new("e1", "robot", pose)
      map.add_entity(entity)
      retrieved = map.get_entity("e1")
      retrieved.should_not be_nil
      retrieved.not_nil!.name.should eq("robot")
    end

    it "removes entities" do
      map = Robotics::SpatialReasoning::SpatialMap.new
      pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(0.0, 0.0))
      entity = Robotics::SpatialReasoning::SpatialEntity.new("e1", "box", pose)
      map.add_entity(entity)
      map.remove_entity("e1").should be_true
      map.get_entity("e1").should be_nil
    end

    it "finds entities within radius" do
      map = Robotics::SpatialReasoning::SpatialMap.new
      close_pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(1.0, 0.0))
      far_pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(10.0, 0.0))
      map.add_entity(Robotics::SpatialReasoning::SpatialEntity.new("close", "near_obj", close_pose))
      map.add_entity(Robotics::SpatialReasoning::SpatialEntity.new("far", "far_obj", far_pose))
      center = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      nearby = map.entities_within_radius(center, 3.0)
      nearby.size.should eq(1)
      nearby.first.name.should eq("near_obj")
    end

    it "finds nearest entity" do
      map = Robotics::SpatialReasoning::SpatialMap.new
      p1 = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(1.0, 0.0))
      p2 = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(5.0, 0.0))
      map.add_entity(Robotics::SpatialReasoning::SpatialEntity.new("near", "A", p1))
      map.add_entity(Robotics::SpatialReasoning::SpatialEntity.new("far", "B", p2))
      origin = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      nearest = map.nearest_entity(origin)
      nearest.should_not be_nil
      nearest.not_nil!.name.should eq("A")
    end

    it "computes spatial relations between entities" do
      map = Robotics::SpatialReasoning::SpatialMap.new
      p1 = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(0.0, 0.0))
      p2 = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(5.0, 0.0))
      map.add_entity(Robotics::SpatialReasoning::SpatialEntity.new("e1", "obj1", p1))
      map.add_entity(Robotics::SpatialReasoning::SpatialEntity.new("e2", "obj2", p2))
      rel = map.relation_between("e1", "e2")
      rel.should_not be_nil
    end

    it "stores knowledge in atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      map = Robotics::SpatialReasoning::SpatialMap.new
      pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(1.0, 2.0))
      map.add_entity(Robotics::SpatialReasoning::SpatialEntity.new("e1", "table", pose))
      map.to_atomspace(atomspace)
      atomspace.size.should be > 0
    end
  end
end
