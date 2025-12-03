# Crystal spec for Distributed Cognitive Agent Networks
require "spec"
require "../../src/agent-zero/distributed_agents"
require "../../src/agent-zero/agent_network"
require "../../src/agent-zero/network_services"

describe AgentZero::AgentNode do
  describe "#initialize" do
    it "creates agent with default configuration" do
      agent = AgentZero::AgentNode.new("TestAgent")

      agent.name.should eq("TestAgent")
      agent.host.should eq("localhost")
      agent.status.should eq(AgentZero::AgentNode::AgentStatus::Initializing)
      agent.capabilities.should contain("reasoning")
      agent.capabilities.should contain("learning")
      agent.trust_level.should eq(1.0)
      agent.id.should_not be_empty
    end

    it "creates agent with custom configuration" do
      agent = AgentZero::AgentNode.new("CustomAgent", "192.168.1.100", 25000)

      agent.name.should eq("CustomAgent")
      agent.host.should eq("192.168.1.100")
      agent.port.should eq(25000)
    end
  end

  describe "#start and #stop" do
    it "starts and stops agent properly" do
      agent = AgentZero::AgentNode.new("TestAgent", port: 0)

      agent.start
      sleep 0.1  # Allow server to start

      agent.status.should eq(AgentZero::AgentNode::AgentStatus::Active)

      agent.stop
      sleep 0.1  # Allow server to stop

      agent.status.should eq(AgentZero::AgentNode::AgentStatus::Offline)
    end
  end

  describe "#connect_to_peer" do
    it "handles connection attempts gracefully" do
      agent1 = AgentZero::AgentNode.new("Agent1", port: 0)
      agent2 = AgentZero::AgentNode.new("Agent2", port: 0)

      agent1.start
      agent2.start
      sleep 0.1

      # Test connection between agents
      result = agent1.connect_to_peer(agent2.host, agent2.port)

      # Should handle the connection attempt (may succeed or fail gracefully)
      result.should be_a(Bool)

      agent1.stop
      agent2.stop
    end
  end

  describe "#request_collaborative_reasoning" do
    it "handles reasoning requests with timeout" do
      agent = AgentZero::AgentNode.new("ReasoningAgent", port: 0)
      agent.start
      sleep 0.1

      results = agent.request_collaborative_reasoning("What is consciousness?", 1)

      results.should be_a(Array(AgentZero::CollaborativeResult))
      # With no peers, should return empty results quickly
      results.size.should eq(0)

      agent.stop
    end
  end

  describe "#share_knowledge" do
    it "broadcasts knowledge to network" do
      agent = AgentZero::AgentNode.new("KnowledgeAgent", port: 0)
      agent.start
      sleep 0.1

      knowledge = AgentZero::KnowledgeItem.new(
        "test-knowledge-1",
        "concept",
        "The sky is blue",
        0.9,
        "test_source"
      )

      shares = agent.share_knowledge(knowledge)

      shares.should be_a(Int32)
      # With no peers, should return 0
      shares.should eq(0)

      agent.stop
    end
  end

  describe "#network_status" do
    it "returns comprehensive network status" do
      agent = AgentZero::AgentNode.new("StatusAgent", port: 0)
      agent.start
      sleep 0.1

      status = agent.network_status

      status.should be_a(Hash(String, JSON::Any))
      status["agent_id"].as_s.should eq(agent.id)
      status["agent_name"].as_s.should eq(agent.name)
      status["status"].as_s.should eq("Active")
      status["peer_count"].as_i64.should eq(0)
      status["capabilities"].as_a.size.should be > 0

      agent.stop
    end
  end
end

