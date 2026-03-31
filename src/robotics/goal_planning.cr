# Goal-Oriented Behavior Planning for CrystalCog Robotics
#
# This module implements goal representation and behavior planning,
# enabling agents to select and sequence actions to achieve goals
# using a simple STRIPS-like planning framework.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Robotics
  module GoalPlanning
    VERSION = "0.1.0"

    class PlanningException < Exception
    end

    # World state is a set of true propositions
    alias WorldState = Set(String)

    # An action has preconditions and effects (add/delete lists)
    class Action
      getter name : String
      getter preconditions : Set(String)
      getter add_effects : Set(String)
      getter delete_effects : Set(String)
      getter cost : Float64

      def initialize(
        @name : String,
        preconditions : Array(String),
        add_effects : Array(String),
        delete_effects : Array(String) = [] of String,
        @cost : Float64 = 1.0
      )
        @preconditions = preconditions.to_set
        @add_effects = add_effects.to_set
        @delete_effects = delete_effects.to_set
      end

      def applicable?(state : WorldState) : Bool
        @preconditions.subset_of?(state)
      end

      def apply(state : WorldState) : WorldState
        new_state = state.dup
        @delete_effects.each { |e| new_state.delete(e) }
        @add_effects.each { |e| new_state.add(e) }
        new_state
      end
    end

    # A goal is a set of propositions that must be true
    class Goal
      getter name : String
      getter conditions : Set(String)
      getter priority : Float64

      def initialize(@name : String, conditions : Array(String), @priority : Float64 = 1.0)
        @conditions = conditions.to_set
      end

      def satisfied?(state : WorldState) : Bool
        @conditions.subset_of?(state)
      end
    end

    # A plan is a sequence of actions
    struct Plan
      getter actions : Array(Action)
      getter total_cost : Float64

      def initialize(@actions : Array(Action) = [] of Action)
        @total_cost = @actions.sum(&.cost)
      end

      def empty? : Bool
        @actions.empty?
      end

      def length : Int32
        @actions.size
      end
    end

    # Forward-search planner (BFS) with a cost-bound
    class ForwardPlanner
      MAX_SEARCH_DEPTH = 20

      def initialize(@actions : Array(Action))
      end

      # Returns the first plan found that achieves the goal from the initial state
      def plan(initial_state : WorldState, goal : Goal) : Plan?
        return Plan.new if goal.satisfied?(initial_state)

        # BFS: queue of {state, action_sequence}
        queue = Deque({WorldState, Array(Action)}).new
        queue.push({initial_state, [] of Action})
        visited = Set(String).new
        visited.add(state_key(initial_state))

        until queue.empty?
          state, actions_so_far = queue.shift

          next if actions_so_far.size >= MAX_SEARCH_DEPTH

          @actions.each do |action|
            next unless action.applicable?(state)

            new_state = action.apply(state)
            key = state_key(new_state)
            next if visited.includes?(key)
            visited.add(key)

            new_actions = actions_so_far + [action]

            if goal.satisfied?(new_state)
              return Plan.new(new_actions)
            end

            queue.push({new_state, new_actions})
          end
        end

        nil
      end

      private def state_key(state : WorldState) : String
        state.to_a.sort.join(",")
      end
    end

    # Goal manager that tracks multiple goals and selects the highest-priority unsatisfied one
    class GoalManager
      getter goals : Array(Goal)
      getter current_goal : Goal?
      getter current_plan : Plan?

      def initialize
        @goals = [] of Goal
        @current_goal = nil
        @current_plan = nil
        @action_index = 0
        CogUtil::Logger.info("GoalManager initialized")
      end

      def add_goal(goal : Goal)
        @goals << goal
        @goals.sort_by! { |g| -g.priority }
        CogUtil::Logger.debug("Goal added: #{goal.name} (priority #{goal.priority})")
      end

      def remove_goal(name : String)
        @goals.reject! { |g| g.name == name }
      end

      # Select and plan for the highest-priority unsatisfied goal
      def update(state : WorldState, actions : Array(Action)) : Plan?
        unsatisfied = @goals.reject { |g| g.satisfied?(state) }
        return nil if unsatisfied.empty?

        goal = unsatisfied.first
        if @current_goal != goal
          @current_goal = goal
          @action_index = 0
          planner = ForwardPlanner.new(actions)
          @current_plan = planner.plan(state, goal)
          CogUtil::Logger.info("Planning for goal '#{goal.name}': #{@current_plan ? "#{@current_plan.not_nil!.length} steps" : "no plan found"}")
        end

        @current_plan
      end

      # Execute one step of the current plan, return the action taken (if any)
      def step(state : WorldState) : Action?
        plan = @current_plan
        return nil unless plan
        return nil if @action_index >= plan.length

        action = plan.actions[@action_index]
        if action.applicable?(state)
          @action_index += 1
          CogUtil::Logger.debug("Executing action: #{action.name}")
          action
        else
          # Plan is invalid; re-plan on next update
          @current_plan = nil
          nil
        end
      end

      # Store goal state in AtomSpace
      def to_atomspace(atomspace : AtomSpace::AtomSpace)
        @goals.each do |goal|
          goal_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "goal_#{goal.name}")
          goal.conditions.each do |cond|
            cond_node = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, cond)
            atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [cond_node, goal_node])
          end
        end
      end
    end
  end
end
