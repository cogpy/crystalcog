require "../spec_helper"
require "../../src/behavior/behavior"

describe Behavior do
  describe "Predicate" do
    it "creates a predicate" do
      pred = Behavior::Predicate.new("on", ["block_a", "table"])
      pred.name.should eq("on")
      pred.arguments.should eq(["block_a", "table"])
      pred.negated.should be_false
    end

    it "negates a predicate" do
      pred = Behavior::Predicate.new("on", ["block_a", "table"])
      neg = pred.negate
      neg.negated.should be_true
    end

    it "matches identical predicates" do
      pred1 = Behavior::Predicate.new("on", ["a", "b"])
      pred2 = Behavior::Predicate.new("on", ["a", "b"])
      pred1.matches?(pred2).should be_true
    end

    it "detects conflicting predicates" do
      pred1 = Behavior::Predicate.new("on", ["a", "b"])
      pred2 = Behavior::Predicate.new("on", ["a", "b"], negated: true)
      pred1.conflicts?(pred2).should be_true
    end
  end

  describe "State" do
    it "adds and removes predicates" do
      state = Behavior::State.new
      pred = Behavior::Predicate.new("on", ["a", "b"])

      state.add(pred)
      state.holds?(pred).should be_true

      state.remove(pred)
      state.holds?(pred).should be_false
    end

    it "removes conflicting predicates when adding" do
      state = Behavior::State.new
      pred_pos = Behavior::Predicate.new("on", ["a", "b"])
      pred_neg = Behavior::Predicate.new("on", ["a", "b"], negated: true)

      state.add(pred_pos)
      state.holds?(pred_pos).should be_true

      state.add(pred_neg)
      state.holds?(pred_neg).should be_true
      state.holds?(pred_pos).should be_false
    end

    it "satisfies multiple predicates" do
      state = Behavior::State.new
      state.add(Behavior::Predicate.new("on", ["a", "b"]))
      state.add(Behavior::Predicate.new("clear", ["a"]))

      conditions = [
        Behavior::Predicate.new("on", ["a", "b"]),
        Behavior::Predicate.new("clear", ["a"]),
      ]

      state.satisfies?(conditions).should be_true
    end
  end

  describe "Action" do
    it "checks applicability" do
      precond = [Behavior::Predicate.new("clear", ["block"])]
      action = Behavior::Action.new("pickup", ["block"], precond)

      state_valid = Behavior::State.new
      state_valid.add(Behavior::Predicate.new("clear", ["block"]))

      state_invalid = Behavior::State.new

      action.applicable?(state_valid).should be_true
      action.applicable?(state_invalid).should be_false
    end

    it "applies effects to state" do
      precond = [Behavior::Predicate.new("on_table", ["block"])]
      add_eff = [Behavior::Predicate.new("holding", ["block"])]
      del_eff = [Behavior::Predicate.new("on_table", ["block"])]

      action = Behavior::Action.new(
        "pickup",
        ["block"],
        precond,
        add_eff,
        del_eff
      )

      initial = Behavior::State.new
      initial.add(Behavior::Predicate.new("on_table", ["block"]))

      result = action.apply(initial)

      result.holds?(Behavior::Predicate.new("holding", ["block"])).should be_true
      result.holds?(Behavior::Predicate.new("on_table", ["block"])).should be_false
    end
  end

  describe "Goal" do
    it "checks satisfaction" do
      conditions = [Behavior::Predicate.new("on", ["a", "b"])]
      goal = Behavior::Goal.new("stack_blocks", conditions)

      state_satisfied = Behavior::State.new
      state_satisfied.add(Behavior::Predicate.new("on", ["a", "b"]))

      state_unsatisfied = Behavior::State.new

      goal.satisfied?(state_satisfied).should be_true
      goal.satisfied?(state_unsatisfied).should be_false
    end
  end

  describe "ForwardPlanner" do
    it "finds a simple plan" do
      planner = Behavior::ForwardPlanner.new

      # Define action: pickup block from table
      pickup = Behavior::Action.new(
        "pickup",
        ["block"],
        [Behavior::Predicate.new("on_table", ["block"]), Behavior::Predicate.new("clear", ["block"])],
        [Behavior::Predicate.new("holding", ["block"])],
        [Behavior::Predicate.new("on_table", ["block"])]
      )
      planner.add_action(pickup)

      # Initial state
      initial = Behavior::State.new
      initial.add(Behavior::Predicate.new("on_table", ["block"]))
      initial.add(Behavior::Predicate.new("clear", ["block"]))

      # Goal
      goal = Behavior::Goal.new(
        "hold_block",
        [Behavior::Predicate.new("holding", ["block"])]
      )

      plan = planner.plan(initial, goal)
      plan.should_not be_nil
      plan.not_nil!.actions.size.should eq(1)
    end

    it "returns nil for impossible goal" do
      planner = Behavior::ForwardPlanner.new(max_depth: 5)

      # No actions defined
      initial = Behavior::State.new
      goal = Behavior::Goal.new(
        "impossible",
        [Behavior::Predicate.new("flying", ["pig"])]
      )

      plan = planner.plan(initial, goal)
      plan.should be_nil
    end
  end

  describe "BehaviorTree" do
    it "executes action node" do
      action = Behavior::ActionNode.new("test_action") do |blackboard|
        blackboard["executed"] = true
        Behavior::NodeStatus::SUCCESS
      end

      bt = Behavior::BehaviorTree.new(action)
      status = bt.tick

      status.should eq(Behavior::NodeStatus::SUCCESS)
      bt.get("executed").should eq(true)
    end

    it "executes sequence node" do
      counter = 0

      child1 = Behavior::ActionNode.new("action1") do |_|
        counter += 1
        Behavior::NodeStatus::SUCCESS
      end

      child2 = Behavior::ActionNode.new("action2") do |_|
        counter += 1
        Behavior::NodeStatus::SUCCESS
      end

      sequence = Behavior::SequenceNode.new("sequence", [child1, child2])
      bt = Behavior::BehaviorTree.new(sequence)

      status = bt.tick
      status.should eq(Behavior::NodeStatus::SUCCESS)
      counter.should eq(2)
    end

    it "executes selector node" do
      child1 = Behavior::ActionNode.new("fail") do |_|
        Behavior::NodeStatus::FAILURE
      end

      child2 = Behavior::ActionNode.new("succeed") do |blackboard|
        blackboard["chosen"] = "second"
        Behavior::NodeStatus::SUCCESS
      end

      selector = Behavior::SelectorNode.new("selector", [child1, child2])
      bt = Behavior::BehaviorTree.new(selector)

      status = bt.tick
      status.should eq(Behavior::NodeStatus::SUCCESS)
      bt.get("chosen").should eq("second")
    end

    it "inverts child result" do
      child = Behavior::ActionNode.new("succeed") do |_|
        Behavior::NodeStatus::SUCCESS
      end

      inverter = Behavior::InverterNode.new("inverter", child)
      bt = Behavior::BehaviorTree.new(inverter)

      status = bt.tick
      status.should eq(Behavior::NodeStatus::FAILURE)
    end
  end

  describe "GoalManager" do
    it "selects highest priority goal" do
      manager = Behavior::GoalManager.new

      low_priority = Behavior::Goal.new(
        "low",
        [Behavior::Predicate.new("done", ["low"])],
        priority: 1.0
      )

      high_priority = Behavior::Goal.new(
        "high",
        [Behavior::Predicate.new("done", ["high"])],
        priority: 10.0
      )

      manager.add_goal(low_priority)
      manager.add_goal(high_priority)

      state = Behavior::State.new
      selected = manager.select_goal(state)

      selected.should_not be_nil
      selected.not_nil!.name.should eq("high")
    end
  end
end