describe AgentZero::AgentNetwork do
  describe "#initialize" do
    it "creates network with default configuration" do
      network = AgentZero::AgentNetwork.new("TestNetwork")

      network.name.should eq("TestNetwork")
      network.agents.size.should eq(0)
      network.network_config.network_topology.should eq("mesh")
      network.network_config.consensus_protocol.should eq("raft")
    end

    it "creates network with custom configuration" do
      config = AgentZero::AgentNetwork::NetworkConfig.new
      config.network_topology = "star"
      config.max_agents = 50

      network = AgentZero::AgentNetwork.new("CustomNetwork", config)

      network.network_config.network_topology.should eq("star")
      network.network_config.max_agents.should eq(50)
    end
  end

  describe "#add_agent and #remove_agent" do
    it "manages agents in the network" do
      network = AgentZero::AgentNetwork.new("ManagementNetwork")
      agent = AgentZero::AgentNode.new("ManagedAgent", port: 0)

      # Add agent
      result = network.add_agent(agent)
      result.should be_true
      network.agents.size.should eq(1)
      network.agents.has_key?(agent.id).should be_true

      # Remove agent
      removal_result = network.remove_agent(agent.id)
      removal_result.should be_true
      network.agents.size.should eq(0)
    end

    it "respects max_agents limit" do
      config = AgentZero::AgentNetwork::NetworkConfig.new
      config.max_agents = 1

      network = AgentZero::AgentNetwork.new("LimitedNetwork", config)

      agent1 = AgentZero::AgentNode.new("Agent1", port: 0)
      agent2 = AgentZero::AgentNode.new("Agent2", port: 0)

      network.add_agent(agent1).should be_true
      network.add_agent(agent2).should be_false  # Should fail due to limit

      network.agents.size.should eq(1)
    end
  end

  describe "#create_agent" do
    it "creates and adds new agent to network" do
      network = AgentZero::AgentNetwork.new("CreationNetwork")

      agent = network.create_agent("CreatedAgent", ["reasoning", "memory"])

      agent.should_not be_nil
      if agent
        agent.name.should eq("CreatedAgent")
        agent.capabilities.should contain("reasoning")
        agent.capabilities.should contain("memory")
        network.agents.size.should eq(1)

        # Clean up
        agent.stop
      end
    end

    it "returns nil when network is at capacity" do
      config = AgentZero::AgentNetwork::NetworkConfig.new
      config.max_agents = 0

      network = AgentZero::AgentNetwork.new("FullNetwork", config)

      agent = network.create_agent("OverflowAgent")
      agent.should be_nil
      network.agents.size.should eq(0)
    end
  end

  describe "#collaborative_reasoning" do
    it "executes collaborative reasoning with available agents" do
      network = AgentZero::AgentNetwork.new("ReasoningNetwork")

      agent1 = network.create_agent("ReasoningAgent1")
      agent2 = network.create_agent("ReasoningAgent2")

      if agent1 && agent2
        sleep 0.1  # Allow agents to start

        result = network.collaborative_reasoning(
          "What is artificial intelligence?",
          AgentZero::AgentNetwork::AgentSelection::All,
          5  # 5 second timeout
        )

        result.should be_a(AgentZero::CollaborativeReasoningResult)
        result.query.should eq("What is artificial intelligence?")
        result.results.should be_a(Array(AgentZero::CollaborativeResult))

        # Clean up
        agent1.stop
        agent2.stop
      end
    end

    it "handles empty network gracefully" do
      network = AgentZero::AgentNetwork.new("EmptyNetwork")

      result = network.collaborative_reasoning("Test query")

      result.query.should eq("Test query")
      result.results.size.should eq(0)
      result.consensus_confidence.should eq(0.0)
    end
  end

  describe "#distribute_knowledge" do
    it "distributes knowledge using flood strategy" do
      network = AgentZero::AgentNetwork.new("KnowledgeNetwork")

      agent1 = network.create_agent("KnowledgeAgent1")
      agent2 = network.create_agent("KnowledgeAgent2")

      if agent1 && agent2
        sleep 0.1

        knowledge = AgentZero::KnowledgeItem.new(
          "dist-knowledge-1",
          "fact",
          "Distributed systems enable scalability",
          0.9,
          "test_source"
        )

        shares = network.distribute_knowledge(
          knowledge,
          AgentZero::AgentNetwork::PropagationStrategy::Flood
        )

        shares.should be_a(Int32)
        shares.should be >= 0

        # Clean up
        agent1.stop
        agent2.stop
      end
    end
  end

  describe "#network_status" do
    it "provides comprehensive network status" do
      network = AgentZero::AgentNetwork.new("StatusNetwork")

      agent1 = network.create_agent("StatusAgent1")
      agent2 = network.create_agent("StatusAgent2")

      if agent1 && agent2
        sleep 0.1

        status = network.network_status

        status.should be_a(AgentZero::NetworkStatus)
        status.network_name.should eq("StatusNetwork")
        status.agent_count.should eq(2)
        status.agents.size.should eq(2)
        status.connectivity.should be >= 0.0
        status.connectivity.should be <= 1.0

        # Clean up
        agent1.stop
        agent2.stop
      end
    end
  end
