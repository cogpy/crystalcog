# Goal-Oriented Behavior Planning for CrystalCog
#
# This module provides goal-oriented behavior planning capabilities including:
# - Goal representation and management
# - Action planning using STRIPS-style operators
# - Hierarchical Task Networks (HTN)
# - Behavior trees for reactive planning
#
# References:
# - STRIPS: Fikes & Nilsson, 1971
# - HTN Planning: Erol, Hendler, Nau, 1994
# - Behavior Trees: Colledanchise & Ögren, 2017

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../spatial/spatial"

module Behavior
  VERSION = "0.1.0"

  # Exception classes
  class BehaviorException < Exception
  end

  class GoalUnreachableException < BehaviorException
  end

  class ActionFailedException < BehaviorException
  end

  # Represents a state predicate
  struct Predicate
    getter name : String
    getter arguments : Array(String)
    getter negated : Bool

    def initialize(@name : String, @arguments : Array(String) = [] of String, @negated : Bool = false)
    end

    def negate : Predicate
      Predicate.new(@name, @arguments, !@negated)
    end

    def matches?(other : Predicate) : Bool
      @name == other.name &&
        @arguments == other.arguments &&
        @negated == other.negated
    end

    def conflicts?(other : Predicate) : Bool
      @name == other.name &&
        @arguments == other.arguments &&
        @negated != other.negated
    end

    def to_s(io : IO)
      io << "#{@negated ? "NOT " : ""}#{@name}(#{@arguments.join(", ")})"
    end
  end

  # Represents a world state as a set of predicates
  class State
    getter predicates : Set(Predicate)
    getter variables : Hash(String, String | Float64 | Bool)

    def initialize
      @predicates = Set(Predicate).new
      @variables = {} of String => String | Float64 | Bool
    end

    def add(predicate : Predicate)
      # Remove conflicting predicates first
      # Crystal's Set has no in-place `reject!`; collect first so deletion does
      # not mutate the collection while it is being traversed.
      @predicates.select { |existing| existing.conflicts?(predicate) }.each do |conflict|
        @predicates.delete(conflict)
      end
      @predicates.add(predicate)
    end

    def remove(predicate : Predicate)
      @predicates.delete(predicate)
    end

    def holds?(predicate : Predicate) : Bool
      @predicates.includes?(predicate)
    end

    def satisfies?(predicates : Array(Predicate)) : Bool
      predicates.all? { |p| holds?(p) }
    end

    def clone : State
      new_state = State.new
      @predicates.each { |p| new_state.add(p) }
      @variables.each { |k, v| new_state.variables[k] = v }
      new_state
    end

    # Convert to AtomSpace representation
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      @predicates.each do |pred|
        pred_node = atomspace.add_node(
          AtomSpace::AtomType::PREDICATE_NODE,
          pred.name
        )

        arg_nodes = pred.arguments.map do |arg|
          atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, arg)
        end

        if pred.negated
          # Wrap in NotLink
          inner_link = atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [pred_node, atomspace.add_link(
              AtomSpace::AtomType::LIST_LINK,
              arg_nodes
            )]
          )
          atoms << atomspace.add_link(
            AtomSpace::AtomType::NOT_LINK,
            [inner_link]
          )
        else
          atoms << atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [pred_node, atomspace.add_link(
              AtomSpace::AtomType::LIST_LINK,
              arg_nodes
            )]
          )
        end
      end

      atoms
    end
  end

  # Represents an action with preconditions and effects
  class Action
    getter name : String
    getter parameters : Array(String)
    getter preconditions : Array(Predicate)
    getter add_effects : Array(Predicate)
    getter delete_effects : Array(Predicate)
    getter cost : Float64
    getter duration : Float64

    def initialize(@name : String,
                   @parameters : Array(String) = [] of String,
                   @preconditions : Array(Predicate) = [] of Predicate,
                   @add_effects : Array(Predicate) = [] of Predicate,
                   @delete_effects : Array(Predicate) = [] of Predicate,
                   @cost : Float64 = 1.0,
                   @duration : Float64 = 1.0)
    end

    # Check if action is applicable in given state
    def applicable?(state : State) : Bool
      state.satisfies?(@preconditions)
    end

    # Apply action to state, returning new state
    def apply(state : State) : State
      new_state = state.clone

      # Remove delete effects
      @delete_effects.each { |e| new_state.remove(e) }

      # Add add effects
      @add_effects.each { |e| new_state.add(e) }

      new_state
    end

    def to_s(io : IO)
      io << "Action(#{@name}(#{@parameters.join(", ")}))"
    end

    # Ground action with specific bindings
    def ground(bindings : Hash(String, String)) : Action
      ground_predicates = ->(preds : Array(Predicate)) {
        preds.map do |p|
          args = p.arguments.map { |a| bindings[a]? || a }
          Predicate.new(p.name, args, p.negated)
        end
      }

      Action.new(
        @name,
        @parameters.map { |p| bindings[p]? || p },
        ground_predicates.call(@preconditions),
        ground_predicates.call(@add_effects),
        ground_predicates.call(@delete_effects),
        @cost,
        @duration
      )
    end
  end

  # Represents a goal
  class Goal
    getter name : String
    getter conditions : Array(Predicate)
    getter priority : Float64
    getter deadline : Float64?

    def initialize(@name : String,
                   @conditions : Array(Predicate) = [] of Predicate,
                   @priority : Float64 = 1.0,
                   @deadline : Float64? = nil)
    end

    def satisfied?(state : State) : Bool
      state.satisfies?(@conditions)
    end
  end

  # Plan as sequence of actions
  class Plan
    getter actions : Array(Action)
    getter total_cost : Float64

    def initialize(@actions : Array(Action) = [] of Action)
      @total_cost = @actions.sum(&.cost)
    end

    def add_action(action : Action)
      @actions << action
      @total_cost += action.cost
    end

    def valid?(initial_state : State) : Bool
      state = initial_state.clone

      @actions.all? do |action|
        if action.applicable?(state)
          state = action.apply(state)
          true
        else
          false
        end
      end
    end

    def execute(initial_state : State) : State
      @actions.reduce(initial_state) do |state, action|
        if action.applicable?(state)
          action.apply(state)
        else
          raise ActionFailedException.new("Action #{action.name} not applicable")
        end
      end
    end

    def to_s(io : IO)
      io << "Plan[\n"
      @actions.each_with_index do |action, i|
        io << "  #{i + 1}. #{action}\n"
      end
      io << "] (cost: #{@total_cost})"
    end
  end

  # STRIPS-style forward planner
  class ForwardPlanner
    getter actions : Array(Action)
    getter max_depth : Int32

    def initialize(@max_depth : Int32 = 100)
      @actions = [] of Action
      CogUtil::Logger.info("ForwardPlanner initialized with max depth #{@max_depth}")
    end

    def add_action(action : Action)
      @actions << action
    end

    # Find plan using breadth-first search
    def plan(initial_state : State, goal : Goal) : Plan?
      return Plan.new if goal.satisfied?(initial_state)

      CogUtil::Logger.debug("Planning for goal: #{goal.name}")

      queue = [{initial_state, Plan.new}]
      visited = Set(String).new
      visited.add(state_hash(initial_state))

      while !queue.empty?
        state, current_plan = queue.shift

        return nil if current_plan.actions.size >= @max_depth

        @actions.each do |action|
          if action.applicable?(state)
            new_state = action.apply(state)
            state_key = state_hash(new_state)

            unless visited.includes?(state_key)
              visited.add(state_key)

              new_plan = Plan.new(current_plan.actions.dup)
              new_plan.add_action(action)

              if goal.satisfied?(new_state)
                CogUtil::Logger.info("Plan found with #{new_plan.actions.size} actions")
                return new_plan
              end

              queue << {new_state, new_plan}
            end
          end
        end
      end

      CogUtil::Logger.warn("No plan found for goal: #{goal.name}")
      nil
    end

    private def state_hash(state : State) : String
      state.predicates.map(&.to_s).sort.join(";")
    end
  end

  # Behavior tree node status
  enum NodeStatus
    SUCCESS
    FAILURE
    RUNNING
  end

  # Base class for behavior tree nodes
  abstract class BTNode
    getter name : String

    def initialize(@name : String)
    end

    abstract def tick(blackboard : Hash(String, String | Float64 | Bool)) : NodeStatus
    abstract def reset
  end

  # Action node - executes a callback
  class ActionNode < BTNode
    @action : Proc(Hash(String, String | Float64 | Bool), NodeStatus)

    def initialize(name : String, &@action : Proc(Hash(String, String | Float64 | Bool), NodeStatus))
      super(name)
    end

    def tick(blackboard : Hash(String, String | Float64 | Bool)) : NodeStatus
      @action.call(blackboard)
    end

    def reset
    end
  end

  # Condition node - checks a condition
  class ConditionNode < BTNode
    @condition : Proc(Hash(String, String | Float64 | Bool), Bool)

    def initialize(name : String, &@condition : Proc(Hash(String, String | Float64 | Bool), Bool))
      super(name)
    end

    def tick(blackboard : Hash(String, String | Float64 | Bool)) : NodeStatus
      @condition.call(blackboard) ? NodeStatus::SUCCESS : NodeStatus::FAILURE
    end

    def reset
    end
  end

  # Sequence node - executes children in order until one fails
  class SequenceNode < BTNode
    getter children : Array(BTNode)
    @current_index : Int32

    def initialize(name : String)
      @children = [] of BTNode
      super(name)
      @current_index = 0
    end

    # Arrays are invariant in Crystal, so normalize an array of any BTNode
    # subclass (such as Array(ActionNode)) to the node collection we store.
    def initialize(name : String, children : Array(T)) forall T
      @children = children.map(&.as(BTNode))
      super(name)
      @current_index = 0
    end

    def add_child(child : BTNode)
      @children << child
    end

    def tick(blackboard : Hash(String, String | Float64 | Bool)) : NodeStatus
      while @current_index < @children.size
        status = @children[@current_index].tick(blackboard)

        case status
        when NodeStatus::RUNNING
          return NodeStatus::RUNNING
        when NodeStatus::FAILURE
          reset
          return NodeStatus::FAILURE
        when NodeStatus::SUCCESS
          @current_index += 1
        end
      end

      reset
      NodeStatus::SUCCESS
    end

    def reset
      @current_index = 0
      @children.each(&.reset)
    end
  end

  # Selector node - executes children until one succeeds
  class SelectorNode < BTNode
    getter children : Array(BTNode)
    @current_index : Int32

    def initialize(name : String)
      @children = [] of BTNode
      super(name)
      @current_index = 0
    end

    # Arrays are invariant in Crystal, so normalize an array of any BTNode
    # subclass (such as Array(ActionNode)) to the node collection we store.
    def initialize(name : String, children : Array(T)) forall T
      @children = children.map(&.as(BTNode))
      super(name)
      @current_index = 0
    end

    def add_child(child : BTNode)
      @children << child
    end

    def tick(blackboard : Hash(String, String | Float64 | Bool)) : NodeStatus
      while @current_index < @children.size
        status = @children[@current_index].tick(blackboard)

        case status
        when NodeStatus::RUNNING
          return NodeStatus::RUNNING
        when NodeStatus::SUCCESS
          reset
          return NodeStatus::SUCCESS
        when NodeStatus::FAILURE
          @current_index += 1
        end
      end

      reset
      NodeStatus::FAILURE
    end

    def reset
      @current_index = 0
      @children.each(&.reset)
    end
  end

  # Decorator that inverts child result
  class InverterNode < BTNode
    getter child : BTNode

    def initialize(name : String, @child : BTNode)
      super(name)
    end

    def tick(blackboard : Hash(String, String | Float64 | Bool)) : NodeStatus
      status = @child.tick(blackboard)

      case status
      when NodeStatus::SUCCESS then NodeStatus::FAILURE
      when NodeStatus::FAILURE then NodeStatus::SUCCESS
      else                          status
      end
    end

    def reset
      @child.reset
    end
  end

  # Repeat decorator
  class RepeatNode < BTNode
    getter child : BTNode
    getter max_repeats : Int32
    @current_repeats : Int32

    def initialize(name : String, @child : BTNode, @max_repeats : Int32 = -1)
      super(name)
      @current_repeats = 0
    end

    def tick(blackboard : Hash(String, String | Float64 | Bool)) : NodeStatus
      loop do
        status = @child.tick(blackboard)

        case status
        when NodeStatus::RUNNING
          return NodeStatus::RUNNING
        when NodeStatus::SUCCESS
          @current_repeats += 1
          @child.reset

          if @max_repeats > 0 && @current_repeats >= @max_repeats
            reset
            return NodeStatus::SUCCESS
          end
        when NodeStatus::FAILURE
          reset
          return NodeStatus::FAILURE
        end

        # Prevent infinite loop if max_repeats is -1 (infinite)
        break if @max_repeats < 0 && @current_repeats > 1000
      end

      NodeStatus::RUNNING
    end

    def reset
      @current_repeats = 0
      @child.reset
    end
  end

  # Behavior tree executor
  class BehaviorTree
    getter root : BTNode
    getter blackboard : Hash(String, String | Float64 | Bool)

    def initialize(@root : BTNode)
      @blackboard = {} of String => String | Float64 | Bool
      CogUtil::Logger.info("BehaviorTree created with root: #{@root.name}")
    end

    def tick : NodeStatus
      @root.tick(@blackboard)
    end

    def reset
      @root.reset
    end

    def set(key : String, value : String | Float64 | Bool)
      @blackboard[key] = value
    end

    def get(key : String) : (String | Float64 | Bool)?
      @blackboard[key]?
    end
  end

  # Goal manager for managing multiple goals
  class GoalManager
    getter goals : Array(Goal)
    getter active_goal : Goal?
    getter planner : ForwardPlanner

    def initialize(@planner : ForwardPlanner = ForwardPlanner.new)
      @goals = [] of Goal
      @active_goal = nil
    end

    def add_goal(goal : Goal)
      @goals << goal
      @goals.sort_by! { |g| -g.priority } # Highest priority first
    end

    def remove_goal(name : String)
      @goals.reject! { |g| g.name == name }
    end

    # Select highest priority unsatisfied goal
    def select_goal(current_state : State) : Goal?
      @goals.find { |g| !g.satisfied?(current_state) }
    end

    # Plan for the highest priority goal
    def plan_for_current_goal(current_state : State) : Plan?
      @active_goal = select_goal(current_state)

      if goal = @active_goal
        CogUtil::Logger.info("Planning for goal: #{goal.name}")
        @planner.plan(current_state, goal)
      else
        CogUtil::Logger.info("All goals satisfied")
        nil
      end
    end
  end

  # Module-level convenience methods
  def self.create_state : State
    State.new
  end

  def self.create_goal(name : String, conditions : Array(Predicate), priority : Float64 = 1.0) : Goal
    Goal.new(name, conditions, priority)
  end

  def self.create_planner(max_depth : Int32 = 100) : ForwardPlanner
    ForwardPlanner.new(max_depth)
  end

  def self.create_behavior_tree(root : BTNode) : BehaviorTree
    BehaviorTree.new(root)
  end
end
