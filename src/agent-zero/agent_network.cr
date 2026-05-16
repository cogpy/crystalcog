# Crystal implementation of Agent Network Management
# Part of Agent-Zero Genesis distributed cognitive agent networks
#
# This module manages networks of distributed cognitive agents,
# providing discovery, coordination, and collective intelligence capabilities.

require "./distributed_agents"
require "./network_services"
require "json"
require "../cogutil/cogutil"

module AgentZero
  # Manager for networks of distributed cognitive agents
  class AgentNetwork
    property name : String
    property agents : Hash(String, AgentNode)
    property network_config : NetworkConfig

    @discovery_server : DiscoveryServer?
    @consensus_manager : ConsensusManager?
    @task_coordinator : TaskCoordinator?
    @running : Bool = false

    struct NetworkConfig
      property discovery_port : Int32
      property discovery_host : String
      property network_topology : String
      property consensus_protocol : String
      property max_agents : Int32
      property heartbeat_interval : Int32
      property trust_threshold : Float64

      def initialize
        @discovery_port = 19000
        @discovery_host = "localhost"
        @network_topology = "mesh"
        @consensus_protocol = "raft"
        @max_agents = 100
        @heartbeat_interval = 30
        @trust_threshold = 0.5
      end
    end

    def initialize(@name : String, config : NetworkConfig? = nil)
      @network_config = config || NetworkConfig.new
      @agents = Hash(String, AgentNode).new

      CogUtil::Logger.info("AgentNetwork '#{@name}' initialized with #{@network_config.network_topology} topology")
    end

    # Start the agent network
    def start
      return if @running

      @running = true

      # Start network services
      start_discovery_server
      start_consensus_manager
      start_task_coordinator

      CogUtil::Logger.info("AgentNetwork '#{@name}' started")
    end

    # Stop the agent network
    def stop
      return unless @running

      @running = false

      # Stop all agents
      @agents.each_value(&.stop)

      # Stop network services
      @discovery_server.try(&.stop)
      @consensus_manager.try(&.stop)
      @task_coordinator.try(&.stop)

      CogUtil::Logger.info("AgentNetwork '#{@name}' stopped")
    end

    # Add an agent to the network
    def add_agent(agent : AgentNode) : Bool
      return false if @agents.size >= @network_config.max_agents
      return false if @agents.has_key?(agent.id)

      @agents[agent.id] = agent

      # Connect agent to existing network peers based on topology
      connect_agent_to_network(agent)

      # Register with discovery server
      @discovery_server.try(&.register_agent(agent))

      CogUtil::Logger.info("Added agent #{agent.name} to network #{@name}")
      true
    end

    # Remove an agent from the network
    def remove_agent(agent_id : String) : Bool
      agent = @agents.delete(agent_id)
      return false unless agent

      agent.stop
      @discovery_server.try(&.unregister_agent(agent_id))

      CogUtil::Logger.info("Removed agent #{agent.name} from network #{@name}")
      true
    end

    # Create and add a new agent to the network
    def create_agent(name : String, capabilities : Array(String) = [] of String) : AgentNode?
      return nil if @agents.size >= @network_config.max_agents

      # Find available port
      port = find_available_port(20000 + @agents.size)
      agent = AgentNode.new(name, @network_config.discovery_host, port)
      agent.capabilities = capabilities unless capabilities.empty?

      if add_agent(agent)
        agent.start
        return agent
      else
        return nil
      end
    end

    # Execute collaborative reasoning across the network
    def collaborative_reasoning(query : String, agent_selection : AgentSelection = AgentSelection::All,
                                timeout_seconds : Int32 = 60) : CollaborativeReasoningResult
      selected_agents = select_agents(agent_selection)

      return CollaborativeReasoningResult.new(query, [] of CollaborativeResult, 0.0) if selected_agents.empty?

      all_results = [] of CollaborativeResult
      reasoning_start = Time.instant

      # Execute reasoning on selected agents in parallel
      channel = Channel(Array(CollaborativeResult)).new

      selected_agents.each do |agent|
        spawn do
          results = agent.request_collaborative_reasoning(query, timeout_seconds)
          channel.send(results)
        end
      end

      # Collect results
      selected_agents.size.times do
        results = channel.receive
        all_results.concat(results)
      end

      # Calculate consensus confidence
      consensus_confidence = calculate_consensus_confidence(all_results)

      reasoning_time = (Time.instant - reasoning_start).total_milliseconds

      CogUtil::Logger.info("Network collaborative reasoning completed: #{all_results.size} results, " \
                           "consensus: #{consensus_confidence.round(3)}, time: #{reasoning_time.round(1)}ms")

      CollaborativeReasoningResult.new(query, all_results, consensus_confidence, reasoning_time)
    end

    # Distribute knowledge across the network
    def distribute_knowledge(knowledge : KnowledgeItem, propagation_strategy : PropagationStrategy = PropagationStrategy::Flood) : Int32
      case propagation_strategy
      when .flood?
        # Broadcast to all agents
        successful_shares = 0
        @agents.each_value do |agent|
          successful_shares += agent.share_knowledge(knowledge)
        end
        successful_shares
      when .selective?
        # Share only with agents that have relevant capabilities
        relevant_agents = @agents.values.select do |agent|
          agent.capabilities.any? { |cap| knowledge.content.includes?(cap) }
        end

        successful_shares = 0
        relevant_agents.each do |agent|
          successful_shares += agent.share_knowledge(knowledge)
        end
        successful_shares
      when .consensus?
        # Use consensus protocol to determine best agents for knowledge
        target_agents = @consensus_manager.try(&.select_knowledge_targets(knowledge)) || @agents.values

        successful_shares = 0
        target_agents.each do |agent|
          successful_shares += agent.share_knowledge(knowledge)
        end
        successful_shares
      else
        0
      end
    end

    # Coordinate distributed task execution
    def execute_distributed_task(task : DistributedTask) : TaskExecutionResult
      coordinator = @task_coordinator.not_nil!
      coordinator.execute_task(task, @agents.values)
    end

    # Get comprehensive network status
    def network_status : NetworkStatus
      agent_statuses = @agents.map do |id, agent|
        {id => agent.network_status}
      end.reduce({} of String => Hash(String, JSON::Any)) { |acc, item| acc.merge!(item) }

      # Calculate network metrics
      total_connections = @agents.values.sum(&.network_status["peer_count"].as_i64)
      avg_trust_level = @agents.values.map(&.trust_level).sum / @agents.size
      network_connectivity = @agents.size > 1 ? total_connections.to_f / (@agents.size * (@agents.size - 1)) : 0.0

      # Count active agents (those that are active or busy)
      active_count = @agents.values.count { |agent| agent.status == AgentNode::AgentStatus::Active || agent.status == AgentNode::AgentStatus::Busy }

      NetworkStatus.new(
        @name,
        @agents.size,
        active_count,
        @running,
        network_connectivity,
        avg_trust_level,
        agent_statuses,
        @network_config
      )
    end

    # Discover agents in the network
    def discover_agents(timeout_seconds : Int32 = 10) : Array(AgentNode)
      @discovery_server.try(&.discover_agents(timeout_seconds)) || [] of AgentNode
    end

    # Optimize network topology for better performance
    def optimize_topology : TopologyOptimizationResult
      current_efficiency = calculate_network_efficiency

      case @network_config.network_topology
      when "mesh"
        optimize_mesh_topology
      when "star"
        optimize_star_topology
      when "ring"
        optimize_ring_topology
      else
        TopologyOptimizationResult.new(false, current_efficiency, current_efficiency, "Unknown topology")
      end
    end

    private def start_discovery_server
      @discovery_server = DiscoveryServer.new(@network_config.discovery_host, @network_config.discovery_port)
      @discovery_server.not_nil!.start
    end

    private def start_consensus_manager
      @consensus_manager = ConsensusManager.new(@network_config.consensus_protocol, @agents.values)
      @consensus_manager.not_nil!.start
    end

    private def start_task_coordinator
      @task_coordinator = TaskCoordinator.new(@network_config)
    end

    private def connect_agent_to_network(agent : AgentNode)
      case @network_config.network_topology
      when "mesh"
        # Connect to all other agents (full mesh)
        @agents.each_value do |existing_agent|
          next if existing_agent.id == agent.id
          agent.connect_to_peer(existing_agent.host, existing_agent.port)
          existing_agent.connect_to_peer(agent.host, agent.port)
        end
      when "star"
        # Connect to a central hub (first agent becomes hub)
        if @agents.size > 1
          hub_agent = @agents.values.first
          agent.connect_to_peer(hub_agent.host, hub_agent.port)
          hub_agent.connect_to_peer(agent.host, agent.port)
        end
      when "ring"
        # Connect to previous agent in a ring topology
        if @agents.size > 1
          prev_agent = @agents.values.last
          agent.connect_to_peer(prev_agent.host, prev_agent.port)
          prev_agent.connect_to_peer(agent.host, agent.port)
        end
      end
    end

    private def select_agents(selection : AgentSelection) : Array(AgentNode)
      case selection
      when .all?
        @agents.values
      when .active_only?
        @agents.values.select { |agent| agent.status == AgentNode::AgentStatus::Active }
      when .high_trust?
        @agents.values.select { |agent| agent.trust_level >= @network_config.trust_threshold }
      when .random_sample?
        sample_size = Math.min(5, @agents.size)
        @agents.values.sample(sample_size)
      else
        [] of AgentNode
      end
    end

    private def calculate_consensus_confidence(results : Array(CollaborativeResult)) : Float64
      return 0.0 if results.empty?

      # Calculate weighted average confidence
      total_confidence = results.sum(&.confidence)
      avg_confidence = total_confidence / results.size

      # Factor in result consistency (simplified implementation)
      consistency_bonus = results.size > 1 ? 0.1 : 0.0

      Math.min(1.0, avg_confidence + consistency_bonus)
    end

    private def calculate_network_efficiency : Float64
      return 0.0 if @agents.size <= 1

      total_connections = @agents.values.sum { |agent| agent.network_status["peer_count"].as_i64 }
      max_connections = @agents.size * (@agents.size - 1)

      total_connections.to_f / max_connections
    end

    private def optimize_mesh_topology : TopologyOptimizationResult
      # For mesh topology, ensure all agents are connected to each other
      original_efficiency = calculate_network_efficiency

      @agents.each_value do |agent1|
        @agents.each_value do |agent2|
          next if agent1.id == agent2.id
          # Ensure bidirectional connections exist
          agent1.connect_to_peer(agent2.host, agent2.port)
        end
      end

      new_efficiency = calculate_network_efficiency
      improvement = new_efficiency - original_efficiency

      TopologyOptimizationResult.new(
        improvement > 0.01,
        original_efficiency,
        new_efficiency,
        "Mesh topology optimization completed"
      )
    end

    private def optimize_star_topology : TopologyOptimizationResult
      # For star topology, ensure all agents are connected to the hub
      original_efficiency = calculate_network_efficiency

      return TopologyOptimizationResult.new(false, original_efficiency, original_efficiency, "No agents to optimize") if @agents.empty?

      hub_agent = @agents.values.first

      @agents.each_value do |agent|
        next if agent.id == hub_agent.id
        agent.connect_to_peer(hub_agent.host, hub_agent.port)
        hub_agent.connect_to_peer(agent.host, agent.port)
      end

      new_efficiency = calculate_network_efficiency
      improvement = new_efficiency - original_efficiency

      TopologyOptimizationResult.new(
        improvement > 0.01,
        original_efficiency,
        new_efficiency,
        "Star topology optimization completed"
      )
    end

    private def optimize_ring_topology : TopologyOptimizationResult
      # For ring topology, connect each agent to the next one in a circle
      original_efficiency = calculate_network_efficiency

      return TopologyOptimizationResult.new(false, original_efficiency, original_efficiency, "Not enough agents for ring") if @agents.size < 2

      agents_array = @agents.values
      agents_array.each_with_index do |agent, i|
        next_agent = agents_array[(i + 1) % agents_array.size]
        agent.connect_to_peer(next_agent.host, next_agent.port)
      end

      new_efficiency = calculate_network_efficiency
      improvement = new_efficiency - original_efficiency

      TopologyOptimizationResult.new(
        improvement > 0.01,
        original_efficiency,
        new_efficiency,
        "Ring topology optimization completed"
      )
    end

    private def find_available_port(start_port : Int32) : Int32
      (start_port..start_port + 1000).each do |port|
        begin
          server = TCPServer.new(@network_config.discovery_host, port)
          server.close
          return port
        rescue
          # Port in use, try next
        end
      end

      Random.rand(30000..40000)
    end

    enum AgentSelection
      All
      ActiveOnly
      HighTrust
      RandomSample
    end

    enum PropagationStrategy
      Flood
      Selective
      Consensus
      Gossip
      Targeted
    end
  end

  # Network status information
  struct NetworkStatus
    property network_name : String
    property agent_count : Int32
    property active_agents : Int32
    property running : Bool
    property connectivity : Float64
    property average_trust : Float64
    property agents : Hash(String, Hash(String, JSON::Any))
    property config : AgentNetwork::NetworkConfig
    property timestamp : Time

    def initialize(@network_name : String, @agent_count : Int32, @active_agents : Int32, @running : Bool,
                   @connectivity : Float64, @average_trust : Float64,
                   @agents : Hash(String, Hash(String, JSON::Any)),
                   @config : AgentNetwork::NetworkConfig)
      @timestamp = Time.utc
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "network_name", @network_name
        json.field "agent_count", @agent_count
        json.field "active_agents", @active_agents
        json.field "running", @running
        json.field "connectivity", @connectivity
        json.field "average_trust", @average_trust
        json.field "timestamp", @timestamp.to_rfc3339
        json.field "agents", @agents
        json.field "config" do
          json.object do
            json.field "topology", @config.network_topology
            json.field "consensus_protocol", @config.consensus_protocol
            json.field "max_agents", @config.max_agents
            json.field "heartbeat_interval", @config.heartbeat_interval
            json.field "trust_threshold", @config.trust_threshold
          end
        end
      end
    end
  end

  # Collaborative reasoning result
  struct CollaborativeReasoningResult
    property query : String
    property results : Array(CollaborativeResult)
    property consensus_confidence : Float64
    property total_time_ms : Float64
    property timestamp : Time

    def initialize(@query : String, @results : Array(CollaborativeResult),
                   @consensus_confidence : Float64, @total_time_ms : Float64 = 0.0)
      @timestamp = Time.utc
    end

    def best_result : CollaborativeResult?
      @results.max_by?(&.confidence)
    end

    def average_confidence : Float64
      return 0.0 if @results.empty?
      @results.sum(&.confidence) / @results.size
    end
  end

  # Distributed task definition
  struct DistributedTask
    property id : String
    property name : String
    property description : String
    property required_capabilities : Array(String)
    property priority : Int32
    property max_agents : Int32
    property timeout_seconds : Int32
    property payload : Hash(String, JSON::Any)

    def initialize(@name : String, @description : String,
                   @required_capabilities : Array(String) = [] of String,
                   @priority : Int32 = 5, @max_agents : Int32 = -1,
                   @timeout_seconds : Int32 = 300)
      @id = UUID.random.to_s
      @payload = Hash(String, JSON::Any).new
    end
  end

  # Task execution result
  struct TaskExecutionResult
    property task_id : String
    property success : Bool
    property participating_agents : Array(String)
    property execution_time_ms : Float64
    property results : Hash(String, JSON::Any)
    property errors : Array(String)

    def initialize(@task_id : String, @success : Bool, @participating_agents : Array(String),
                   @execution_time_ms : Float64, @results : Hash(String, JSON::Any) = Hash(String, JSON::Any).new)
      @errors = [] of String
    end
  end

  # Topology optimization result
  struct TopologyOptimizationResult
    property improved : Bool
    property original_efficiency : Float64
    property new_efficiency : Float64
    property description : String

    def initialize(@improved : Bool, @original_efficiency : Float64,
                   @new_efficiency : Float64, @description : String)
    end

    def improvement_percentage : Float64
      return 0.0 if @original_efficiency == 0.0
      ((@new_efficiency - @original_efficiency) / @original_efficiency) * 100.0
    end
  end
end
