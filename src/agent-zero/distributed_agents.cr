# Crystal implementation of Distributed Cognitive Agent Networks
# Part of Agent-Zero Genesis roadmap - Long-term (Month 3+) task
#
# This module provides a distributed network of cognitive agents that can
# communicate, collaborate, and share knowledge across network boundaries.
# Each agent maintains its own cognitive kernel while participating in
# collective reasoning processes.

require "socket"
require "json"
require "uuid"
require "../atomspace/atomspace"
require "../atomspace/cognitive_kernel"
require "../cogserver/cogserver"
require "../cogutil/cogutil"

module AgentZero
  VERSION = "0.1.0"

  # Represents a distributed cognitive agent node
  class AgentNode
    property id : String
    property name : String
    property host : String
    property port : Int32
    property cognitive_kernel : AtomSpace::CognitiveKernel
    property status : AgentStatus
    property capabilities : Array(String)
    property trust_level : Float64

    @peers : Hash(String, PeerInfo)
    @message_handlers : Hash(String, Proc(Message, Nil))
    @server : TCPServer?
    @running : Bool = false

    enum AgentStatus
      Initializing
      Active
      Idle
      Busy
      Offline
      Failed
    end

    struct PeerInfo
      property id : String
      property host : String
      property port : Int32
      property name : String
      property capabilities : Array(String)
      property trust_level : Float64
      property last_seen : Time
      property status : AgentStatus

      def initialize(@id : String, @host : String, @port : Int32, @name : String = "Unknown")
        @capabilities = [] of String
        @trust_level = 0.5
        @last_seen = Time.utc
        @status = AgentStatus::Active
      end

      def update_last_seen
        @last_seen = Time.utc
      end

      def is_stale?(threshold_minutes : Int32 = 5) : Bool
        (Time.utc - @last_seen).total_minutes > threshold_minutes
      end
    end

    def initialize(@name : String, @host : String = "localhost", @port : Int32 = 0)
      @id = UUID.random.to_s
      @cognitive_kernel = AtomSpace::CognitiveKernel.new([64, 64], 0.7, 0, "distributed_agent")
      @status = AgentStatus::Initializing
      @capabilities = ["reasoning", "learning", "memory", "communication"]
      @trust_level = 1.0
      @peers = Hash(String, PeerInfo).new
      @message_handlers = Hash(String, Proc(Message, Nil)).new

      # Auto-assign port if not specified
      @port = find_available_port if @port == 0

      setup_message_handlers
      CogUtil::Logger.info("AgentNode #{@name} (#{@id}) initialized on #{@host}:#{@port}")
    end

    # Start the agent and begin listening for connections
    def start
      return if @running

      @running = true
      @status = AgentStatus::Active

      spawn do
        start_server
      end

      spawn do
        discovery_heartbeat_loop
      end

      CogUtil::Logger.info("AgentNode #{@name} started and listening on #{@host}:#{@port}")
    end

    # Stop the agent
    def stop
      return unless @running

      @running = false
      @status = AgentStatus::Offline

      # Send goodbye messages to peers
      broadcast_message(Message.new("agent_goodbye", @id, {
        "agent_id" => @id,
        "name" => @name,
        "timestamp" => Time.utc.to_rfc3339
      }))

      @server.try(&.close)
      CogUtil::Logger.info("AgentNode #{@name} stopped")
    end

    # Connect to another agent
    def connect_to_peer(host : String, port : Int32) : Bool
      begin
        socket = TCPSocket.new(host, port)

        # Send introduction message
        intro_message = Message.new("agent_introduction", @id, {
          "agent_id" => @id,
          "name" => @name,
          "host" => @host,
          "port" => @port,
          "capabilities" => @capabilities,
          "trust_level" => @trust_level,
          "timestamp" => Time.utc.to_rfc3339
        })

        socket.puts(intro_message.to_json)

        # Wait for response
        response_data = socket.gets
        if response_data
          response = Message.from_json(response_data)
          if response.type == "agent_introduction_response" && response.payload["status"] == "accepted"
            peer_info = PeerInfo.new(
              response.sender_id,
              response.payload["host"].as_s,
              response.payload["port"].as_i,
              response.payload["name"].as_s
            )
            peer_info.capabilities = response.payload["capabilities"].as_a.map(&.as_s)
            peer_info.trust_level = response.payload["trust_level"].as_f

            @peers[peer_info.id] = peer_info
            CogUtil::Logger.info("Connected to peer #{peer_info.name} (#{peer_info.id})")

            socket.close
            return true
          end
        end

        socket.close
        return false
      rescue ex
        CogUtil::Logger.error("Failed to connect to peer #{host}:#{port} - #{ex.message}")
        return false
      end
    end

    # Send a message to a specific peer
    def send_message_to_peer(peer_id : String, message : Message) : Bool
      peer = @peers[peer_id]?
      return false unless peer

      begin
        socket = TCPSocket.new(peer.host, peer.port)
        socket.puts(message.to_json)
        socket.close

        CogUtil::Logger.debug("Sent message to #{peer.name}: #{message.type}")
        return true
      rescue ex
        CogUtil::Logger.error("Failed to send message to peer #{peer.name}: #{ex.message}")
        return false
      end
    end

    # Broadcast a message to all connected peers
    def broadcast_message(message : Message) : Int32
      successful_sends = 0

      @peers.each_value do |peer|
        if send_message_to_peer(peer.id, message)
          successful_sends += 1
        end
      end

      CogUtil::Logger.debug("Broadcast message to #{successful_sends}/#{@peers.size} peers")
      successful_sends
    end

    # Request collaborative reasoning from the network
    def request_collaborative_reasoning(query : String, timeout_seconds : Int32 = 30) : Array(CollaborativeResult)
      reasoning_id = UUID.random.to_s
      request_message = Message.new("collaborative_reasoning_request", @id, {
        "reasoning_id" => reasoning_id,
        "query" => query,
        "requester" => @name,
        "timeout" => timeout_seconds,
        "timestamp" => Time.utc.to_rfc3339
      })

      # Store expected responses
      expected_responses = @peers.keys
      received_results = [] of CollaborativeResult

      # Set up response handler
      original_handler = @message_handlers["collaborative_reasoning_response"]?
      @message_handlers["collaborative_reasoning_response"] = ->(message : Message) {
        if message.payload["reasoning_id"] == reasoning_id
          result = CollaborativeResult.new(
            message.sender_id,
            message.payload["response"].as_s,
            message.payload["confidence"].as_f,
            message.payload["reasoning_time_ms"].as_f
          )
          received_results << result
        end
        original_handler.try(&.call(message))
      }

      # Broadcast request
      broadcast_message(request_message)

      # Wait for responses with timeout
      start_time = Time.monotonic
      while received_results.size < expected_responses.size &&
            (Time.monotonic - start_time).total_seconds < timeout_seconds
        sleep 0.1
      end

      # Restore original handler
      if original_handler
        @message_handlers["collaborative_reasoning_response"] = original_handler
      else
        @message_handlers.delete("collaborative_reasoning_response")
      end

      CogUtil::Logger.info("Collaborative reasoning completed: #{received_results.size} responses for '#{query}'")
      received_results
    end

    # Share knowledge with the network
    def share_knowledge(knowledge_item : KnowledgeItem) : Int32
      share_message = Message.new("knowledge_share", @id, {
        "knowledge_id" => knowledge_item.id,
        "type" => knowledge_item.type,
        "content" => knowledge_item.content,
        "confidence" => knowledge_item.confidence,
        "source" => @name,
        "timestamp" => Time.utc.to_rfc3339
      })

      broadcast_message(share_message)
    end

    # Get network status and peer information
    def network_status : Hash(String, JSON::Any)
      peer_status = @peers.map do |id, peer|
        {
          id => JSON::Any.new({
            "name" => JSON::Any.new(peer.name),
            "host" => JSON::Any.new(peer.host),
            "port" => JSON::Any.new(peer.port.to_i64),
            "status" => JSON::Any.new(peer.status.to_s),
            "capabilities" => JSON::Any.new(peer.capabilities.map { |c| JSON::Any.new(c) }),
            "trust_level" => JSON::Any.new(peer.trust_level),
            "last_seen" => JSON::Any.new(peer.last_seen.to_rfc3339),
            "is_stale" => JSON::Any.new(peer.is_stale?)
          })
        }
      end.reduce({} of String => JSON::Any) { |acc, item| acc.merge!(item) }

      {
        "agent_id" => JSON::Any.new(@id),
        "agent_name" => JSON::Any.new(@name),
        "status" => JSON::Any.new(@status.to_s),
        "peer_count" => JSON::Any.new(@peers.size.to_i64),
        "peers" => JSON::Any.new(peer_status),
        "capabilities" => JSON::Any.new(@capabilities.map { |c| JSON::Any.new(c) }),
        "trust_level" => JSON::Any.new(@trust_level),
        "uptime_seconds" => JSON::Any.new(uptime_seconds.to_i64)
      }
    end

    private def start_server
      @server = TCPServer.new(@host, @port)

      while @running && (server = @server)
        begin
          client = server.accept
          spawn do
            handle_client_connection(client)
          end
        rescue ex
          break unless @running
          CogUtil::Logger.error("Server accept error: #{ex.message}")
        end
      end
    rescue ex
      CogUtil::Logger.error("Server error: #{ex.message}")
    end

    private def handle_client_connection(client : TCPSocket)
      begin
        while @running
          message_data = client.gets
          break unless message_data

          message = Message.from_json(message_data)
          process_message(message, client)
        end
      rescue ex
        CogUtil::Logger.debug("Client connection error: #{ex.message}")
      ensure
        client.close
      end
    end

    private def process_message(message : Message, client : TCPSocket?)
      handler = @message_handlers[message.type]?
      if handler
        handler.call(message)
      else
        CogUtil::Logger.warn("No handler for message type: #{message.type}")
      end

      # Update peer last seen if known
      if peer = @peers[message.sender_id]?
        peer.update_last_seen
      end
    end

    private def setup_message_handlers
      # Agent introduction handler
      @message_handlers["agent_introduction"] = ->(message : Message) {
        response_payload = {
          "status" => "accepted",
          "agent_id" => @id,
          "name" => @name,
          "host" => @host,
          "port" => @port,
          "capabilities" => @capabilities,
          "trust_level" => @trust_level,
          "timestamp" => Time.utc.to_rfc3339
        }

        response = Message.new("agent_introduction_response", @id, response_payload)

        # Add peer to our list
        peer_info = PeerInfo.new(
          message.sender_id,
          message.payload["host"].as_s,
          message.payload["port"].as_i,
          message.payload["name"].as_s
        )
        peer_info.capabilities = message.payload["capabilities"].as_a.map(&.as_s)
        peer_info.trust_level = message.payload["trust_level"].as_f

        @peers[peer_info.id] = peer_info
        CogUtil::Logger.info("New peer connected: #{peer_info.name} (#{peer_info.id})")
      }

      # Collaborative reasoning request handler
      @message_handlers["collaborative_reasoning_request"] = ->(message : Message) {
        query = message.payload["query"].as_s
        reasoning_id = message.payload["reasoning_id"].as_s

        start_time = Time.monotonic

        # Perform local reasoning using cognitive kernel
        result = perform_local_reasoning(query)

        reasoning_time = (Time.monotonic - start_time).total_milliseconds

        response = Message.new("collaborative_reasoning_response", @id, {
          "reasoning_id" => reasoning_id,
          "response" => result.content,
          "confidence" => result.confidence,
          "reasoning_time_ms" => reasoning_time,
          "agent_name" => @name,
          "timestamp" => Time.utc.to_rfc3339
        })

        send_message_to_peer(message.sender_id, response)
      }

      # Knowledge sharing handler
      @message_handlers["knowledge_share"] = ->(message : Message) {
        knowledge_item = KnowledgeItem.new(
          message.payload["knowledge_id"].as_s,
          message.payload["type"].as_s,
          message.payload["content"].as_s,
          message.payload["confidence"].as_f,
          message.payload["source"].as_s
        )

        # Integrate knowledge into local cognitive kernel
        integrate_shared_knowledge(knowledge_item)

        CogUtil::Logger.debug("Received knowledge from #{knowledge_item.source}: #{knowledge_item.type}")
      }

      # Agent goodbye handler
      @message_handlers["agent_goodbye"] = ->(message : Message) {
        peer_id = message.payload["agent_id"].as_s
        if peer = @peers.delete(peer_id)
          CogUtil::Logger.info("Peer #{peer.name} disconnected")
        end
      }

      # Discovery heartbeat handler
      @message_handlers["discovery_heartbeat"] = ->(message : Message) {
        # Update or add peer information
        peer_id = message.sender_id
        if peer = @peers[peer_id]?
          peer.update_last_seen
          peer.status = AgentStatus.parse(message.payload["status"].as_s)
        else
          # New peer discovered via heartbeat
          peer_info = PeerInfo.new(
            peer_id,
            message.payload["host"].as_s,
            message.payload["port"].as_i,
            message.payload["name"].as_s
          )
          peer_info.capabilities = message.payload["capabilities"].as_a.map(&.as_s)
          peer_info.status = AgentStatus.parse(message.payload["status"].as_s)
          @peers[peer_id] = peer_info

          CogUtil::Logger.info("Discovered new peer via heartbeat: #{peer_info.name}")
        end
      }
    end

    private def discovery_heartbeat_loop
      while @running
        # Send heartbeat to all known peers
        heartbeat_message = Message.new("discovery_heartbeat", @id, {
          "agent_id" => @id,
          "name" => @name,
          "host" => @host,
          "port" => @port,
          "status" => @status.to_s,
          "capabilities" => @capabilities,
          "timestamp" => Time.utc.to_rfc3339
        })

        broadcast_message(heartbeat_message)

        # Clean up stale peers
        @peers.reject! do |id, peer|
          if peer.is_stale?
            CogUtil::Logger.debug("Removing stale peer: #{peer.name}")
            true
          else
            false
          end
        end

        sleep 30 # Send heartbeat every 30 seconds
      end
    end

    private def perform_local_reasoning(query : String) : ReasoningResult
      # Use the cognitive kernel for local reasoning
      # This is a simplified implementation - would integrate with PLN, ECAN, etc.

      # Add query to atomspace
      query_node = @cognitive_kernel.add_concept_node("query_#{UUID.random}")
      query_content = @cognitive_kernel.add_concept_node(query)
      @cognitive_kernel.add_evaluation_link(query_node, query_content)

      # Generate cognitive tensor encoding for the query
      tensor_encoding = @cognitive_kernel.cognitive_tensor_field_encoding("reasoning")

      # Simple reasoning based on tensor field patterns
      confidence = Math.min(0.9, tensor_encoding.sum / tensor_encoding.size / 10.0)
      response_content = "Reasoning result for: #{query} (confidence: #{confidence.round(3)})"

      ReasoningResult.new(response_content, confidence)
    end

    private def integrate_shared_knowledge(knowledge : KnowledgeItem)
      # Integrate shared knowledge into local cognitive kernel
      knowledge_node = @cognitive_kernel.add_concept_node("shared_knowledge_#{knowledge.id}")
      content_node = @cognitive_kernel.add_concept_node(knowledge.content)

      # Create links based on knowledge type
      case knowledge.type
      when "concept"
        @cognitive_kernel.add_inheritance_link(content_node, knowledge_node)
      when "fact"
        @cognitive_kernel.add_evaluation_link(knowledge_node, content_node)
      end

      CogUtil::Logger.debug("Integrated shared knowledge: #{knowledge.type} - #{knowledge.content}")
    end

    private def find_available_port : Int32
      # Find an available port starting from 20000
      (20000..21000).each do |port|
        begin
          server = TCPServer.new(@host, port)
          server.close
          return port
        rescue
          # Port is in use, try next one
        end
      end

      # Fallback to random port
      Random.rand(21000..30000)
    end

    private def uptime_seconds : Float64
      (Time.utc - @created_at).total_seconds
    end

    getter :created_at

    @created_at : Time = Time.utc
  end

  # Message structure for inter-agent communication
  struct Message
    include JSON::Serializable

    property type : String
    property sender_id : String
    property payload : Hash(String, JSON::Any)
    property timestamp : String

    def initialize(@type : String, @sender_id : String, @payload : Hash(String, JSON::Any))
      @timestamp = Time.utc.to_rfc3339
    end

    def initialize(@type : String, @sender_id : String, payload : Hash(String, String | Int32 | Float64 | Array(String) | Bool))
      @timestamp = Time.utc.to_rfc3339
      @payload = payload.transform_values do |value|
        case value
        when String
          JSON::Any.new(value)
        when Int32
          JSON::Any.new(value.to_i64)
        when Float64
          JSON::Any.new(value)
        when Array(String)
          JSON::Any.new(value.map { |v| JSON::Any.new(v) })
        when Bool
          JSON::Any.new(value)
        else
          JSON::Any.new(value.to_s)
        end
      end
    end
  end

  # Result of collaborative reasoning
  struct CollaborativeResult
    property agent_id : String
    property content : String
    property confidence : Float64
    property reasoning_time_ms : Float64

    def initialize(@agent_id : String, @content : String, @confidence : Float64, @reasoning_time_ms : Float64)
    end
  end

  # Knowledge item for sharing between agents
  struct KnowledgeItem
    property id : String
    property type : String
    property content : String
    property confidence : Float64
    property source : String
    property created_at : Time

    def initialize(@id : String, @type : String, @content : String, @confidence : Float64, @source : String)
      @created_at = Time.utc
    end
  end

  # Local reasoning result
  struct ReasoningResult
    property content : String
    property confidence : Float64

    def initialize(@content : String, @confidence : Float64)
    end
  end
end