# Multi-Agent Coordination for CrystalCog
#
# This module implements coordination protocols for multi-agent systems,
# including task allocation, negotiation, and distributed reasoning.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./communication"

module MultiAgent
  module Coordination
    VERSION = "0.1.0"

    class CoordinationException < Exception
    end

    # Task that can be allocated to agents
    class Task
      getter id : String
      getter name : String
      getter description : String
      getter required_capabilities : Array(String)
      getter priority : Float64
      property assigned_to : String?
      property status : TaskStatus

      enum TaskStatus
        PENDING
        ASSIGNED
        IN_PROGRESS
        COMPLETED
        FAILED
      end

      def initialize(
        @name : String,
        @description : String,
        @required_capabilities : Array(String) = [] of String,
        @priority : Float64 = 1.0,
      )
        @id = Random::Secure.hex(8)
        @assigned_to = nil
        @status = TaskStatus::PENDING
      end
    end

    # An agent in the multi-agent system
    class Agent
      getter id : String
      getter name : String
      getter capabilities : Array(String)
      getter mailbox : Communication::Mailbox
      property current_task : Task?

      def initialize(@id : String, @name : String, @capabilities : Array(String) = [] of String)
        @mailbox = Communication::Mailbox.new(@id)
        @current_task = nil
        CogUtil::Logger.debug("Agent '#{@name}' (#{@id}) created with capabilities: #{@capabilities.join(", ")}")
      end

      def can_handle?(task : Task) : Bool
        task.required_capabilities.all? { |cap| @capabilities.includes?(cap) }
      end

      def accept_task(task : Task) : Bool
        return false unless can_handle?(task)
        @current_task = task
        task.assigned_to = @id
        task.status = Task::TaskStatus::ASSIGNED
        CogUtil::Logger.debug("Agent '#{@name}' accepted task '#{task.name}'")
        true
      end

      def complete_task : Bool
        task = @current_task
        return false unless task
        task.status = Task::TaskStatus::COMPLETED
        @current_task = nil
        true
      end

      def busy? : Bool
        !@current_task.nil?
      end
    end

    # Contract Net Protocol: auctioneer broadcasts tasks; agents bid; best bid wins
    class ContractNetCoordinator
      getter agents : Hash(String, Agent)
      getter tasks : Array(Task)
      getter bus : Communication::MessageBus

      def initialize
        @agents = {} of String => Agent
        @tasks = [] of Task
        @bus = Communication::MessageBus.new
        CogUtil::Logger.info("ContractNetCoordinator initialized")
      end

      def register_agent(agent : Agent)
        @agents[agent.id] = agent
        @bus.register(agent.id)
      end

      def submit_task(task : Task)
        @tasks << task
        CogUtil::Logger.info("Task '#{task.name}' submitted (priority #{task.priority})")
      end

      # Allocate pending tasks to available agents
      def allocate_tasks : Int32
        allocated = 0
        pending = @tasks.select { |t| t.status == Task::TaskStatus::PENDING }
          .sort_by { |t| -t.priority }

        pending.each do |task|
          # Find best available agent: highest capability match + not busy
          candidates = @agents.values
            .reject(&.busy?)
            .select { |a| a.can_handle?(task) }

          next if candidates.empty?

          # Simple selection: pick the agent with the most capabilities (specialized first)
          best = candidates.max_by { |a| a.capabilities.size }
          best.accept_task(task)

          # Inform agent via message bus
          inform_msg = Communication::Message.new(
            "coordinator",
            best.id,
            Communication::Performative::REQUEST,
            "execute:#{task.id}:#{task.name}"
          )
          @bus.send(inform_msg)
          allocated += 1
        end

        allocated
      end

      # Mark a task as completed by an agent
      def complete_task(agent_id : String, task_id : String) : Bool
        agent = @agents[agent_id]?
        return false unless agent

        task = @tasks.find { |t| t.id == task_id }
        return false unless task

        agent.complete_task
        task.status = Task::TaskStatus::COMPLETED
        CogUtil::Logger.info("Task '#{task.name}' completed by agent '#{agent.name}'")
        true
      end

      # Store coordination state in AtomSpace
      def to_atomspace(atomspace : AtomSpace::AtomSpace)
        @agents.each do |_id, agent|
          agent_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "agent_#{agent.name}")
          agent.capabilities.each do |cap|
            cap_node = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "has_capability_#{cap}")
            atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [cap_node, agent_node])
          end
        end

        @tasks.each do |task|
          task_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "task_#{task.name}")
          status_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, task.status.to_s)
          atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [status_node, task_node])
        end
      end
    end

    # Bilateral negotiation over a proposal value
    class Negotiator
      getter agent_a : String
      getter agent_b : String
      getter history : Array(Tuple(String, Float64))

      def initialize(@agent_a : String, @agent_b : String)
        @history = [] of Tuple(String, Float64)
      end

      # Alternating offers; each side concedes toward the midpoint until gap <= tolerance
      def negotiate(offer_a : Float64, offer_b : Float64, tolerance : Float64 = 0.05,
                    max_rounds : Int32 = 20) : Float64?
        a = offer_a
        b = offer_b
        max_rounds.times do |round|
          proposer = round.even? ? @agent_a : @agent_b
          current = round.even? ? a : b
          @history << {proposer, current}

          gap = (a - b).abs
          return (a + b) / 2.0 if gap <= tolerance

          # Concede 25% of remaining gap each round
          mid = (a + b) / 2.0
          if round.even?
            a = a + (mid - a) * 0.25
          else
            b = b + (mid - b) * 0.25
          end
        end
        nil
      end
    end

    # Majority / weighted consensus among agents
    class ConsensusEngine
      def majority(votes : Hash(String, String)) : String?
        return nil if votes.empty?
        tallies = Hash(String, Int32).new(0)
        votes.each_value { |v| tallies[v] += 1 }
        winner, count = tallies.max_by { |_, c| c }
        # Require strict majority
        count > votes.size / 2.0 ? winner : nil
      end

      def weighted(votes : Hash(String, String), weights : Hash(String, Float64)) : String?
        return nil if votes.empty?
        scores = Hash(String, Float64).new(0.0)
        votes.each do |agent, choice|
          scores[choice] += weights[agent]? || 1.0
        end
        scores.max_by { |_, s| s }[0]
      end

      # Iterative opinion dynamics: agents adopt neighbor majority until stable
      def iterate(opinions : Hash(String, String),
                  neighbors : Hash(String, Array(String)),
                  max_iters : Int32 = 10) : Hash(String, String)
        current = opinions.dup
        max_iters.times do
          nxt = current.dup
          current.each_key do |agent|
            neigh = neighbors[agent]? || [] of String
            next if neigh.empty?
            ballots = neigh.map { |n| current[n]? }.compact
            ballots << current[agent]
            tallies = Hash(String, Int32).new(0)
            ballots.each { |b| tallies[b] += 1 }
            nxt[agent] = tallies.max_by { |_, c| c }[0]
          end
          break if nxt == current
          current = nxt
        end
        current
      end
    end

    # Coalition formation based on complementary capabilities
    class CoalitionFormer
      struct Coalition
        getter members : Array(String)
        getter capabilities : Array(String)
        getter value : Float64

        def initialize(@members : Array(String), @capabilities : Array(String), @value : Float64)
        end
      end

      def form(agents : Array(Agent), required : Array(String),
               max_size : Int32 = 4) : Coalition?
        return nil if agents.empty? || required.empty?

        # Greedy set cover by capability gain
        remaining = required.dup
        selected = [] of Agent
        covered = Set(String).new

        while !remaining.empty? && selected.size < max_size
          best = nil.as(Agent?)
          best_gain = 0
          agents.each do |a|
            next if selected.includes?(a)
            gain = a.capabilities.count { |c| remaining.includes?(c) && !covered.includes?(c) }
            if gain > best_gain
              best_gain = gain
              best = a
            end
          end
          break unless best && best_gain > 0
          selected << best
          best.capabilities.each { |c| covered << c if remaining.includes?(c) }
          remaining.reject! { |c| covered.includes?(c) }
        end

        return nil if selected.empty?
        caps = selected.flat_map(&.capabilities).uniq
        value = required.count { |c| caps.includes?(c) }.to_f / required.size
        Coalition.new(selected.map(&.id), caps, value)
      end

      # Partition agents into non-overlapping coalitions for a set of tasks
      def partition_for_tasks(agents : Array(Agent), tasks : Array(Task)) : Array(Coalition)
        available = agents.dup
        coalitions = [] of Coalition
        tasks.sort_by { |t| -t.priority }.each do |task|
          coal = form(available, task.required_capabilities)
          next unless coal
          coalitions << coal
          available.reject! { |a| coal.members.includes?(a.id) }
        end
        coalitions
      end
    end

    # Shared mental model: common beliefs across agents with consensus tracking
    class SharedMentalModel
      getter beliefs : Hash(String, Float64) # proposition -> confidence
      getter endorsements : Hash(String, Set(String)) # proposition -> agent ids

      def initialize
        @beliefs = {} of String => Float64
        @endorsements = Hash(String, Set(String)).new { |h, k| h[k] = Set(String).new }
      end

      def assert(agent_id : String, proposition : String, confidence : Float64)
        conf = confidence.clamp(0.0, 1.0)
        @endorsements[proposition] << agent_id
        # Confidence = average of endorsing agents' latest (simplified: max then dilute)
        prev = @beliefs[proposition]? || 0.0
        n = @endorsements[proposition].size.to_f
        @beliefs[proposition] = (prev * (n - 1) + conf) / n
      end

      def retract(agent_id : String, proposition : String)
        @endorsements[proposition].delete(agent_id)
        if @endorsements[proposition].empty?
          @beliefs.delete(proposition)
          @endorsements.delete(proposition)
        end
      end

      def consensus?(proposition : String, min_agents : Int32, min_confidence : Float64 = 0.5) : Bool
        (@endorsements[proposition]?.try(&.size) || 0) >= min_agents &&
          (@beliefs[proposition]? || 0.0) >= min_confidence
      end

      def common_ground(min_agents : Int32 = 2) : Array(String)
        @beliefs.keys.select { |p| consensus?(p, min_agents) }
      end

      def to_atomspace(atomspace : AtomSpace::AtomSpace)
        @beliefs.each do |prop, conf|
          node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "belief:#{prop}")
          pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "shared_belief")
          atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [pred, node],
            AtomSpace::SimpleTruthValue.new(conf, 0.9)
          )
        end
      end
    end
  end
end
