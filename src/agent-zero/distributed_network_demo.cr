# Distributed Cognitive Agent Network Demo
# Demonstrates the functionality of the Agent-Zero distributed agent networks

require "./distributed_agents"
require "./agent_network"
require "./network_services"
require "../cogutil/cogutil"

module AgentZero
  class NetworkDemo
    def self.run
      puts "🧠 Agent-Zero Distributed Cognitive Network Demo"
      puts "=" * 50

      # Initialize logging
      CogUtil::Logger.set_level(CogUtil::LogLevel::INFO)

      demo = new
      demo.run_demo
    end

    def run_demo
      puts "\n1. Creating Agent Network..."

      # Create network configuration
      config = AgentNetwork::NetworkConfig.new
      config.network_topology = "mesh"
      config.max_agents = 5
      config.heartbeat_interval = 10
      config.trust_threshold = 0.6

      network = AgentNetwork.new("CognitiveAgentNetwork", config)

      puts "   ✓ Network 'CognitiveAgentNetwork' created with mesh topology"

      # Start the network
      network.start
      puts "   ✓ Network services started"

      puts "\n2. Creating Cognitive Agents..."

      # Create diverse agents with different capabilities
      agents = [] of AgentNode?

      agents << network.create_agent("ReasoningExpert", ["reasoning", "logic", "inference"])
      agents << network.create_agent("LearningSpecialist", ["learning", "adaptation", "pattern_recognition"])
      agents << network.create_agent("MemoryManager", ["memory", "storage", "retrieval"])
      agents << network.create_agent("AttentionController", ["attention", "focus", "prioritization"])
      agents << network.create_agent("GeneralAgent", ["reasoning", "learning", "memory", "attention"])

      active_agents = agents.compact
      puts "   ✓ Created #{active_agents.size} cognitive agents"

      # Display agent information
      active_agents.each do |agent|
        puts "     - #{agent.name}: #{agent.capabilities.join(", ")} (trust: #{agent.trust_level})"
      end

      # Allow agents to discover and connect to each other
      puts "\n3. Agent Discovery and Network Formation..."
      sleep 2.seconds

      # Check network status
      status = network.network_status
      puts "   ✓ Network connectivity: #{(status.connectivity * 100).round(1)}%"
      puts "   ✓ Average trust level: #{status.average_trust.round(3)}"

      puts "\n4. Collaborative Reasoning Demo..."

      # Test collaborative reasoning with multiple queries
      reasoning_queries = [
        "What is the nature of consciousness in artificial intelligence?",
        "How can distributed cognition enhance problem-solving capabilities?",
        "What are the ethical implications of autonomous cognitive agents?",
      ]

      reasoning_queries.each_with_index do |query, i|
        puts "\n   Query #{i + 1}: #{query}"

        result = network.collaborative_reasoning(
          query,
          AgentNetwork::AgentSelection::All,
          15 # 15 second timeout
        )

        puts "   → Results: #{result.results.size} responses"
        puts "   → Consensus confidence: #{(result.consensus_confidence * 100).round(1)}%"
        puts "   → Processing time: #{result.total_time_ms.round(1)}ms"

        if best_result = result.best_result
          puts "   → Best response (confidence #{(best_result.confidence * 100).round(1)}%):"
          puts "     \"#{best_result.content}\""
        end
      end

      puts "\n5. Knowledge Sharing Demo..."

      # Create and share various types of knowledge
      knowledge_items = [
        KnowledgeItem.new("k1", "concept", "Distributed cognition emerges from agent interactions", 0.9, "ReasoningExpert"),
        KnowledgeItem.new("k2", "fact", "Neural networks can exhibit emergent collective behavior", 0.85, "LearningSpecialist"),
        KnowledgeItem.new("k3", "principle", "Attention mechanisms improve information processing efficiency", 0.8, "AttentionController"),
        KnowledgeItem.new("k4", "observation", "Memory consolidation requires periodic reinforcement", 0.75, "MemoryManager"),
      ]

      knowledge_items.each do |knowledge|
        shares = network.distribute_knowledge(knowledge, AgentNetwork::PropagationStrategy::Flood)
        puts "   ✓ Shared knowledge '#{knowledge.content[0..50]}...' to #{shares} agents"
      end

      puts "\n6. Distributed Task Execution Demo..."

      # Execute various distributed tasks
      tasks = [
        create_reasoning_task,
        create_knowledge_sharing_task,
        create_network_optimization_task,
      ]

      tasks.each do |task|
        puts "\n   Executing task: #{task.name}"
        puts "   Description: #{task.description}"
        puts "   Required capabilities: #{task.required_capabilities.join(", ")}"

        result = network.execute_distributed_task(task)

        puts "   → Success: #{result.success}"
        puts "   → Participating agents: #{result.participating_agents.size}"
        puts "   → Execution time: #{result.execution_time_ms.round(1)}ms"

        if result.success
          puts "   → Results:"
          result.results.each do |key, value|
            puts "     - #{key}: #{format_json_value(value)}"
          end
        else
          puts "   → Errors:"
          result.errors.each do |error|
            puts "     - #{error}"
          end
        end
      end

      puts "\n7. Network Topology Optimization..."

      optimization_result = network.optimize_topology
      puts "   → Optimization improved: #{optimization_result.improved}"
      puts "   → Original efficiency: #{(optimization_result.original_efficiency * 100).round(1)}%"
      puts "   → New efficiency: #{(optimization_result.new_efficiency * 100).round(1)}%"
      if optimization_result.improved
        puts "   → Improvement: #{optimization_result.improvement_percentage.round(1)}%"
      end
      puts "   → Description: #{optimization_result.description}"

      puts "\n8. Network Performance Analysis..."

      # Display comprehensive network metrics
      final_status = network.network_status
      puts "   Network Statistics:"
      puts "   - Total agents: #{final_status.agent_count}"
      puts "   - Network connectivity: #{(final_status.connectivity * 100).round(1)}%"
      puts "   - Average trust level: #{final_status.average_trust.round(3)}"
      puts "   - Configuration: #{final_status.config.network_topology} topology"

      puts "\n   Individual Agent Performance:"
      final_status.agents.each do |agent_id, agent_status|
        agent_name = agent_status["agent_name"].as_s
        peer_count = agent_status["peer_count"].as_i64
        uptime = agent_status["uptime_seconds"].as_i64

        puts "   - #{agent_name}: #{peer_count} peers, uptime #{uptime}s"
      end

      puts "\n9. Cleanup and Shutdown..."

      # Gracefully shutdown the network
      active_agents.each do |agent|
        agent.stop
        puts "   ✓ Agent #{agent.name} stopped"
      end

      network.stop
      puts "   ✓ Network stopped"

      puts "\n🎉 Demo completed successfully!"
      puts "\nKey achievements demonstrated:"
      puts "- ✅ Distributed agent network creation and management"
      puts "- ✅ Peer-to-peer agent discovery and communication"
      puts "- ✅ Collaborative reasoning across multiple agents"
      puts "- ✅ Knowledge sharing and distribution"
      puts "- ✅ Distributed task coordination and execution"
      puts "- ✅ Network topology optimization"
      puts "- ✅ Comprehensive performance monitoring"

      puts "\nThe distributed cognitive agent network has been successfully"
      puts "implemented as part of the Agent-Zero Genesis roadmap! 🚀"
    end

    private def create_reasoning_task : DistributedTask
      task = DistributedTask.new(
        "collaborative_reasoning",
        "Collaborative reasoning on artificial general intelligence",
        ["reasoning", "logic"]
      )
      task.payload["query"] = JSON::Any.new("What are the key components needed for artificial general intelligence?")
      task.priority = 8
      task.timeout_seconds = 30
      task
    end

    private def create_knowledge_sharing_task : DistributedTask
      task = DistributedTask.new(
        "knowledge_sharing",
        "Share knowledge about cognitive architectures",
        ["learning", "memory"]
      )
      task.payload["knowledge"] = JSON::Any.new("Cognitive architectures integrate perception, reasoning, learning, and action in unified systems")
      task.priority = 6
      task.timeout_seconds = 20
      task
    end

    private def create_network_optimization_task : DistributedTask
      task = DistributedTask.new(
        "network_optimization",
        "Optimize network topology for better information flow",
        ["attention", "reasoning"]
      )
      task.payload["optimization_target"] = JSON::Any.new("information_flow")
      task.priority = 7
      task.timeout_seconds = 25
      task
    end

    private def format_json_value(value : JSON::Any) : String
      case value.raw
      when String
        value.as_s
      when Int64
        value.as_i64.to_s
      when Float64
        value.as_f.round(3).to_s
      when Bool
        value.as_bool.to_s
      else
        value.to_s
      end
    end
  end
end

# Run the demo if this file is executed directly
if PROGRAM_NAME.ends_with?("distributed_network_demo.cr") || PROGRAM_NAME.ends_with?("distributed_network_demo")
  AgentZero::NetworkDemo.run
end
