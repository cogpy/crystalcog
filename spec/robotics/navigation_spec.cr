require "spec"
require "../../src/robotics/navigation"

describe Robotics::Navigation do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe "Waypoint" do
    it "creates a waypoint with a position" do
      pos = Robotics::SpatialReasoning::Position.new(1.0, 2.0)
      wp = Robotics::Navigation::Waypoint.new(pos, "checkpoint")
      wp.position.x.should eq(1.0)
      wp.label.should eq("checkpoint")
    end
  end

  describe "Path" do
    it "starts empty" do
      path = Robotics::Navigation::Path.new
      path.empty?.should be_true
      path.length.should eq(0)
      path.total_distance.should eq(0.0)
    end

    it "computes total distance" do
      wp1 = Robotics::Navigation::Waypoint.new(Robotics::SpatialReasoning::Position.new(0.0, 0.0))
      wp2 = Robotics::Navigation::Waypoint.new(Robotics::SpatialReasoning::Position.new(3.0, 4.0))
      path = Robotics::Navigation::Path.new([wp1, wp2])
      path.total_distance.should be_close(5.0, 0.0001)
    end

    it "adds waypoints" do
      path = Robotics::Navigation::Path.new
      wp = Robotics::Navigation::Waypoint.new(Robotics::SpatialReasoning::Position.new(1.0, 1.0))
      path.add_waypoint(wp)
      path.length.should eq(1)
    end
  end

  describe "OccupancyGrid" do
    it "creates a grid of given dimensions" do
      grid = Robotics::Navigation::OccupancyGrid.new(10, 10)
      grid.width.should eq(10)
      grid.height.should eq(10)
    end

    it "starts with no obstacles" do
      grid = Robotics::Navigation::OccupancyGrid.new(5, 5)
      grid.obstacle?(2, 2).should be_false
    end

    it "sets and clears obstacles" do
      grid = Robotics::Navigation::OccupancyGrid.new(5, 5)
      grid.set_obstacle(2, 3)
      grid.obstacle?(2, 3).should be_true
      grid.clear_obstacle(2, 3)
      grid.obstacle?(2, 3).should be_false
    end

    it "treats out-of-bounds as obstacles" do
      grid = Robotics::Navigation::OccupancyGrid.new(5, 5)
      grid.obstacle?(-1, 0).should be_true
      grid.obstacle?(10, 0).should be_true
    end

    it "converts between world and grid coordinates" do
      grid = Robotics::Navigation::OccupancyGrid.new(100, 100, 0.1)
      pos = Robotics::SpatialReasoning::Position.new(1.0, 2.0)
      gx, gy = grid.world_to_grid(pos)
      gx.should eq(10)
      gy.should eq(20)
    end
  end

  describe "AStarPlanner" do
    it "finds a path on an empty grid" do
      grid = Robotics::Navigation::OccupancyGrid.new(20, 20, 1.0)
      planner = Robotics::Navigation::AStarPlanner.new(grid)
      start = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      goal = Robotics::SpatialReasoning::Position.new(5.0, 5.0)
      path = planner.plan(start, goal)
      path.should_not be_nil
      path.not_nil!.empty?.should be_false
    end

    it "returns nil when start is blocked" do
      grid = Robotics::Navigation::OccupancyGrid.new(10, 10, 1.0)
      grid.set_obstacle(0, 0)
      planner = Robotics::Navigation::AStarPlanner.new(grid)
      start = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      goal = Robotics::SpatialReasoning::Position.new(5.0, 5.0)
      path = planner.plan(start, goal)
      path.should be_nil
    end

    it "navigates around an obstacle" do
      grid = Robotics::Navigation::OccupancyGrid.new(10, 10, 1.0)
      # Place a wall
      (0..8).each { |y| grid.set_obstacle(3, y) }
      planner = Robotics::Navigation::AStarPlanner.new(grid)
      start = Robotics::SpatialReasoning::Position.new(0.0, 0.0)
      goal = Robotics::SpatialReasoning::Position.new(6.0, 0.0)
      path = planner.plan(start, goal)
      # May or may not find path depending on grid topology but should not crash
      # (the wall doesn't block row y=9)
      path.should_not be_nil
    end
  end

  describe "Navigator" do
    it "initializes at given pose" do
      pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(0.0, 0.0))
      nav = Robotics::Navigation::Navigator.new(pose)
      nav.current_pose.position.x.should eq(0.0)
    end

    it "plans navigation and steps towards goal" do
      pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(0.0, 0.0))
      nav = Robotics::Navigation::Navigator.new(pose)
      grid = Robotics::Navigation::OccupancyGrid.new(20, 20, 1.0)
      goal = Robotics::SpatialReasoning::Position.new(3.0, 0.0)
      success = nav.navigate_to(goal, grid)
      success.should be_true
      nav.current_path.should_not be_nil
    end

    it "reports reached_goal? when no path is set" do
      pose = Robotics::SpatialReasoning::Pose.new(Robotics::SpatialReasoning::Position.new(0.0, 0.0))
      nav = Robotics::Navigation::Navigator.new(pose)
      nav.reached_goal?.should be_true
    end
  end
end