end

describe AgentZero::DiscoveryServer do
  describe "#initialize and basic operations" do
    it "initializes discovery server correctly" do
      server = AgentZero::DiscoveryServer.new("localhost", 19500)

      server.host.should eq("localhost")
      server.port.should eq(19500)
    end

    it "registers and unregisters agents" do
      server = AgentZero::DiscoveryServer.new("localhost", 19501)
      agent = AgentZero::AgentNode.new("DiscoveryTestAgent", port: 0)

      # Register agent
      result = server.register_agent(agent)
      result.should be_true

      # Get agent info
      info = server.get_agent_info(agent.id)
      info.should_not be_nil
      if info
        info.agent_id.should eq(agent.id)
        info.name.should eq(agent.name)
      end

      # Unregister agent
      unregister_result = server.unregister_agent(agent.id)
      unregister_result.should be_true

      # Verify agent is removed
      removed_info = server.get_agent_info(agent.id)
      removed_info.should be_nil
    end

    it "lists active agents" do
      server = AgentZero::DiscoveryServer.new("localhost", 19502)

      agent1 = AgentZero::AgentNode.new("ListAgent1", port: 0)
      agent2 = AgentZero::AgentNode.new("ListAgent2", port: 0)

      server.register_agent(agent1)
      server.register_agent(agent2)

      active_agents = server.list_agents
      active_agents.size.should eq(2)

      agent_names = active_agents.map(&.name)
      agent_names.should contain("ListAgent1")
      agent_names.should contain("ListAgent2")
    end
  end
end

describe AgentZero::ConsensusManager do
  describe "#initialize and consensus operations" do
    it "initializes consensus manager" do
      agents = [
        AgentZero::AgentNode.new("ConsensusAgent1", port: 0),
        AgentZero::AgentNode.new("ConsensusAgent2", port: 0)
      ]

      manager = AgentZero::ConsensusManager.new("raft", agents)

      manager.protocol.should eq("raft")
      manager.participants.size.should eq(2)
    end

    it "handles consensus proposals and voting" do
      agents = [
        AgentZero::AgentNode.new("VoteAgent1", port: 0),
        AgentZero::AgentNode.new("VoteAgent2", port: 0)
      ]

      manager = AgentZero::ConsensusManager.new("simple", agents)
      manager.start

      # Create a proposal
      proposal = JSON::Any.new({"action" => JSON::Any.new("test_action")})
      consensus_id = manager.propose_consensus(proposal, 5)

      consensus_id.should_not be_empty

      # Cast votes
      vote1_result = manager.vote(
        consensus_id,
        agents[0].id,
        AgentZero::ConsensusManager::VoteDecision::Approve,
        "I approve this action"
      )
      vote1_result.should be_true

      vote2_result = manager.vote(
        consensus_id,
        agents[1].id,
        AgentZero::ConsensusManager::VoteDecision::Approve,
        "Looks good to me"
      )
      vote2_result.should be_true

      # Check consensus result
      sleep 0.1  # Allow consensus calculation
      result = manager.get_consensus_result(consensus_id)

      # With 2 approve votes, should be approved
      result.should eq(AgentZero::ConsensusManager::ConsensusStatus::Approved)

      manager.stop
    end
  end
end

