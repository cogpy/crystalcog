# Crystal implementation of Network Services for Distributed Cognitive Agents
# Supporting services for agent discovery, consensus, and task coordination

require "socket"
require "json"
require "uuid"
require "./distributed_agents"
require "../cogutil/cogutil"

module AgentZero
  # Service for agent discovery and registration
  class DiscoveryServer
    property host : String
    property port : Int32

    @registered_agents : Hash(String, AgentRegistration)
    @server : TCPServer?
    @running : Bool = false

    class AgentRegistration
      property agent_id : String
      property name : String
      property host : String
      property port : Int32
      property capabilities : Array(String)
      property trust_level : Float64
      property registered_at : Time
      property last_heartbeat : Time

      def initialize(@agent_id : String, @name : String, @host : String, @port : Int32,
                     @capabilities : Array(String) = [] of String, @trust_level : Float64 = 0.5)
        @registered_at = Time.utc
        @last_heartbeat = Time.utc
      end

      def update_heartbeat
        @last_heartbeat = Time.utc
      end

      def is_alive?(timeout_minutes : Int32 = 2) : Bool
        (Time.utc - @last_heartbeat).total_minutes < timeout_minutes
      end
    end

    def initialize(@host : String, @port : Int32)
      @registered_agents = Hash(String, AgentRegistration).new
      CogUtil::Logger.info("DiscoveryServer initialized on #{@host}:#{@port}")
    end

    def start
      return if @running

      @running = true

      spawn do
        start_server
      end

      spawn do
        cleanup_loop
      end

      CogUtil::Logger.info("DiscoveryServer started")
    end

    def stop
      return unless @running

      @running = false
      @server.try(&.close)

      CogUtil::Logger.info("DiscoveryServer stopped")
    end

    def register_agent(agent : AgentNode) : Bool
      registration = AgentRegistration.new(
        agent.id,
        agent.name,
        agent.host,
        agent.port,
        agent.capabilities,
        agent.trust_level
      )

      @registered_agents[agent.id] = registration
      CogUtil::Logger.info("Registered agent: #{agent.name} (#{agent.id})")
      true
    end

    def unregister_agent(agent_id : String) : Bool
      removed = @registered_agents.delete(agent_id)
      if removed
        CogUtil::Logger.info("Unregistered agent: #{removed.name} (#{agent_id})")
        true
      else
        false
      end
    end

    def discover_agents(timeout_seconds : Int32 = 10) : Array(AgentNode)
      # Return list of active registered agents as discovery results
      active_agents = [] of AgentNode

      @registered_agents.each_value do |reg|
        next unless reg.is_alive?

        # Create AgentNode representation for discovery
        agent = AgentNode.new(reg.name, reg.host, reg.port)
        agent.capabilities = reg.capabilities
        agent.trust_level = reg.trust_level
        active_agents << agent
      end

      CogUtil::Logger.info("Discovered #{active_agents.size} active agents")
      active_agents
    end

    def get_agent_info(agent_id : String) : AgentRegistration?
      @registered_agents[agent_id]?
    end

    def list_agents : Array(AgentRegistration)
      @registered_agents.values.select(&.is_alive?)
    end

    def stats : Hash(String, Int32 | Float64)
      total_agents = @registered_agents.size
      active_agents = @registered_agents.values.count(&.is_alive?)

      {
        "total_registered" => total_agents,
        "active_agents"    => active_agents,
        "uptime_seconds"   => uptime_seconds.to_i32,
      }
    end

    private def start_server
      @server = TCPServer.new(@host, @port)

      while @running && (server = @server)
        begin
          client = server.accept
          spawn do
            handle_discovery_request(client)
          end
        rescue ex
          break unless @running
          CogUtil::Logger.error("Discovery server error: #{ex.message}")
        end
      end
    rescue ex
      CogUtil::Logger.error("Discovery server startup error: #{ex.message}")
    end

    private def handle_discovery_request(client : TCPSocket)
      begin
        request_data = client.gets
        return unless request_data

        request = JSON.parse(request_data)
        command = request["command"].as_s

        case command
        when "register"
          handle_register_request(request, client)
        when "discover"
          handle_discover_request(request, client)
        when "heartbeat"
          handle_heartbeat_request(request, client)
        when "unregister"
          handle_unregister_request(request, client)
        else
          send_error_response(client, "Unknown command: #{command}")
        end
      rescue ex
        send_error_response(client, "Request processing error: #{ex.message}")
      ensure
        client.close
      end
    end

    private def handle_register_request(request : JSON::Any, client : TCPSocket)
      agent_data = request["agent"]

      registration = AgentRegistration.new(
        agent_data["id"].as_s,
        agent_data["name"].as_s,
        agent_data["host"].as_s,
        agent_data["port"].as_i,
        agent_data["capabilities"].as_a.map(&.as_s),
        agent_data["trust_level"].as_f
      )

      @registered_agents[registration.agent_id] = registration

      response = {
        "status"   => "success",
        "message"  => "Agent registered successfully",
        "agent_id" => registration.agent_id,
      }

      client.puts(response.to_json)
    end

    private def handle_discover_request(request : JSON::Any, client : TCPSocket)
      active_agents = list_agents.map do |reg|
        {
          "id"           => reg.agent_id,
          "name"         => reg.name,
          "host"         => reg.host,
          "port"         => reg.port,
          "capabilities" => reg.capabilities,
          "trust_level"  => reg.trust_level,
        }
      end

      response = {
        "status" => "success",
        "agents" => active_agents,
      }

      client.puts(response.to_json)
    end

    private def handle_heartbeat_request(request : JSON::Any, client : TCPSocket)
      agent_id = request["agent_id"].as_s

      if registration = @registered_agents[agent_id]?
        registration.update_heartbeat

        response = {
          "status"  => "success",
          "message" => "Heartbeat updated",
        }
      else
        response = {
          "status"  => "error",
          "message" => "Agent not registered",
        }
      end

      client.puts(response.to_json)
    end

    private def handle_unregister_request(request : JSON::Any, client : TCPSocket)
      agent_id = request["agent_id"].as_s

      if unregister_agent(agent_id)
        response = {
          "status"  => "success",
          "message" => "Agent unregistered successfully",
        }
      else
        response = {
          "status"  => "error",
          "message" => "Agent not found",
        }
      end

      client.puts(response.to_json)
    end

    private def send_error_response(client : TCPSocket, message : String)
      response = {
        "status"  => "error",
        "message" => message,
      }
      client.puts(response.to_json)
    end

    private def cleanup_loop
      cleanup_interval = 60.seconds
      check_interval = 0.1.seconds
      elapsed = Time::Span.zero

      while @running
        # Check running status frequently, but only cleanup at the configured interval
        if elapsed >= cleanup_interval
          # Remove stale agent registrations
          @registered_agents.reject! do |id, reg|
            if !reg.is_alive?
              CogUtil::Logger.debug("Removing stale agent registration: #{reg.name}")
              true
            else
              false
            end
          end

          elapsed = Time::Span.zero
        end

        sleep check_interval
        elapsed += check_interval
      end
    end

    getter :started_at
    @started_at : Time = Time.utc

    private def uptime_seconds : Float64
      (Time.utc - @started_at).total_seconds
    end
  end

  # Consensus management for distributed decisions
  class ConsensusManager
    property protocol : String
    property participants : Array(AgentNode)

    @running : Bool = false
    @consensus_state : Hash(String, ConsensusItem)

    class ConsensusItem
      property id : String
      property proposal : JSON::Any
      property votes : Hash(String, Vote)
      property status : ConsensusStatus
      property created_at : Time
      property timeout_at : Time

      def initialize(@id : String, @proposal : JSON::Any, timeout_seconds : Int32 = 30)
        @votes = Hash(String, Vote).new
        @status = ConsensusStatus::Pending
        @created_at = Time.utc
        @timeout_at = Time.utc + timeout_seconds.seconds
      end

      def add_vote(agent_id : String, decision : VoteDecision, justification : String = "")
        @votes[agent_id] = Vote.new(agent_id, decision, justification)
      end

      def calculate_result : ConsensusStatus
        return ConsensusStatus::Timeout if Time.utc > @timeout_at

        approve_votes = @votes.values.count { |v| v.decision.approve? }
        reject_votes = @votes.values.count { |v| v.decision.reject? }
        total_votes = @votes.size

        # Simple majority consensus
        if approve_votes > total_votes / 2
          ConsensusStatus::Approved
        elsif reject_votes > total_votes / 2
          ConsensusStatus::Rejected
        else
          ConsensusStatus::Pending
        end
      end
    end

    struct Vote
      property agent_id : String
      property decision : VoteDecision
      property justification : String
      property timestamp : Time

      def initialize(@agent_id : String, @decision : VoteDecision, @justification : String = "")
        @timestamp = Time.utc
      end
    end

    enum ConsensusStatus
      Pending
      Approved
      Rejected
      Timeout
    end

    enum VoteDecision
      Approve
      Reject
      Abstain
    end

    def initialize(@protocol : String, @participants : Array(AgentNode))
      @consensus_state = Hash(String, ConsensusItem).new
      CogUtil::Logger.info("ConsensusManager initialized with #{@protocol} protocol, #{@participants.size} participants")
    end

    def start
      return if @running

      @running = true

      spawn do
        consensus_loop
      end

      CogUtil::Logger.info("ConsensusManager started")
    end

    def stop
      @running = false
      CogUtil::Logger.info("ConsensusManager stopped")
    end

    def propose_consensus(proposal : JSON::Any, timeout_seconds : Int32 = 30) : String
      consensus_id = UUID.random.to_s
      item = ConsensusItem.new(consensus_id, proposal, timeout_seconds)
      @consensus_state[consensus_id] = item

      # Broadcast proposal to participants
      broadcast_consensus_proposal(item)

      CogUtil::Logger.info("Started consensus #{consensus_id} with #{@participants.size} participants")
      consensus_id
    end

    def vote(consensus_id : String, agent_id : String, decision : VoteDecision, justification : String = "") : Bool
      item = @consensus_state[consensus_id]?
      return false unless item
      return false if item.status != ConsensusStatus::Pending

      item.add_vote(agent_id, decision, justification)
      CogUtil::Logger.debug("Vote recorded: #{agent_id} -> #{decision} for consensus #{consensus_id}")
      true
    end

    def get_consensus_result(consensus_id : String) : ConsensusStatus?
      @consensus_state[consensus_id]?.try(&.calculate_result)
    end

    def select_knowledge_targets(knowledge : KnowledgeItem) : Array(AgentNode)
      # Simple heuristic: select agents with relevant capabilities
      @participants.select do |agent|
        agent.capabilities.any? { |cap| knowledge.content.includes?(cap) } ||
          agent.trust_level > 0.7
      end
    end

    private def consensus_loop
      while @running
        # Update consensus status and handle timeouts
        @consensus_state.each do |id, item|
          if item.status == ConsensusStatus::Pending
            new_status = item.calculate_result
            if new_status != ConsensusStatus::Pending
              item.status = new_status
              CogUtil::Logger.info("Consensus #{id} completed: #{new_status}")
            end
          end
        end

        # Clean up old consensus items
        @consensus_state.reject! do |id, item|
          if Time.utc > item.timeout_at + 5.minutes
            CogUtil::Logger.debug("Cleaning up old consensus: #{id}")
            true
          else
            false
          end
        end

        sleep 1.second
      end
    end

    private def broadcast_consensus_proposal(item : ConsensusItem)
      proposal_message = Message.new("consensus_proposal", "consensus_manager", {
        "consensus_id" => item.id,
        "proposal"     => item.proposal.to_s,
        "timeout_at"   => item.timeout_at.to_rfc3339,
      })

      @participants.each do |participant|
        # Send proposal message to each participant
        # This is simplified - would use proper message routing in production
        CogUtil::Logger.debug("Sending consensus proposal to #{participant.name}")
      end
    end
  end

  # Task coordination and distribution
  class TaskCoordinator
    property config : AgentNetwork::NetworkConfig

    @active_tasks : Hash(String, TaskExecution)

    struct TaskExecution
      property task : DistributedTask
      property assigned_agents : Array(AgentNode)
      property status : TaskStatus
      property started_at : Time
      property results : Hash(String, JSON::Any)
      property errors : Array(String)

      def initialize(@task : DistributedTask, @assigned_agents : Array(AgentNode))
        @status = TaskStatus::Pending
        @started_at = Time.utc
        @results = Hash(String, JSON::Any).new
        @errors = [] of String
      end

      def is_completed? : Bool
        @status.completed? || @status.failed? || @status.timeout?
      end

      def is_timeout? : Bool
        (Time.utc - @started_at).total_seconds > @task.timeout_seconds
      end
    end

    enum TaskStatus
      Pending
      Running
      Completed
      Failed
      Timeout
    end

    def initialize(@config : AgentNetwork::NetworkConfig)
      @active_tasks = Hash(String, TaskExecution).new
      CogUtil::Logger.info("TaskCoordinator initialized")
    end

    def execute_task(task : DistributedTask, available_agents : Array(AgentNode)) : TaskExecutionResult
      # Select appropriate agents for the task
      selected_agents = select_agents_for_task(task, available_agents)

      if selected_agents.empty?
        return TaskExecutionResult.new(
          task.id,
          false,
          [] of String,
          0.0,
          Hash(String, JSON::Any).new
        ).tap { |r| r.errors << "No suitable agents found for task" }
      end

      execution = TaskExecution.new(task, selected_agents)
      @active_tasks[task.id] = execution

      execution.status = TaskStatus::Running
      start_time = Time.instant

      # Execute task on selected agents
      begin
        case task.name.downcase
        when "collaborative_reasoning"
          execute_reasoning_task(execution)
        when "knowledge_sharing"
          execute_knowledge_sharing_task(execution)
        when "network_optimization"
          execute_network_optimization_task(execution)
        else
          execute_generic_task(execution)
        end

        execution.status = TaskStatus::Completed
      rescue ex
        execution.status = TaskStatus::Failed
        execution.errors << (ex.message || "Unknown error")
        CogUtil::Logger.error("Task execution failed: #{ex.message}")
      end

      execution_time = (Time.instant - start_time).total_milliseconds

      # Create result
      result = TaskExecutionResult.new(
        task.id,
        execution.status.completed?,
        execution.assigned_agents.map(&.id),
        execution_time,
        execution.results
      )
      result.errors = execution.errors

      # Clean up completed task
      @active_tasks.delete(task.id)

      CogUtil::Logger.info("Task #{task.name} completed: success=#{result.success}, agents=#{result.participating_agents.size}")
      result
    end

    private def select_agents_for_task(task : DistributedTask, available_agents : Array(AgentNode)) : Array(AgentNode)
      # Filter agents by required capabilities
      capable_agents = available_agents.select do |agent|
        task.required_capabilities.empty? ||
          task.required_capabilities.any? { |cap| agent.capabilities.includes?(cap) }
      end

      # Sort by trust level and select up to max_agents
      capable_agents.sort_by(&.trust_level).reverse!

      max_count = task.max_agents > 0 ? task.max_agents : capable_agents.size
      capable_agents.first(max_count)
    end

    private def execute_reasoning_task(execution : TaskExecution)
      query = execution.task.payload["query"]?.try(&.as_s) || "default reasoning query"

      # Execute collaborative reasoning
      all_results = [] of CollaborativeResult

      execution.assigned_agents.each do |agent|
        results = agent.request_collaborative_reasoning(query, 30)
        all_results.concat(results)
      end

      # Store results
      execution.results["query"] = JSON::Any.new(query)
      execution.results["result_count"] = JSON::Any.new(all_results.size.to_i64)
      execution.results["average_confidence"] = JSON::Any.new(
        all_results.empty? ? 0.0 : all_results.sum(&.confidence) / all_results.size
      )
    end

    private def execute_knowledge_sharing_task(execution : TaskExecution)
      knowledge_content = execution.task.payload["knowledge"]?.try(&.as_s) || "default knowledge"

      # Create knowledge item and share across agents
      knowledge = KnowledgeItem.new(
        UUID.random.to_s,
        "task_knowledge",
        knowledge_content,
        0.8,
        "task_coordinator"
      )

      successful_shares = 0
      execution.assigned_agents.each do |agent|
        successful_shares += agent.share_knowledge(knowledge)
      end

      execution.results["knowledge_id"] = JSON::Any.new(knowledge.id)
      execution.results["successful_shares"] = JSON::Any.new(successful_shares.to_i64)
      execution.results["total_agents"] = JSON::Any.new(execution.assigned_agents.size.to_i64)
    end

    # Tighten the topology among the assigned agents: while two of them
    # are more than two hops apart (or cannot reach each other at all),
    # connect the farthest pair directly. Efficiency is the network's global
    # efficiency: the mean of 1/distance over all pairs, 1.0 when everyone
    # is one hop from everyone else.
    private def execute_network_optimization_task(execution : TaskExecution)
      agents = execution.assigned_agents
      original_efficiency = TaskCoordinator.global_efficiency(agents)

      links_added = 0
      failed = Set({String, String}).new
      loop do
        distances = TaskCoordinator.hop_distances(agents)
        worst = nil
        worst_distance = 2
        agents.each_with_index do |a, i|
          agents.each_with_index do |b, j|
            next if j <= i || failed.includes?({a.id, b.id})
            distance = distances[i][j] || Int32::MAX
            if distance > worst_distance
              worst = {a, b}
              worst_distance = distance
            end
          end
        end
        pair = worst || break
        if pair[0].connect_to_peer(pair[1].host, pair[1].port, retries: 2)
          links_added += 1
        else
          failed << {pair[0].id, pair[1].id}
        end
      end

      optimized_efficiency = TaskCoordinator.global_efficiency(agents)
      execution.results["original_efficiency"] = JSON::Any.new(original_efficiency)
      execution.results["optimized_efficiency"] = JSON::Any.new(optimized_efficiency)
      execution.results["improvement"] = JSON::Any.new(optimized_efficiency - original_efficiency)
      execution.results["links_added"] = JSON::Any.new(links_added.to_i64)
      execution.results["participating_agents"] = JSON::Any.new(agents.size.to_i64)
    end

    # Hop counts between agents over their peer connections (a connection
    # known to either end counts); nil where there is no path.
    def self.hop_distances(agents : Array(AgentNode)) : Array(Array(Int32?))
      index = agents.each_with_index.to_h { |agent, i| {agent.id, i} }
      adjacent = Array.new(agents.size) { Set(Int32).new }
      agents.each_with_index do |agent, i|
        agent.peer_ids.each do |peer_id|
          j = index[peer_id]? || next
          adjacent[i] << j
          adjacent[j] << i
        end
      end

      agents.each_index.map do |start|
        distances = Array(Int32?).new(agents.size, nil)
        distances[start] = 0
        queue = Deque{start}
        until queue.empty?
          current = queue.shift
          adjacent[current].each do |neighbour|
            next unless distances[neighbour].nil?
            distances[neighbour] = distances[current].not_nil! + 1
            queue << neighbour
          end
        end
        distances
      end.to_a
    end

    # Mean of 1/distance over all ordered pairs of agents; unreachable
    # pairs contribute 0. A single agent, or none, is trivially efficient.
    def self.global_efficiency(agents : Array(AgentNode)) : Float64
      return 1.0 if agents.size < 2
      distances = hop_distances(agents)
      total = 0.0
      agents.size.times do |i|
        agents.size.times do |j|
          next if i == j
          distances[i][j].try { |d| total += 1.0 / d }
        end
      end
      total / (agents.size * (agents.size - 1))
    end

    private def execute_generic_task(execution : TaskExecution)
      # Generic task execution
      execution.results["task_type"] = JSON::Any.new("generic")
      execution.results["agents_used"] = JSON::Any.new(execution.assigned_agents.size.to_i64)
      execution.results["execution_timestamp"] = JSON::Any.new(Time.utc.to_rfc3339)
    end

    def get_active_tasks : Array(TaskExecution)
      @active_tasks.values
    end

    def get_task_status(task_id : String) : TaskStatus?
      @active_tasks[task_id]?.status
    end

    def stop
      @active_tasks.clear
      CogUtil::Logger.info("TaskCoordinator stopped")
    end
  end
end
