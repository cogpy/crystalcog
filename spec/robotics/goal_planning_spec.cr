require "spec"
require "../../src/robotics/goal_planning"

describe Robotics::GoalPlanning do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe "Action" do
    it "creates an action with preconditions and effects" do
      action = Robotics::GoalPlanning::Action.new(
        "move",
        ["at_A"],
        ["at_B"],
        ["at_A"]
      )
      action.name.should eq("move")
      action.preconditions.should contain("at_A")
      action.add_effects.should contain("at_B")
      action.delete_effects.should contain("at_A")
    end

    it "checks applicability" do
      action = Robotics::GoalPlanning::Action.new("pick", ["holding_nothing", "near_object"], ["holding_object"])
      state_ok = Set{"holding_nothing", "near_object"}
      state_bad = Set{"holding_nothing"}
      action.applicable?(state_ok).should be_true
      action.applicable?(state_bad).should be_false
    end

    it "applies action to state" do
      action = Robotics::GoalPlanning::Action.new("pick", ["near_object"], ["holding_object"], ["near_object"])
      state = Set{"near_object", "room_empty"}
      new_state = action.apply(state)
      new_state.should contain("holding_object")
      new_state.should_not contain("near_object")
      new_state.should contain("room_empty")
    end
  end

  describe "Goal" do
    it "creates a goal with conditions" do
      goal = Robotics::GoalPlanning::Goal.new("deliver", ["holding_package", "at_destination"])
      goal.name.should eq("deliver")
      goal.conditions.size.should eq(2)
    end

    it "checks satisfaction" do
      goal = Robotics::GoalPlanning::Goal.new("reach_B", ["at_B"])
      satisfied_state = Set{"at_B", "door_open"}
      unsatisfied_state = Set{"at_A"}
      goal.satisfied?(satisfied_state).should be_true
      goal.satisfied?(unsatisfied_state).should be_false
    end
  end

  describe "ForwardPlanner" do
    it "returns empty plan when goal is already satisfied" do
      actions = [] of Robotics::GoalPlanning::Action
      planner = Robotics::GoalPlanning::ForwardPlanner.new(actions)
      state = Set{"at_B"}
      goal = Robotics::GoalPlanning::Goal.new("reach_B", ["at_B"])
      plan = planner.plan(state, goal)
      plan.should_not be_nil
      plan.not_nil!.empty?.should be_true
    end

    it "finds a one-step plan" do
      move = Robotics::GoalPlanning::Action.new("move_to_B", ["at_A"], ["at_B"], ["at_A"])
      planner = Robotics::GoalPlanning::ForwardPlanner.new([move])
      state = Set{"at_A"}
      goal = Robotics::GoalPlanning::Goal.new("reach_B", ["at_B"])
      plan = planner.plan(state, goal)
      plan.should_not be_nil
      plan.not_nil!.length.should eq(1)
      plan.not_nil!.actions.first.name.should eq("move_to_B")
    end

    it "finds a multi-step plan" do
      a_to_b = Robotics::GoalPlanning::Action.new("move_A_to_B", ["at_A"], ["at_B"], ["at_A"])
      b_to_c = Robotics::GoalPlanning::Action.new("move_B_to_C", ["at_B"], ["at_C"], ["at_B"])
      planner = Robotics::GoalPlanning::ForwardPlanner.new([a_to_b, b_to_c])
      state = Set{"at_A"}
      goal = Robotics::GoalPlanning::Goal.new("reach_C", ["at_C"])
      plan = planner.plan(state, goal)
      plan.should_not be_nil
      plan.not_nil!.length.should eq(2)
    end

    it "returns nil when no plan exists" do
      # No actions available
      planner = Robotics::GoalPlanning::ForwardPlanner.new([] of Robotics::GoalPlanning::Action)
      state = Set{"at_A"}
      goal = Robotics::GoalPlanning::Goal.new("reach_B", ["at_B"])
      plan = planner.plan(state, goal)
      plan.should be_nil
    end
  end

  describe "GoalManager" do
    it "adds and prioritizes goals" do
      manager = Robotics::GoalPlanning::GoalManager.new
      low_goal = Robotics::GoalPlanning::Goal.new("low_priority", ["done_low"], 0.5)
      high_goal = Robotics::GoalPlanning::Goal.new("high_priority", ["done_high"], 2.0)
      manager.add_goal(low_goal)
      manager.add_goal(high_goal)
      manager.goals.first.name.should eq("high_priority")
    end

    it "updates and produces a plan" do
      manager = Robotics::GoalPlanning::GoalManager.new
      goal = Robotics::GoalPlanning::Goal.new("reach_B", ["at_B"])
      manager.add_goal(goal)
      actions = [Robotics::GoalPlanning::Action.new("go", ["at_A"], ["at_B"], ["at_A"])]
      state = Set{"at_A"}
      plan = manager.update(state, actions)
      plan.should_not be_nil
    end

    it "stores goals in atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      manager = Robotics::GoalPlanning::GoalManager.new
      goal = Robotics::GoalPlanning::Goal.new("pickup", ["near_object", "hand_free"])
      manager.add_goal(goal)
      manager.to_atomspace(atomspace)
      atomspace.size.should be > 0
    end
  end
end