describe AgentZero::TaskCoordinator do
  describe "#initialize and task execution" do
    it "initializes task coordinator" do
      config = AgentZero::AgentNetwork::NetworkConfig.new
      coordinator = AgentZero::TaskCoordinator.new(config)

      coordinator.config.should eq(config)
    end

    it "executes collaborative reasoning tasks" do
      config = AgentZero::AgentNetwork::NetworkConfig.new
      coordinator = AgentZero::TaskCoordinator.new(config)

      agents = [
        AgentZero::AgentNode.new("TaskAgent1", port: 0),
        AgentZero::AgentNode.new("TaskAgent2", port: 0)
      ]

      agents.each(&.start)
      sleep 0.1

      task = AgentZero::DistributedTask.new(
        "collaborative_reasoning",
        "Test reasoning task",
        ["reasoning"]
      )
      task.payload["query"] = JSON::Any.new("What is machine learning?")

      result = coordinator.execute_task(task, agents)

      result.should be_a(AgentZero::TaskExecutionResult)
      result.task_id.should eq(task.id)
      result.participating_agents.size.should be > 0
      result.execution_time_ms.should be > 0

      agents.each(&.stop)
    end

    it "executes knowledge sharing tasks" do
      config = AgentZero::AgentNetwork::NetworkConfig.new
      coordinator = AgentZero::TaskCoordinator.new(config)

      agents = [
        AgentZero::AgentNode.new("ShareAgent1", port: 0),
        AgentZero::AgentNode.new("ShareAgent2", port: 0)
      ]

      agents.each(&.start)
      sleep 0.1

      task = AgentZero::DistributedTask.new(
        "knowledge_sharing",
        "Test knowledge sharing task",
        ["memory", "learning"]
      )
      task.payload["knowledge"] = JSON::Any.new("Neural networks learn through backpropagation")

      result = coordinator.execute_task(task, agents)

      result.success.should be_true
      result.results.keys.should contain("knowledge_id")
      result.results.keys.should contain("successful_shares")

      agents.each(&.stop)
    end

    it "handles tasks with no suitable agents" do
      config = AgentZero::AgentNetwork::NetworkConfig.new
      coordinator = AgentZero::TaskCoordinator.new(config)

      # Create agents without required capabilities
      agents = [
        AgentZero::AgentNode.new("UnspecializedAgent", port: 0)
      ]
      agents[0].capabilities = ["basic"]  # Different from task requirements

      task = AgentZero::DistributedTask.new(
        "specialized_task",
        "Task requiring specific capabilities",
        ["advanced_reasoning", "quantum_computing"]  # Capabilities not available
      )

      result = coordinator.execute_task(task, agents)

      result.success.should be_false
      result.participating_agents.size.should eq(0)
      result.errors.should_not be_empty
    end
  end
end

# Integration tests
describe "Distributed Agent Network Integration" do
  it "creates a functioning multi-agent network" do
    # Create network
    network = AgentZero::AgentNetwork.new("IntegrationTestNetwork")
    network.start
    sleep 0.1

    # Create multiple agents
    agent1 = network.create_agent("IntegrationAgent1", ["reasoning", "learning"])
    agent2 = network.create_agent("IntegrationAgent2", ["memory", "attention"])
    agent3 = network.create_agent("IntegrationAgent3", ["reasoning", "memory"])

    if agent1 && agent2 && agent3
      sleep 0.2  # Allow agents to start and discover each other

      # Test network status
      status = network.network_status
      status.agent_count.should eq(3)
      status.running.should be_true

      # Test collaborative reasoning
      reasoning_result = network.collaborative_reasoning(
        "How does distributed cognition work?",
        AgentZero::AgentNetwork::AgentSelection::All,
        10
      )

      reasoning_result.query.should contain("distributed cognition")

      # Test knowledge distribution
      knowledge = AgentZero::KnowledgeItem.new(
        "integration-test-knowledge",
        "concept",
        "Distributed cognition emerges from agent interactions",
        0.95,
        "integration_test"
      )

      shares = network.distribute_knowledge(knowledge)
      shares.should be >= 0

      # Test distributed task execution
      task = AgentZero::DistributedTask.new(
        "network_optimization",
        "Optimize the network topology",
        ["reasoning"]
      )

      task_result = network.execute_distributed_task(task)
      task_result.success.should be_true
      task_result.participating_agents.size.should be > 0

      # Clean up
      agent1.stop
      agent2.stop
      agent3.stop
    end

    network.stop
  end

  it "handles network failures gracefully" do
    network = AgentZero::AgentNetwork.new("FailureTestNetwork")

    # Test operations on empty network
    reasoning_result = network.collaborative_reasoning("Test query")
    reasoning_result.results.size.should eq(0)

    knowledge = AgentZero::KnowledgeItem.new("test", "fact", "Test fact", 0.8, "test")
    shares = network.distribute_knowledge(knowledge)
    shares.should eq(0)

    # Test with agents that stop unexpectedly
    agent = network.create_agent("UnstableAgent")
    if agent
      agent.stop  # Stop immediately

      # Network should handle this gracefully
      status = network.network_status
      status.agent_count.should eq(1)  # Still counted but not active
    end
  end
end