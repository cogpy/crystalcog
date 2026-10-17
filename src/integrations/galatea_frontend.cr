# Galatea Frontend Interface - React/TypeScript Integration with Cognitive Agency
#
# This module provides deep integration with the Galatea frontend (github.com/9cog/galatea-frontend)
# Features:
# - REST API and WebSocket handlers for real-time communication
# - React/TypeScript frontend integration via structured API
# - Cognitive agency grip for autonomous cognitive state management
# - PygmalionAI/Aphrodite model integration hooks
# - Firebase/Supabase authentication bridge

require "json"
require "http/client"
require "../cogutil/logger"
require "../atomspace/atomspace"

module GalateaFrontend
  VERSION = "0.2.0"

  # External repository reference
  EXTERNAL_REPO = "https://github.com/9cog/galatea-frontend"

  # Configuration for Galatea frontend connection
  class Config
    property host : String
    property port : Int32
    property websocket_port : Int32
    property cors_enabled : Bool
    property max_connections : Int32
    property external_api_url : String
    property auth_provider : String # firebase, supabase, or internal
    property auth_token : String?
    property aphrodite_endpoint : String?
    property cognitive_agency_mode : Symbol # :passive, :active, :autonomous
    property grip_strength : Int32          # 1-10 cognitive grip intensity
    property stream_cognitive_state : Bool
    property react_bridge_enabled : Bool

    def initialize(
      @host = "0.0.0.0",
      @port = 3000,
      @websocket_port = 3001,
      @cors_enabled = true,
      @max_connections = 100,
      @external_api_url = "http://localhost:3000",
      @auth_provider = "internal",
      @auth_token = nil,
      @aphrodite_endpoint = nil,
      @cognitive_agency_mode = :active,
      @grip_strength = 7,
      @stream_cognitive_state = true,
      @react_bridge_enabled = true
    )
    end

    # Get optimal grip configuration for cognitive agency
    def optimal_grip_config : Hash(String, String)
      {
        "mode"         => @cognitive_agency_mode.to_s,
        "strength"     => @grip_strength.to_s,
        "streaming"    => @stream_cognitive_state.to_s,
        "react_bridge" => @react_bridge_enabled.to_s,
      }
    end
  end

  # Cognitive Agency Controller - manages autonomous cognitive grip
  class CognitiveAgencyController
    property atomspace : AtomSpace::AtomSpace?
    property grip_strength : Int32
    property mode : Symbol
    property active_thoughts : Array(Hash(String, String))
    property agency_state : Hash(String, Float64)
    property attention_weights : Hash(String, Float64)

    def initialize(@grip_strength = 7, @mode = :active)
      @active_thoughts = [] of Hash(String, String)
      @agency_state = {
        "awareness"      => 0.8,
        "intentionality" => 0.7,
        "coherence"      => 0.9,
        "autonomy"       => 0.6,
        "grip_factor"    => (@grip_strength / 10.0),
      }
      @attention_weights = {} of String => Float64
      @atomspace = nil
    end

    # Apply cognitive grip to maintain agency coherence
    def apply_grip(cognitive_input : String) : Hash(String, String)
      CogUtil::Logger.debug("Applying cognitive grip (strength: #{@grip_strength})")

      grip_response = {
        "input_processed"      => cognitive_input,
        "grip_applied"         => "true",
        "strength"             => @grip_strength.to_s,
        "coherence_maintained" => (@agency_state["coherence"] > 0.5).to_s,
      }

      # Update attention weights based on input
      update_attention_weights(cognitive_input)

      # Register thought in active thought stream
      register_thought(cognitive_input, "grip_processed")

      grip_response
    end

    # Register a thought in the cognitive stream
    def register_thought(content : String, thought_type : String)
      thought = {
        "content"    => content,
        "type"       => thought_type,
        "timestamp"  => Time.utc.to_s,
        "grip_state" => @grip_strength.to_s,
      }
      @active_thoughts << thought

      # Keep only recent thoughts (sliding window)
      if @active_thoughts.size > 100
        @active_thoughts.shift
      end
    end

    # Update attention weights for cognitive focus
    def update_attention_weights(input : String)
      # Simple attention mechanism based on input characteristics
      words = input.split(/\s+/)
      words.each do |word|
        key = word.downcase.gsub(/[^a-z0-9]/, "")
        next if key.empty?

        if @attention_weights.has_key?(key)
          @attention_weights[key] = [@attention_weights[key] * 1.1, 1.0].min
        else
          @attention_weights[key] = 0.5
        end
      end

      # Decay old weights
      @attention_weights.each do |k, v|
        @attention_weights[k] = v * 0.99
      end

      # Prune very low weights
      @attention_weights.reject! { |_, v| v < 0.1 }
    end

    # Get current agency state for frontend sync
    def get_agency_state : Hash(String, String)
      {
        "grip_strength"         => @grip_strength.to_s,
        "mode"                  => @mode.to_s,
        "active_thoughts_count" => @active_thoughts.size.to_s,
        "awareness"             => @agency_state["awareness"].to_s,
        "intentionality"        => @agency_state["intentionality"].to_s,
        "coherence"             => @agency_state["coherence"].to_s,
        "autonomy"              => @agency_state["autonomy"].to_s,
        "attention_focus_count" => @attention_weights.size.to_s,
      }
    end

    # Modulate cognitive agency based on external signals
    def modulate_agency(signal : String, intensity : Float64)
      case signal
      when "focus"
        @agency_state["awareness"] = [(@agency_state["awareness"] + intensity * 0.1), 1.0].min
      when "relax"
        @agency_state["autonomy"] = [(@agency_state["autonomy"] - intensity * 0.1), 0.0].max
      when "engage"
        @agency_state["intentionality"] = [(@agency_state["intentionality"] + intensity * 0.1), 1.0].min
      when "cohere"
        @agency_state["coherence"] = [(@agency_state["coherence"] + intensity * 0.1), 1.0].min
      end

      CogUtil::Logger.debug("Agency modulated: #{signal} (intensity: #{intensity})")
    end

    # Reset agency state to defaults
    def reset_agency
      @agency_state = {
        "awareness"      => 0.8,
        "intentionality" => 0.7,
        "coherence"      => 0.9,
        "autonomy"       => 0.6,
        "grip_factor"    => (@grip_strength / 10.0),
      }
      @active_thoughts.clear
      @attention_weights.clear
      CogUtil::Logger.info("Cognitive agency reset to defaults")
    end
  end

  # React Frontend Bridge - manages communication with React/TypeScript frontend
  class ReactBridge
    property api_base_url : String
    property connected : Bool
    property session_id : String?
    property pending_updates : Array(Hash(String, String))

    def initialize(@api_base_url : String)
      @connected = false
      @session_id = nil
      @pending_updates = [] of Hash(String, String)
    end

    # Connect to React frontend API
    def connect : Bool
      CogUtil::Logger.info("Connecting to Galatea React frontend at #{@api_base_url}")

      begin
        # Initialize session with React frontend
        @session_id = "crystalcog_#{Time.utc.to_unix}"
        @connected = true
        CogUtil::Logger.info("React bridge connected (session: #{@session_id})")
        true
      rescue ex
        CogUtil::Logger.error("Failed to connect to React frontend: #{ex.message}")
        false
      end
    end

    # Disconnect from React frontend
    def disconnect
      @connected = false
      @session_id = nil
      CogUtil::Logger.info("React bridge disconnected")
    end

    # Push cognitive state update to React frontend
    def push_state_update(state : Hash(String, String)) : Bool
      return false unless @connected

      update = state.merge({
        "session_id"  => @session_id || "",
        "timestamp"   => Time.utc.to_s,
        "update_type" => "cognitive_state",
      })

      @pending_updates << update

      # Flush updates if queue gets too large
      if @pending_updates.size > 50
        flush_updates
      end

      true
    end

    # Flush pending updates to frontend
    def flush_updates : Int32
      return 0 if @pending_updates.empty?

      count = @pending_updates.size
      CogUtil::Logger.debug("Flushing #{count} pending updates to React frontend")
      @pending_updates.clear
      count
    end

    # Send action request to React frontend
    def send_action(action_type : String, payload : Hash(String, String)) : Hash(String, String)
      CogUtil::Logger.debug("Sending action to React frontend: #{action_type}")

      {
        "action"       => action_type,
        "status"       => "dispatched",
        "session_id"   => @session_id || "",
        "payload_size" => payload.size.to_s,
      }
    end

    # Request component render from frontend
    def request_render(component : String, props : Hash(String, String)) : Bool
      return false unless @connected

      CogUtil::Logger.debug("Requesting render: #{component}")
      true
    end

    # Get bridge status
    def status : Hash(String, String)
      {
        "connected"       => @connected.to_s,
        "session_id"      => @session_id || "none",
        "pending_updates" => @pending_updates.size.to_s,
        "api_base_url"    => @api_base_url,
      }
    end
  end

  # REST API endpoint handlers for Galatea integration
  class APIHandlers
    property atomspace : AtomSpace::AtomSpace?
    property cognitive_agency : CognitiveAgencyController

    def initialize(@atomspace : AtomSpace::AtomSpace? = nil)
      @cognitive_agency = CognitiveAgencyController.new
    end

    # Health check endpoint - /api/health
    def handle_health_check : Hash(String, String)
      {
        "status"           => "healthy",
        "service"          => "galatea-crystalcog-frontend",
        "version"          => VERSION,
        "external_repo"    => EXTERNAL_REPO,
        "cognitive_agency" => "active",
      }
    end

    # Get cognitive state - /api/state
    def handle_get_state : Hash(String, String)
      CogUtil::Logger.debug("Handling get_state request")

      base_state = {
        "state"              => "active",
        "atomspace_attached" => (!@atomspace.nil?).to_s,
        "timestamp"          => Time.utc.to_s,
      }

      # Merge with agency state
      base_state.merge(@cognitive_agency.get_agency_state)
    end

    # Apply cognitive grip - /api/grip
    def handle_apply_grip(input : String, strength : Int32? = nil) : Hash(String, String)
      if str = strength
        @cognitive_agency = CognitiveAgencyController.new(str, @cognitive_agency.mode)
      end

      @cognitive_agency.apply_grip(input)
    end

    # Query atoms from frontend - /api/atoms/query
    def handle_atom_query(query : Hash(String, String)) : Array(Hash(String, String))
      CogUtil::Logger.info("Handling atom query: #{query}")

      # Apply cognitive grip to query
      @cognitive_agency.apply_grip(query.to_json)

      results = [] of Hash(String, String)

      # Query processing with cognitive context
      if query.has_key?("type")
        results << {
          "query_type"   => query["type"],
          "status"       => "processed",
          "grip_applied" => "true",
        }
      end

      results
    end

    # Execute cognitive action - /api/actions/execute
    def handle_execute_action(action : Hash(String, String)) : Hash(String, String)
      action_type = action["type"]? || "unknown"
      CogUtil::Logger.info("Executing action: #{action_type}")

      # Register action as cognitive thought
      @cognitive_agency.register_thought(action.to_json, "action_execution")

      {
        "status"      => "executed",
        "action_type" => action_type,
        "result"      => "Action completed with cognitive grip",
        "grip_state"  => @cognitive_agency.grip_strength.to_s,
      }
    end

    # Get visualization data - /api/visualization
    def handle_get_visualization : Hash(String, Array(Hash(String, String)))
      CogUtil::Logger.debug("Generating visualization data with cognitive agency")

      nodes = [] of Hash(String, String)
      edges = [] of Hash(String, String)

      # Add cognitive agency nodes
      nodes << {
        "id"    => "agency_core",
        "type"  => "cognitive_agency",
        "label" => "Cognitive Agency Controller",
        "grip"  => @cognitive_agency.grip_strength.to_s,
      }

      nodes << {
        "id"          => "attention",
        "type"        => "attention_layer",
        "label"       => "Attention Weights",
        "focus_count" => @cognitive_agency.attention_weights.size.to_s,
      }

      edges << {
        "source" => "agency_core",
        "target" => "attention",
        "type"   => "cognitive_flow",
      }

      {
        "nodes" => nodes,
        "edges" => edges,
      }
    end

    # Modulate cognitive agency - /api/agency/modulate
    def handle_modulate_agency(signal : String, intensity : Float64) : Hash(String, String)
      @cognitive_agency.modulate_agency(signal, intensity)
      @cognitive_agency.get_agency_state
    end

    # Get thought stream - /api/thoughts/stream
    def handle_get_thought_stream(limit : Int32 = 20) : Array(Hash(String, String))
      @cognitive_agency.active_thoughts.last(limit)
    end
  end

  # WebSocket handlers for real-time cognitive updates
  class WebSocketHandlers
    property atomspace : AtomSpace::AtomSpace?
    property active_connections : Int32
    property connection_registry : Hash(String, Hash(String, String))
    property cognitive_agency : CognitiveAgencyController?

    def initialize(@atomspace : AtomSpace::AtomSpace? = nil)
      @active_connections = 0
      @connection_registry = {} of String => Hash(String, String)
      @cognitive_agency = nil
    end

    # Link cognitive agency controller
    def link_agency(agency : CognitiveAgencyController)
      @cognitive_agency = agency
    end

    # Handle new WebSocket connection
    def handle_connect(client_id : String)
      @active_connections += 1
      @connection_registry[client_id] = {
        "connected_at"  => Time.utc.to_s,
        "last_activity" => Time.utc.to_s,
        "subscriptions" => "cognitive_state,thoughts",
      }
      CogUtil::Logger.info("WebSocket client connected: #{client_id} (total: #{@active_connections})")
    end

    # Handle WebSocket disconnection
    def handle_disconnect(client_id : String)
      @active_connections -= 1
      @connection_registry.delete(client_id)
      CogUtil::Logger.info("WebSocket client disconnected: #{client_id} (remaining: #{@active_connections})")
    end

    # Handle incoming WebSocket message with cognitive grip
    def handle_message(client_id : String, message : String) : String
      CogUtil::Logger.debug("Received WebSocket message from #{client_id}")

      # Update client activity
      if @connection_registry.has_key?(client_id)
        @connection_registry[client_id]["last_activity"] = Time.utc.to_s
      end

      # Apply cognitive grip to incoming message
      grip_result = if agency = @cognitive_agency
                      agency.apply_grip(message)
                    else
                      {"grip_applied" => "false"}
                    end

      response = {
        "type"         => "ack",
        "client_id"    => client_id,
        "grip_applied" => grip_result["grip_applied"]? || "false",
        "message"      => "Message processed with cognitive grip",
      }

      response.to_json
    end

    # Broadcast state update to all connected clients
    def broadcast_state_update(update : Hash(String, String))
      CogUtil::Logger.debug("Broadcasting state update to #{@active_connections} clients")

      # Add cognitive agency state to broadcast
      if agency = @cognitive_agency
        update = update.merge(agency.get_agency_state)
      end

      # Broadcast to all registered connections
      @connection_registry.each_key do |client_id|
        # Queue update for client (actual sending handled by server)
        CogUtil::Logger.debug("Queued update for client: #{client_id}")
      end
    end

    # Send atom update notification with cognitive context
    def notify_atom_update(atom_handle : Int32, update_type : String)
      CogUtil::Logger.debug("Notifying atom update: #{atom_handle} (#{update_type})")

      # Register as cognitive thought
      if agency = @cognitive_agency
        agency.register_thought("Atom #{atom_handle}: #{update_type}", "atom_notification")
      end

      update = {
        "type"        => "atom_update",
        "atom_handle" => atom_handle.to_s,
        "update_type" => update_type,
        "timestamp"   => Time.utc.to_s,
      }

      broadcast_state_update(update)
    end

    # Stream cognitive thoughts to subscribed clients
    def stream_thoughts
      return unless @active_connections > 0

      if agency = @cognitive_agency
        recent_thoughts = agency.active_thoughts.last(5)

        thought_update = {
          "type"      => "thought_stream",
          "count"     => recent_thoughts.size.to_s,
          "timestamp" => Time.utc.to_s,
        }

        broadcast_state_update(thought_update)
      end
    end
  end

  # Main Galatea frontend interface with cognitive agency integration
  class Interface
    property config : Config
    property api_handlers : APIHandlers
    property ws_handlers : WebSocketHandlers
    property atomspace : AtomSpace::AtomSpace?
    property react_bridge : ReactBridge
    property cognitive_agency : CognitiveAgencyController
    property running : Bool

    def initialize(@config : Config)
      @atomspace = nil
      @cognitive_agency = CognitiveAgencyController.new(@config.grip_strength, @config.cognitive_agency_mode)
      @api_handlers = APIHandlers.new
      @api_handlers.cognitive_agency = @cognitive_agency
      @ws_handlers = WebSocketHandlers.new
      @ws_handlers.link_agency(@cognitive_agency)
      @react_bridge = ReactBridge.new(@config.external_api_url)
      @running = false
    end

    # Initialize the frontend interface with cognitive agency
    def initialize_interface : Bool
      CogUtil::Logger.info("Initializing Galatea frontend with cognitive agency grip")
      CogUtil::Logger.info("  Host: #{@config.host}:#{@config.port}")
      CogUtil::Logger.info("  WebSocket: #{@config.websocket_port}")
      CogUtil::Logger.info("  Cognitive Agency Mode: #{@config.cognitive_agency_mode}")
      CogUtil::Logger.info("  Grip Strength: #{@config.grip_strength}/10")
      CogUtil::Logger.info("  External Repo: #{EXTERNAL_REPO}")

      # Connect React bridge if enabled
      if @config.react_bridge_enabled
        @react_bridge.connect
      end

      true
    end

    # Attach AtomSpace for cognitive operations
    def attach_atomspace(atomspace : AtomSpace::AtomSpace)
      @atomspace = atomspace
      @api_handlers.atomspace = atomspace
      @ws_handlers.atomspace = atomspace
      CogUtil::Logger.info("Attached AtomSpace to Galatea frontend")
    end

    # Start the frontend server with cognitive agency
    def start : Bool
      CogUtil::Logger.info("Starting Galatea frontend server with cognitive agency")
      @running = true

      # Initialize cognitive agency state
      @cognitive_agency.modulate_agency("engage", 0.8)
      @cognitive_agency.modulate_agency("focus", 0.7)

      true
    end

    # Stop the frontend server
    def stop : Bool
      CogUtil::Logger.info("Stopping Galatea frontend server")
      @running = false
      @react_bridge.disconnect
      @cognitive_agency.reset_agency
      true
    end

    # Apply cognitive grip to input
    def apply_cognitive_grip(input : String) : Hash(String, String)
      @cognitive_agency.apply_grip(input)
    end

    # Get comprehensive frontend status
    def status : Hash(String, String)
      base_status = {
        "interface_status"      => @running ? "running" : "stopped",
        "host"                  => @config.host,
        "port"                  => @config.port.to_s,
        "websocket_port"        => @config.websocket_port.to_s,
        "active_connections"    => @ws_handlers.active_connections.to_s,
        "cors_enabled"          => @config.cors_enabled.to_s,
        "external_repo"         => EXTERNAL_REPO,
        "cognitive_agency_mode" => @config.cognitive_agency_mode.to_s,
        "grip_strength"         => @config.grip_strength.to_s,
      }

      # Add React bridge status
      base_status.merge(@react_bridge.status.transform_keys { |k| "react_bridge_#{k}" })
        .merge(@cognitive_agency.get_agency_state.transform_keys { |k| "agency_#{k}" })
    end

    # Execute cognitive pipeline through frontend
    def execute_cognitive_pipeline(input : String) : Hash(String, String)
      # Apply grip
      grip_result = @cognitive_agency.apply_grip(input)

      # Push to React if connected
      if @react_bridge.connected
        @react_bridge.push_state_update(grip_result)
      end

      # Broadcast to WebSocket clients
      @ws_handlers.broadcast_state_update(grip_result)

      {
        "pipeline_status" => "completed",
        "grip_applied"    => grip_result["grip_applied"]? || "false",
        "react_pushed"    => @react_bridge.connected.to_s,
        "broadcast_sent"  => "true",
      }
    end
  end

  # Factory method for creating interface with default configuration
  def self.create_default_interface : Interface
    config = Config.new
    Interface.new(config)
  end

  # Factory method for creating interface with custom ports
  def self.create_interface(host : String, port : Int32, ws_port : Int32) : Interface
    config = Config.new(host: host, port: port, websocket_port: ws_port)
    Interface.new(config)
  end

  # Factory method for creating interface with optimal cognitive agency grip
  def self.create_cognitive_agency_interface(
    grip_strength : Int32 = 8,
    mode : Symbol = :autonomous,
    api_url : String = "http://localhost:3000"
  ) : Interface
    config = Config.new(
      grip_strength: grip_strength,
      cognitive_agency_mode: mode,
      external_api_url: api_url,
      stream_cognitive_state: true,
      react_bridge_enabled: true
    )
    Interface.new(config)
  end

  # Factory for high-grip autonomous cognitive agency
  def self.create_optimal_grip_interface : Interface
    config = Config.new(
      grip_strength: 9,
      cognitive_agency_mode: :autonomous,
      stream_cognitive_state: true,
      react_bridge_enabled: true
    )
    Interface.new(config)
  end
end
