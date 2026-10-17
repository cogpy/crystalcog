# Multi-Agent Coordination Module for CrystalCog
#
# This module provides multi-agent coordination capabilities including:
# - Agent communication protocols
# - Distributed task allocation
# - Consensus mechanisms
# - Coalition formation
# - Negotiation strategies
# - Shared knowledge bases
#
# References:
# - Multi-Agent Systems: Wooldridge 2009
# - Contract Net Protocol: Smith 1980
# - BDI Agents: Rao & Georgeff 1995

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../temporal/temporal"
require "../behavior/behavior"

module MultiAgent
  VERSION = "0.1.0"

  # Exception classes
  class MultiAgentException < Exception
  end

  class CommunicationException < MultiAgentException
  end

  class CoordinationException < MultiAgentException
  end

  class NegotiationFailedException < MultiAgentException
  end

  # Agent identifier
  struct AgentID
    getter id : String
    getter group : String?
    getter capabilities : Array(String)

    def initialize(@id : String, @group : String? = nil, @capabilities : Array(String) = [] of String)
    end

    def to_s : String
      @group ? "#{@group}/#{@id}" : @id
    end

    def ==(other : AgentID) : Bool
      @id == other.id
    end

    def hash : UInt64
      @id.hash
    end
  end

  # Message types for agent communication
  enum MessageType
    INFORM        # Share information
    REQUEST       # Request action
    QUERY         # Ask for information
    PROPOSE       # Make a proposal
    ACCEPT        # Accept proposal
    REJECT        # Reject proposal
    CONFIRM       # Confirm receipt/action
    CANCEL        # Cancel previous message
    CALL_FOR_PROPOSAL  # CFP in Contract Net
    BID           # Response to CFP
    AWARD         # Award contract
  end

  # Agent message
  class Message
    getter id : String
    getter sender : AgentID
    getter receiver : AgentID
    getter type : MessageType
    getter content : Hash(String, String | Float64 | Bool | Array(String))
    getter timestamp : Temporal::TimePoint
    getter reply_to : String?
    getter conversation_id : String

    def initialize(@sender : AgentID, @receiver : AgentID, @type : MessageType,
                   @content : Hash(String, String | Float64 | Bool | Array(String)) = {} of String => String | Float64 | Bool | Array(String),
                   @reply_to : String? = nil,
                   @conversation_id : String = UUID.random.to_s)
      @id = UUID.random.to_s
      @timestamp = Temporal::TimePoint.now
    end

    def reply(type : MessageType, content : Hash(String, String | Float64 | Bool | Array(String))) : Message
      Message.new(
        @receiver,
        @sender,
        type,
        content,
        @id,
        @conversation_id
      )
    end

    def to_s : String
      "Message(#{@id[0..7]}): #{@sender} -> #{@receiver} [#{@type}]"
    end
  end

  # Message queue for agent communication
  class MessageQueue
    getter messages : Array(Message)
    @max_size : Int32

    def initialize(@max_size : Int32 = 1000)
      @messages = [] of Message
    end

    def push(message : Message)
      @messages << message
      @messages.shift if @messages.size > @max_size
    end

    def pop : Message?
      @messages.shift?
    end

    def peek : Message?
      @messages.first?
    end

    def size : Int32
      @messages.size
    end

    def empty? : Bool
      @messages.empty?
    end

    def clear
      @messages.clear
    end

    def filter(&block : Message -> Bool) : Array(Message)
      @messages.select(&block)
    end

    def filter_by_type(type : MessageType) : Array(Message)
      filter { |m| m.type == type }
    end

    def filter_by_sender(sender : AgentID) : Array(Message)
      filter { |m| m.sender == sender }
    end

    def filter_by_conversation(conversation_id : String) : Array(Message)
      filter { |m| m.conversation_id == conversation_id }
    end
  end

  # Agent belief, desire, intention (BDI) model
  class BDIModel
    getter beliefs : Hash(String, String | Float64 | Bool)
    getter desires : Array(Desire)
    getter intentions : Array(Intention)

    def initialize
      @beliefs = {} of String => String | Float64 | Bool
      @desires = [] of Desire
      @intentions = [] of Intention
    end

    def add_belief(key : String, value : String | Float64 | Bool)
      @beliefs[key] = value
    end

    def remove_belief(key : String)
      @beliefs.delete(key)
    end

    def has_belief?(key : String) : Bool
      @beliefs.has_key?(key)
    end

    def get_belief(key : String) : (String | Float64 | Bool)?
      @beliefs[key]?
    end

    def add_desire(desire : Desire)
      @desires << desire
      @desires.sort_by! { |d| -d.priority }
    end

    def remove_desire(name : String)
      @desires.reject! { |d| d.name == name }
    end

    def add_intention(intention : Intention)
      @intentions << intention
    end

    def remove_intention(name : String)
      @intentions.reject! { |i| i.name == name }
    end

    # Deliberation - select desires to pursue based on beliefs
    def deliberate : Array(Desire)
      @desires.select do |desire|
        desire.preconditions.all? do |key, expected|
          @beliefs[key]? == expected
        end
      end
    end

    # Means-ends reasoning - form intentions from desires
    def form_intentions(available_actions : Array(String))
      active_desires = deliberate

      active_desires.each do |desire|
        # Check if we already have an intention for this desire
        next if @intentions.any? { |i| i.desire_name == desire.name }

        # Find actions that can achieve the desire
        matching_actions = available_actions.select do |action|
          desire.achievable_by.includes?(action)
        end

        unless matching_actions.empty?
          intention = Intention.new(
            "achieve_#{desire.name}",
            desire.name,
            matching_actions.first
          )
          @intentions << intention
        end
      end
    end
  end

  struct Desire
    getter name : String
    getter priority : Float64
    getter preconditions : Hash(String, String | Float64 | Bool)
    getter achievable_by : Array(String)

    def initialize(@name : String, @priority : Float64 = 1.0,
                   @preconditions : Hash(String, String | Float64 | Bool) = {} of String => String | Float64 | Bool,
                   @achievable_by : Array(String) = [] of String)
    end
  end

  struct Intention
    getter name : String
    getter desire_name : String
    getter action : String
    property status : Symbol

    def initialize(@name : String, @desire_name : String, @action : String)
      @status = :pending
    end
  end

  # Abstract agent class
  abstract class Agent
    getter id : AgentID
    getter inbox : MessageQueue
    getter outbox : MessageQueue
    getter bdi : BDIModel
    getter atomspace : AtomSpace::AtomSpace
    @running : Bool

    def initialize(@id : AgentID, @atomspace : AtomSpace::AtomSpace)
      @inbox = MessageQueue.new
      @outbox = MessageQueue.new
      @bdi = BDIModel.new
      @running = false
      CogUtil::Logger.info("Agent #{@id} created")
    end

    abstract def process_message(message : Message)
    abstract def decide : Array(Message)
    abstract def act

    def receive(message : Message)
      @inbox.push(message)
      CogUtil::Logger.debug("#{@id} received: #{message}")
    end

    def send_message(message : Message)
      @outbox.push(message)
      CogUtil::Logger.debug("#{@id} sent: #{message}")
    end

    def start
      @running = true
      CogUtil::Logger.info("Agent #{@id} started")
    end

    def stop
      @running = false
      CogUtil::Logger.info("Agent #{@id} stopped")
    end

    def running? : Bool
      @running
    end

    def step
      return unless @running

      # Process incoming messages
      while message = @inbox.pop
        process_message(message)
      end

      # Deliberate and decide
      outgoing = decide

      # Send outgoing messages
      outgoing.each { |m| send_message(m) }

      # Act based on intentions
      act
    end

    def has_capability?(capability : String) : Bool
      @id.capabilities.includes?(capability)
    end
  end

  # Coordinator agent for task allocation
  class CoordinatorAgent < Agent
    getter task_queue : Array(Task)
    getter agent_registry : Hash(String, AgentID)
    getter active_contracts : Hash(String, Contract)

    def initialize(id : AgentID, atomspace : AtomSpace::AtomSpace)
      super(id, atomspace)
      @task_queue = [] of Task
      @agent_registry = {} of String => AgentID
      @active_contracts = {} of String => Contract
    end

    def register_agent(agent_id : AgentID)
      @agent_registry[agent_id.id] = agent_id
      CogUtil::Logger.info("Registered agent: #{agent_id}")
    end

    def unregister_agent(agent_id : String)
      @agent_registry.delete(agent_id)
    end

    def submit_task(task : Task)
      @task_queue << task
      CogUtil::Logger.info("Task submitted: #{task.name}")
    end

    def process_message(message : Message)
      case message.type
      when MessageType::BID
        handle_bid(message)
      when MessageType::INFORM
        handle_inform(message)
      when MessageType::CONFIRM
        handle_confirmation(message)
      else
        CogUtil::Logger.debug("Unhandled message type: #{message.type}")
      end
    end

    def decide : Array(Message)
      messages = [] of Message

      # Issue CFPs for pending tasks
      @task_queue.each do |task|
        next if @active_contracts.has_key?(task.id)

        # Find capable agents
        capable = @agent_registry.values.select do |agent|
          task.required_capabilities.all? { |cap| agent.capabilities.includes?(cap) }
        end

        capable.each do |agent|
          cfp = Message.new(
            @id,
            agent,
            MessageType::CALL_FOR_PROPOSAL,
            {
              "task_id"          => task.id,
              "task_name"        => task.name,
              "required_caps"    => task.required_capabilities,
              "deadline"         => task.deadline.to_s,
              "estimated_effort" => task.estimated_effort,
            } of String => String | Float64 | Bool | Array(String)
          )
          messages << cfp
        end
      end

      messages
    end

    def act
      # Evaluate bids and award contracts
      @active_contracts.each do |task_id, contract|
        if contract.status == :pending && !contract.bids.empty?
          # Select best bid (lowest cost)
          best_bid = contract.bids.min_by { |b| b.cost }

          # Award contract
          contract.winner = best_bid.bidder
          contract.status = :awarded

          award = Message.new(
            @id,
            best_bid.bidder,
            MessageType::AWARD,
            {
              "task_id"    => task_id,
              "awarded_to" => best_bid.bidder.id,
            } of String => String | Float64 | Bool | Array(String)
          )
          send_message(award)

          # Notify other bidders
          contract.bids.each do |bid|
            next if bid.bidder == best_bid.bidder
            reject = Message.new(
              @id,
              bid.bidder,
              MessageType::REJECT,
              {"task_id" => task_id} of String => String | Float64 | Bool | Array(String)
            )
            send_message(reject)
          end
        end
      end
    end

    private def handle_bid(message : Message)
      task_id = message.content["task_id"]?.as?(String)
      return unless task_id

      cost = message.content["cost"]?.as?(Float64) || Float64::INFINITY

      if contract = @active_contracts[task_id]?
        contract.bids << Bid.new(message.sender, cost)
      else
        # Create new contract
        contract = Contract.new(task_id)
        contract.bids << Bid.new(message.sender, cost)
        @active_contracts[task_id] = contract
      end
    end

    private def handle_inform(message : Message)
      # Handle status updates
      if status = message.content["status"]?.as?(String)
        if task_id = message.content["task_id"]?.as?(String)
          if contract = @active_contracts[task_id]?
            case status
            when "completed"
              contract.status = :completed
              CogUtil::Logger.info("Task #{task_id} completed by #{message.sender}")
            when "failed"
              contract.status = :failed
              CogUtil::Logger.warn("Task #{task_id} failed by #{message.sender}")
            end
          end
        end
      end
    end

    private def handle_confirmation(message : Message)
      # Handle confirmations
    end
  end

  # Worker agent that can execute tasks
  class WorkerAgent < Agent
    getter current_task : Task?
    getter capabilities : Array(String)
    @task_executor : Proc(Task, Bool)?

    def initialize(id : AgentID, atomspace : AtomSpace::AtomSpace)
      super(id, atomspace)
      @current_task = nil
      @capabilities = id.capabilities.dup
      @task_executor = nil
    end

    def set_task_executor(&executor : Proc(Task, Bool))
      @task_executor = executor
    end

    def process_message(message : Message)
      case message.type
      when MessageType::CALL_FOR_PROPOSAL
        handle_cfp(message)
      when MessageType::AWARD
        handle_award(message)
      when MessageType::REJECT
        handle_reject(message)
      when MessageType::CANCEL
        handle_cancel(message)
      when MessageType::REQUEST
        handle_request(message)
      else
        CogUtil::Logger.debug("Unhandled message type: #{message.type}")
      end
    end

    def decide : Array(Message)
      messages = [] of Message

      # Report task status
      if task = @current_task
        if task.status == :completed || task.status == :failed
          status_msg = Message.new(
            @id,
            task.requester,
            MessageType::INFORM,
            {
              "task_id" => task.id,
              "status"  => task.status.to_s,
            } of String => String | Float64 | Bool | Array(String)
          )
          messages << status_msg
          @current_task = nil
        end
      end

      messages
    end

    def act
      if task = @current_task
        return unless task.status == :in_progress

        # Execute task
        if executor = @task_executor
          success = executor.call(task)
          task.status = success ? :completed : :failed
        else
          # Simulate task execution
          task.status = :completed
        end
      end
    end

    def is_busy? : Bool
      !@current_task.nil? && @current_task.not_nil!.status == :in_progress
    end

    private def handle_cfp(message : Message)
      # Check if we can handle this task
      required = message.content["required_caps"]?.as?(Array(String)) || [] of String
      can_handle = required.all? { |cap| @capabilities.includes?(cap) }

      if can_handle && !is_busy?
        # Calculate bid cost based on estimated effort
        effort = message.content["estimated_effort"]?.as?(Float64) || 1.0
        cost = effort * (1.0 + Random.rand * 0.2)  # Add some variance

        bid = message.reply(
          MessageType::BID,
          {
            "task_id" => message.content["task_id"]? || "",
            "cost"    => cost,
          } of String => String | Float64 | Bool | Array(String)
        )
        send_message(bid)
      end
    end

    private def handle_award(message : Message)
      task_id = message.content["task_id"]?.as?(String)
      return unless task_id

      # Accept the task
      task = Task.new(task_id, "awarded_task", message.sender)
      task.status = :in_progress
      @current_task = task

      confirm = message.reply(
        MessageType::CONFIRM,
        {"task_id" => task_id} of String => String | Float64 | Bool | Array(String)
      )
      send_message(confirm)

      CogUtil::Logger.info("#{@id} accepted task: #{task_id}")
    end

    private def handle_reject(message : Message)
      # Bid was rejected
      CogUtil::Logger.debug("#{@id} bid rejected for task")
    end

    private def handle_cancel(message : Message)
      if task = @current_task
        if message.content["task_id"]?.as?(String) == task.id
          task.status = :cancelled
          @current_task = nil
        end
      end
    end

    private def handle_request(message : Message)
      # Handle direct requests
    end
  end

  # Task definition
  class Task
    getter id : String
    getter name : String
    getter requester : AgentID
    getter required_capabilities : Array(String)
    getter deadline : Temporal::TimePoint
    getter estimated_effort : Float64
    property status : Symbol
    property result : String?

    def initialize(@id : String, @name : String, @requester : AgentID,
                   @required_capabilities : Array(String) = [] of String,
                   @deadline : Temporal::TimePoint = Temporal::TimePoint.now + Temporal::Duration.hours(1),
                   @estimated_effort : Float64 = 1.0)
      @status = :pending
      @result = nil
    end
  end

  # Contract for task execution
  class Contract
    getter task_id : String
    getter bids : Array(Bid)
    property winner : AgentID?
    property status : Symbol

    def initialize(@task_id : String)
      @bids = [] of Bid
      @winner = nil
      @status = :pending
    end
  end

  struct Bid
    getter bidder : AgentID
    getter cost : Float64

    def initialize(@bidder : AgentID, @cost : Float64)
    end
  end

  # Coalition formation
  class Coalition
    getter id : String
    getter members : Array(AgentID)
    getter goal : String
    getter value : Float64
    @payoff_distribution : Hash(String, Float64)

    def initialize(@id : String, @goal : String, @value : Float64 = 0.0)
      @members = [] of AgentID
      @payoff_distribution = {} of String => Float64
    end

    def add_member(agent : AgentID)
      @members << agent unless @members.includes?(agent)
    end

    def remove_member(agent_id : String)
      @members.reject! { |m| m.id == agent_id }
    end

    def set_payoff(agent_id : String, payoff : Float64)
      @payoff_distribution[agent_id] = payoff
    end

    def get_payoff(agent_id : String) : Float64
      @payoff_distribution[agent_id]? || 0.0
    end

    def size : Int32
      @members.size
    end

    def contains?(agent_id : String) : Bool
      @members.any? { |m| m.id == agent_id }
    end

    # Calculate Shapley value for fair payoff distribution
    def calculate_shapley_values(&characteristic_function : Array(AgentID) -> Float64)
      n = @members.size
      return if n == 0

      @members.each do |agent|
        shapley = 0.0
        other_members = @members.reject { |m| m == agent }

        # Iterate over all subsets
        (0...(1 << other_members.size)).each do |mask|
          subset = [] of AgentID
          other_members.each_with_index do |m, i|
            subset << m if (mask & (1 << i)) != 0
          end

          subset_size = subset.size

          # Marginal contribution
          with_agent = subset + [agent]
          marginal = characteristic_function.call(with_agent) - characteristic_function.call(subset)

          # Shapley weight
          weight = factorial(subset_size) * factorial(n - subset_size - 1) / factorial(n).to_f64
          shapley += weight * marginal
        end

        @payoff_distribution[agent.id] = shapley
      end
    end

    private def factorial(n : Int32) : Int64
      return 1_i64 if n <= 1
      (1..n).reduce(1_i64) { |acc, i| acc * i }
    end
  end

  # Coalition formation algorithm
  class CoalitionFormation
    getter agents : Array(AgentID)
    getter coalitions : Array(Coalition)
    @characteristic_function : Proc(Array(AgentID), Float64)?

    def initialize(@agents : Array(AgentID))
      @coalitions = [] of Coalition
      @characteristic_function = nil
    end

    def set_characteristic_function(&func : Proc(Array(AgentID), Float64))
      @characteristic_function = func
    end

    # Form optimal coalitions using greedy algorithm
    def form_coalitions(max_coalition_size : Int32 = 5) : Array(Coalition)
      return @coalitions unless cf = @characteristic_function

      remaining = @agents.dup
      coalition_id = 0

      while !remaining.empty?
        best_coalition = nil
        best_value = 0.0

        # Try different coalition sizes
        (1..[max_coalition_size, remaining.size].min).each do |size|
          # Sample coalitions of this size
          100.times do
            sample = remaining.sample(size)
            value = cf.call(sample)

            if value > best_value
              best_value = value
              best_coalition = sample
            end
          end
        end

        if coalition = best_coalition
          new_coalition = Coalition.new("coalition_#{coalition_id}", "task", best_value)
          coalition.each { |a| new_coalition.add_member(a) }
          new_coalition.calculate_shapley_values { |s| cf.call(s) }
          @coalitions << new_coalition

          remaining = remaining.reject { |a| coalition.includes?(a) }
          coalition_id += 1
        else
          # Form singleton coalitions for remaining agents
          remaining.each do |agent|
            singleton = Coalition.new("coalition_#{coalition_id}", "task", cf.call([agent]))
            singleton.add_member(agent)
            singleton.set_payoff(agent.id, cf.call([agent]))
            @coalitions << singleton
            coalition_id += 1
          end
          break
        end
      end

      @coalitions
    end
  end

  # Negotiation protocol
  abstract class NegotiationProtocol
    getter participants : Array(AgentID)
    getter status : Symbol

    def initialize(@participants : Array(AgentID) = [] of AgentID)
      @status = :pending
    end

    abstract def start
    abstract def receive_proposal(from : AgentID, proposal : Proposal) : Bool
    abstract def get_agreement : Proposal?
  end

  # Proposal for negotiation
  class Proposal
    getter proposer : AgentID
    getter terms : Hash(String, String | Float64 | Bool)
    getter utility : Float64

    def initialize(@proposer : AgentID,
                   @terms : Hash(String, String | Float64 | Bool) = {} of String => String | Float64 | Bool,
                   @utility : Float64 = 0.0)
    end

    def accept?(threshold : Float64) : Bool
      @utility >= threshold
    end
  end

  # Alternating offers protocol
  class AlternatingOffers < NegotiationProtocol
    getter max_rounds : Int32
    getter current_round : Int32
    getter proposals : Array(Proposal)
    getter agreement : Proposal?
    @utility_functions : Hash(String, Proc(Proposal, Float64))
    @discount_factor : Float64

    def initialize(participants : Array(AgentID),
                   @max_rounds : Int32 = 10,
                   @discount_factor : Float64 = 0.95)
      super(participants)
      @current_round = 0
      @proposals = [] of Proposal
      @agreement = nil
      @utility_functions = {} of String => Proc(Proposal, Float64)
    end

    def set_utility_function(agent_id : String, &func : Proc(Proposal, Float64))
      @utility_functions[agent_id] = func
    end

    def start
      @status = :active
      @current_round = 0
      CogUtil::Logger.info("Alternating offers negotiation started")
    end

    def receive_proposal(from : AgentID, proposal : Proposal) : Bool
      return false unless @status == :active
      return false unless @participants.includes?(from)

      @proposals << proposal
      @current_round += 1

      # Check if other party accepts
      other = @participants.find { |p| p != from }
      return false unless other

      utility_func = @utility_functions[other.id]?
      return false unless utility_func

      # Apply discount factor
      discounted_threshold = 0.5 * (@discount_factor ** @current_round)
      utility = utility_func.call(proposal)

      if utility >= discounted_threshold
        @agreement = proposal
        @status = :agreed
        CogUtil::Logger.info("Negotiation agreement reached at round #{@current_round}")
        return true
      end

      if @current_round >= @max_rounds
        @status = :failed
        CogUtil::Logger.warn("Negotiation failed after #{@max_rounds} rounds")
      end

      false
    end

    def get_agreement : Proposal?
      @agreement
    end

    def current_proposer : AgentID?
      return nil if @participants.size < 2
      @participants[@current_round % @participants.size]
    end
  end

  # Multi-agent environment
  class MultiAgentEnvironment
    getter agents : Hash(String, Agent)
    getter coordinator : CoordinatorAgent?
    getter message_bus : MessageBus
    getter shared_atomspace : AtomSpace::AtomSpace
    @running : Bool

    def initialize(@shared_atomspace : AtomSpace::AtomSpace)
      @agents = {} of String => Agent
      @coordinator = nil
      @message_bus = MessageBus.new
      @running = false
      CogUtil::Logger.info("MultiAgentEnvironment created")
    end

    def add_agent(agent : Agent)
      @agents[agent.id.id] = agent
      @message_bus.register(agent.id)
    end

    def remove_agent(agent_id : String)
      if agent = @agents.delete(agent_id)
        @message_bus.unregister(agent.id)
      end
    end

    def set_coordinator(agent : CoordinatorAgent)
      @coordinator = agent
      add_agent(agent)
    end

    def get_agent(id : String) : Agent?
      @agents[id]?
    end

    def start
      @running = true
      @agents.each_value(&.start)
      CogUtil::Logger.info("MultiAgentEnvironment started with #{@agents.size} agents")
    end

    def stop
      @running = false
      @agents.each_value(&.stop)
      CogUtil::Logger.info("MultiAgentEnvironment stopped")
    end

    def step
      return unless @running

      # Each agent processes messages and decides
      @agents.each_value(&.step)

      # Route messages
      @agents.each_value do |agent|
        while message = agent.outbox.pop
          route_message(message)
        end
      end
    end

    def run(steps : Int32 = 100)
      start
      steps.times { step }
      stop
    end

    def broadcast(message : Message)
      @agents.each_value do |agent|
        next if agent.id == message.sender
        agent.receive(message)
      end
    end

    private def route_message(message : Message)
      if receiver = @agents[message.receiver.id]?
        receiver.receive(message)
      else
        CogUtil::Logger.warn("No agent found for: #{message.receiver}")
      end
    end
  end

  # Message bus for agent communication
  class MessageBus
    getter registered : Set(AgentID)
    getter topics : Hash(String, Array(AgentID))

    def initialize
      @registered = Set(AgentID).new
      @topics = {} of String => Array(AgentID)
    end

    def register(agent : AgentID)
      @registered.add(agent)
    end

    def unregister(agent : AgentID)
      @registered.delete(agent)
      @topics.each_value { |subs| subs.delete(agent) }
    end

    def subscribe(agent : AgentID, topic : String)
      @topics[topic] ||= [] of AgentID
      @topics[topic] << agent unless @topics[topic].includes?(agent)
    end

    def unsubscribe(agent : AgentID, topic : String)
      @topics[topic]?.try(&.delete(agent))
    end

    def subscribers(topic : String) : Array(AgentID)
      @topics[topic]? || [] of AgentID
    end
  end

  # Consensus mechanism
  class ConsensusMechanism
    getter participants : Array(AgentID)
    getter values : Hash(String, Float64)
    getter consensus_value : Float64?
    @threshold : Float64

    def initialize(@participants : Array(AgentID) = [] of AgentID, @threshold : Float64 = 0.66)
      @values = {} of String => Float64
      @consensus_value = nil
    end

    def propose(agent : AgentID, value : Float64)
      return unless @participants.includes?(agent)
      @values[agent.id] = value
      check_consensus
    end

    def has_consensus? : Bool
      !@consensus_value.nil?
    end

    private def check_consensus
      return if @values.size < @participants.size * @threshold

      # Simple averaging for numerical consensus
      avg = @values.values.sum / @values.size

      # Check if values are close enough
      max_deviation = @values.values.max_of { |v| (v - avg).abs }

      if max_deviation < 0.1  # Threshold for agreement
        @consensus_value = avg
        CogUtil::Logger.info("Consensus reached: #{avg}")
      end
    end
  end

  # Module-level convenience methods
  def self.create_agent_id(id : String, capabilities : Array(String) = [] of String) : AgentID
    AgentID.new(id, nil, capabilities)
  end

  def self.create_environment(atomspace : AtomSpace::AtomSpace) : MultiAgentEnvironment
    MultiAgentEnvironment.new(atomspace)
  end

  def self.create_coordinator(id : String, atomspace : AtomSpace::AtomSpace) : CoordinatorAgent
    agent_id = AgentID.new(id, nil, ["coordinate", "allocate"])
    CoordinatorAgent.new(agent_id, atomspace)
  end

  def self.create_worker(id : String, atomspace : AtomSpace::AtomSpace,
                         capabilities : Array(String) = [] of String) : WorkerAgent
    agent_id = AgentID.new(id, nil, capabilities)
    WorkerAgent.new(agent_id, atomspace)
  end

  def self.create_task(name : String, requester : AgentID,
                       capabilities : Array(String) = [] of String) : Task
    Task.new(UUID.random.to_s, name, requester, capabilities)
  end
end
