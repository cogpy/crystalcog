# Agent-Zero Main Executable
# Distributed Cognitive Agent Network Server
#
# This executable provides a standalone server for running
# distributed cognitive agent networks with full capabilities.

require "./agent_network"
require "./distributed_agents"
require "./network_services"
require "../cogutil/cogutil"
require "option_parser"
require "json"

module AgentZero
  class AgentZeroServer
    property network : AgentNetwork
    property config : ServerConfig
    
    struct ServerConfig
      property network_name : String
      property discovery_port : Int32
      property agent_count : Int32
      property enable_rest_api : Bool
      property rest_api_port : Int32
      property log_level : String
      
      def initialize
        @network_name = "AgentZeroNetwork"
        @discovery_port = 19000
        @agent_count = 3
        @enable_rest_api = true
        @rest_api_port = 8080
        @log_level = "info"
      end
    end
    
    def initialize(@config : ServerConfig = ServerConfig.new)
      # Initialize network configuration
      network_config = AgentNetwork::NetworkConfig.new
      network_config.discovery_port = @config.discovery_port
      
      @network = AgentNetwork.new(@config.network_name, network_config)
      
      CogUtil::Logger.info("AgentZero Server initialized")
    end
    
    def start
      CogUtil::Logger.info("Starting AgentZero Server...")
      CogUtil::Logger.info("Network: #{@config.network_name}")
      CogUtil::Logger.info("Discovery Port: #{@config.discovery_port}")
      CogUtil::Logger.info("Agent Count: #{@config.agent_count}")
      
      # Create initial agents
      @config.agent_count.times do |i|
        agent_name = "Agent-#{i + 1}"
        capabilities = ["reasoning", "learning", "memory", "communication"]
        
        agent = @network.create_agent(agent_name, capabilities)
        if agent
          CogUtil::Logger.info("Created agent: #{agent_name} (#{agent.id})")
        else
          CogUtil::Logger.error("Failed to create agent: #{agent_name}")
        end
      end
      
      # Start the network
      @network.start
      
      CogUtil::Logger.info("AgentZero Server started successfully")
      CogUtil::Logger.info("Network status: #{@network.agents.size} agents active")
      
      # Display network status
      display_status
    end
    
    def stop
      CogUtil::Logger.info("Stopping AgentZero Server...")
      @network.stop
      CogUtil::Logger.info("AgentZero Server stopped")
    end
    
    def display_status
      status = @network.network_status
      
      puts "\n" + "=" * 60
      puts "AgentZero Network Status"
      puts "=" * 60
      puts "Network Name: #{status.network_name}"
      puts "Agent Count: #{status.agent_count}"
      puts "Running: #{status.running ? "Yes" : "No"}"
      puts "Connectivity: #{(status.connectivity * 100).round(2)}%"
      puts "Average Trust: #{(status.average_trust * 100).round(2)}%"
      puts "=" * 60
      
      if status.agents.size > 0
        puts "\nAgent Details:"
        puts "-" * 60
        status.agents.each do |agent_id, agent_data|
          name = agent_data["agent_name"]?.try(&.as_s) || "Unknown"
          agent_status = agent_data["status"]?.try(&.as_s) || "Unknown"
          peer_count = agent_data["peer_count"]?.try(&.as_i64) || 0
          capabilities = agent_data["capabilities"]?.try(&.as_a.map(&.as_s)) || [] of String
          
          puts "  #{name} (#{agent_id[0..7]}...)"
          puts "    Status: #{agent_status}"
          puts "    Peers: #{peer_count}"
          puts "    Capabilities: #{capabilities.join(", ")}"
          puts ""
        end
      end
    end
    
    def run_interactive
      CogUtil::Logger.info("Starting interactive mode...")
      
      loop do
        print "\nAgentZero> "
        input = gets
        break if input.nil?
        
        command = input.strip
        break if command.empty? || command == "exit" || command == "quit"
        
        case command
        when "status"
          display_status
        when "help"
          display_help
        when /^reason (.+)/
          query = $1
          run_reasoning(query)
        when /^knowledge (.+)/
          knowledge_text = $1
          share_knowledge(knowledge_text)
        else
          puts "Unknown command: #{command}"
          puts "Type 'help' for available commands"
        end
      end
      
      CogUtil::Logger.info("Exiting interactive mode...")
    end
    
    def run_reasoning(query : String)
      puts "\nExecuting collaborative reasoning..."
      puts "Query: #{query}"
      
      result = @network.collaborative_reasoning(query, timeout_seconds: 10)
      
      puts "\nResults:"
      puts "-" * 60
      puts "Query: #{result.query}"
      puts "Responses: #{result.results.size}"
      puts "Consensus Confidence: #{(result.consensus_confidence * 100).round(2)}%"
      
      if result.results.size > 0
        puts "\nAgent Responses:"
        result.results.each_with_index do |res, idx|
          puts "\n  #{idx + 1}. Agent: #{res.agent_id[0..7]}..."
          puts "     Response: #{res.content}"
          puts "     Confidence: #{(res.confidence * 100).round(2)}%"
          puts "     Time: #{res.reasoning_time_ms.round(2)}ms"
        end
      else
        puts "\nNo responses received (agents may be busy or unavailable)"
      end
    end
    
    def share_knowledge(text : String)
      knowledge = KnowledgeItem.new(
        "user-knowledge-#{Time.utc.to_unix}",
        "fact",
        text,
        0.8,
        "user_input"
      )
      
      shares = @network.distribute_knowledge(knowledge)
      puts "Knowledge shared with #{shares} agents"
    end
    
    def display_help
      puts "\nAvailable Commands:"
      puts "-" * 60
      puts "  status              - Display network status"
      puts "  reason <query>      - Execute collaborative reasoning"
      puts "  knowledge <text>    - Share knowledge with network"
      puts "  help                - Display this help message"
      puts "  exit/quit           - Exit the server"
      puts "-" * 60
    end
  end
end

# Main entry point
def main
  config = AgentZero::AgentZeroServer::ServerConfig.new
  interactive = false
  
  OptionParser.parse do |parser|
    parser.banner = "Usage: agent_zero_main [options]"
    
    parser.on("-n NAME", "--name=NAME", "Network name") do |name|
      config.network_name = name
    end
    
    parser.on("-p PORT", "--port=PORT", "Discovery port") do |port|
      config.discovery_port = port.to_i
    end
    
    parser.on("-a COUNT", "--agents=COUNT", "Number of agents to create") do |count|
      config.agent_count = count.to_i
    end
    
    parser.on("-i", "--interactive", "Run in interactive mode") do
      interactive = true
    end
    
    parser.on("-l LEVEL", "--log-level=LEVEL", "Log level (debug, info, warn, error)") do |level|
      config.log_level = level
    end
    
    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit
    end
  end
  
  # Create and start server
  server = AgentZero::AgentZeroServer.new(config)
  
  # Handle signals
  Signal::INT.trap do
    puts "\nReceived interrupt signal, shutting down..."
    server.stop
    exit
  end
  
  Signal::TERM.trap do
    puts "\nReceived termination signal, shutting down..."
    server.stop
    exit
  end
  
  # Start server
  server.start
  
  if interactive
    server.run_interactive
    server.stop
  else
    puts "\nPress Ctrl+C to stop the server"
    sleep  # Keep server running
  end
end

# Run main if this is the main file
main if PROGRAM_NAME.includes?("agent_zero_main")
