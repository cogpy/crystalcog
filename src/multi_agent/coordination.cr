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
        @priority : Float64 = 1.0
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
  end
end
