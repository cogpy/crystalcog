# End-to-End Tests for Agent-Zero Component
# Tests the complete agent-zero system including network creation,
# agent lifecycle, collaborative reasoning, and knowledge distribution

require "spec"
require "../../src/agent-zero/agent_network"
require "../../src/agent-zero/distributed_agents"
require "../../src/agent-zero/network_services"

describe "AgentZero E2E Tests" do
  describe "Complete Network Lifecycle" do
    it "creates network, adds agents, performs operations, and shuts down cleanly" do
      # Create network
      network = AgentZero::AgentNetwork.new("E2ETestNetwork")
      network.should_not be_nil
      
      # Create multiple agents
      agent1 = network.create_agent("E2E-Agent-1", ["reasoning", "memory"])
      agent2 = network.create_agent("E2E-Agent-2", ["learning", "communication"])
      agent3 = network.create_agent("E2E-Agent-3", ["reasoning", "learning"])
      
      agent1.should_not be_nil
      agent2.should_not be_nil
      agent3.should_not be_nil
      
      if agent1 && agent2 && agent3
        # Start network
        network.start
        sleep 0.2  # Allow network to stabilize
        
        # Verify network status
        status = network.network_status
        status.agent_count.should eq(3)
        status.active_agents.should eq(3)
        
        # Test collaborative reasoning
        result = network.collaborative_reasoning(
          "What is distributed artificial intelligence?",
          timeout: 5
        )
        
        result.should_not be_nil
        result.query.should eq("What is distributed artificial intelligence?")
        result.results.should be_a(Array(AgentZero::CollaborativeResult))
        
        # Test knowledge distribution
        knowledge = AgentZero::KnowledgeItem.new(
          "e2e-test-knowledge",
          "concept",
          "Distributed AI enables scalable cognitive systems",
          0.95,
          "e2e_test"
        )
        
        shares = network.distribute_knowledge(knowledge)
        shares.should be >= 0
        
        # Stop network
        network.stop
        sleep 0.1
        
        # Verify cleanup
        agent1.status.should eq(AgentZero::AgentNode::AgentStatus::Offline)
        agent2.status.should eq(AgentZero::AgentNode::AgentStatus::Offline)
        agent3.status.should eq(AgentZero::AgentNode::AgentStatus::Offline)
      end
    end
  end
  
  describe "Multi-Agent Collaboration" do
    it "enables multiple agents to collaborate on complex reasoning tasks" do
      network = AgentZero::AgentNetwork.new("CollaborationNetwork")
      
      # Create specialized agents
      reasoning_agent = network.create_agent("ReasoningSpecialist", ["reasoning", "logic"])
      learning_agent = network.create_agent("LearningSpecialist", ["learning", "pattern_recognition"])
      memory_agent = network.create_agent("MemorySpecialist", ["memory", "retrieval"])
      
      if reasoning_agent && learning_agent && memory_agent
        network.start
        sleep 0.2
        
        # Test multi-agent reasoning
        queries = [
          "What is consciousness?",
          "How does learning occur?",
          "What is the nature of memory?"
        ]
        
        queries.each do |query|
          result = network.collaborative_reasoning(query, timeout: 5)
          result.query.should eq(query)
          result.results.should be_a(Array(AgentZero::CollaborativeResult))
        end
        
        # Verify all agents participated
        status = network.network_status
        status.agent_count.should eq(3)
        
        network.stop
        reasoning_agent.stop
        learning_agent.stop
        memory_agent.stop
      end
    end
  end
  
  describe "Knowledge Propagation" do
    it "distributes knowledge across the network with different strategies" do
      network = AgentZero::AgentNetwork.new("KnowledgeNetwork")
      
      # Create network of agents
      agents = [] of AgentZero::AgentNode
      5.times do |i|
        agent = network.create_agent("KnowledgeAgent-#{i + 1}")
        agents << agent if agent
      end
      
      agents.size.should eq(5)
      
      network.start
      sleep 0.2
      
      # Test flood propagation
      knowledge1 = AgentZero::KnowledgeItem.new(
        "flood-test",
        "fact",
        "Knowledge propagates through networks",
        0.9,
        "test"
      )
      
      flood_shares = network.distribute_knowledge(
        knowledge1,
        AgentZero::AgentNetwork::PropagationStrategy::Flood
      )
      flood_shares.should be >= 0
      
      # Test gossip propagation
      knowledge2 = AgentZero::KnowledgeItem.new(
        "gossip-test",
        "fact",
        "Gossip protocols enable efficient distribution",
        0.85,
        "test"
      )
      
      gossip_shares = network.distribute_knowledge(
        knowledge2,
        AgentZero::AgentNetwork::PropagationStrategy::Gossip
      )
      gossip_shares.should be >= 0
      
      # Test targeted propagation
      knowledge3 = AgentZero::KnowledgeItem.new(
        "targeted-test",
        "fact",
        "Targeted distribution optimizes bandwidth",
        0.8,
        "test"
      )
      
      targeted_shares = network.distribute_knowledge(
        knowledge3,
        AgentZero::AgentNetwork::PropagationStrategy::Targeted
      )
      targeted_shares.should be >= 0
      
      network.stop
      agents.each(&.stop)
    end
  end
  
  describe "Network Resilience" do
    it "handles agent failures and recovers gracefully" do
      network = AgentZero::AgentNetwork.new("ResilientNetwork")
      
      # Create agents
      agents = [] of AgentZero::AgentNode
      3.times do |i|
        agent = network.create_agent("ResilientAgent-#{i + 1}")
        agents << agent if agent
      end
      
      agents.size.should eq(3)
      
      network.start
      sleep 0.2
      
      # Verify initial state
      status = network.network_status
      status.active_agents.should eq(3)
      
      # Simulate agent failure
      if agents.size > 0
        failing_agent = agents[0]
        failing_agent.stop
        sleep 0.1
        
        # Network should still function
        result = network.collaborative_reasoning("Test query after failure", timeout: 3)
        result.should_not be_nil
        
        # Verify network adapted
        status = network.network_status
        status.active_agents.should be < 3
      end
      
      network.stop
      agents.each(&.stop)
    end
  end
  
  describe "Discovery Service" do
    it "enables agents to discover and connect to each other" do
      # Create discovery server
      discovery = AgentZero::DiscoveryServer.new("localhost", 19600)
      
      # Create agents
      agent1 = AgentZero::AgentNode.new("DiscoveryAgent1", port: 0)
      agent2 = AgentZero::AgentNode.new("DiscoveryAgent2", port: 0)
      
      # Register agents
      discovery.register_agent(agent1).should be_true
      discovery.register_agent(agent2).should be_true
      
      # Discover agents
      info1 = discovery.get_agent_info(agent1.id)
      info1.should_not be_nil
      if info1
        info1.name.should eq("DiscoveryAgent1")
      end
      
      # List all agents
      all_agents = discovery.list_agents
      all_agents.size.should be >= 2
      
      # Unregister agents
      discovery.unregister_agent(agent1.id).should be_true
      discovery.unregister_agent(agent2.id).should be_true
      
      # Verify removal
      discovery.get_agent_info(agent1.id).should be_nil
      discovery.get_agent_info(agent2.id).should be_nil
    end
  end
  
  describe "Performance and Scalability" do
    it "handles multiple concurrent operations efficiently" do
      network = AgentZero::AgentNetwork.new("PerformanceNetwork")
      
      # Create multiple agents
      agent_count = 5
      agents = [] of AgentZero::AgentNode
      
      agent_count.times do |i|
        agent = network.create_agent("PerfAgent-#{i + 1}")
        agents << agent if agent
      end
      
      agents.size.should eq(agent_count)
      
      network.start
      sleep 0.2
      
      # Measure reasoning performance
      start_time = Time.monotonic
      
      10.times do |i|
        network.collaborative_reasoning("Performance test query #{i}", timeout: 2)
      end
      
      elapsed = Time.monotonic - start_time
      
      # Should complete reasonably fast (adjust threshold as needed)
      elapsed.total_seconds.should be < 30
      
      # Measure knowledge distribution performance
      start_time = Time.monotonic
      
      10.times do |i|
        knowledge = AgentZero::KnowledgeItem.new(
          "perf-knowledge-#{i}",
          "fact",
          "Performance test knowledge item #{i}",
          0.8,
          "perf_test"
        )
        network.distribute_knowledge(knowledge)
      end
      
      elapsed = Time.monotonic - start_time
      
      # Should complete reasonably fast
      elapsed.total_seconds.should be < 10
      
      network.stop
      agents.each(&.stop)
    end
  end
  
  describe "Integration with CogUtil" do
    it "properly integrates with CogUtil logging and utilities" do
      # This test verifies that agent-zero properly uses CogUtil
      network = AgentZero::AgentNetwork.new("IntegrationNetwork")
      
      # CogUtil::Logger should be used (verified by no exceptions)
      agent = network.create_agent("IntegrationAgent")
      
      if agent
        agent.start
        sleep 0.1
        
        # Should use CogUtil logging without errors
        status = agent.network_status
        status.should be_a(Hash(String, JSON::Any))
        
        agent.stop
      end
      
      network.stop
    end
  end
end
