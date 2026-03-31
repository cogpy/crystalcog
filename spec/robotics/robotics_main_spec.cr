require "spec"
require "../../src/robotics/robotics_main"

describe "Robotics Main" do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    Robotics.initialize
  end

  describe "initialization" do
    it "initializes the Robotics subsystem without errors" do
      Robotics.initialize
    end

    it "has correct version" do
      Robotics::VERSION.should eq("0.1.0")
    end
  end

  describe "module accessibility" do
    it "exposes SpatialReasoning module" do
      Robotics::SpatialReasoning::VERSION.should eq("0.1.0")
    end

    it "exposes Navigation module" do
      Robotics::Navigation::VERSION.should eq("0.1.0")
    end

    it "exposes SensoryMotor module" do
      Robotics::SensoryMotor::VERSION.should eq("0.1.0")
    end

    it "exposes GoalPlanning module" do
      Robotics::GoalPlanning::VERSION.should eq("0.1.0")
    end
  end
end
