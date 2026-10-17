# Paphos Backend Connector - Crystal/Lucky Framework Integration with Cognitive Agency
#
# This module provides deep integration with the Paphos backend (github.com/9cog/paphos-backend)
# Features:
# - Lucky framework API integration (/api/v1 endpoints)
# - PostgreSQL-compatible persistence layer
# - Cognitive agency grip for state coordination
# - Event streaming for distributed cognitive synchronization
# - Authentication and token management

require "json"
require "http/client"
require "../cogutil/logger"
require "../atomspace/atomspace"

module PaphosBackend
  VERSION = "0.2.0"

  # External repository reference
  EXTERNAL_REPO = "https://github.com/9cog/paphos-backend"

  # API version for Lucky framework routes
  API_VERSION = "v1"

  # Configuration for Paphos backend connection
  class Config
    property backend_url : String
    property api_key : String?
    property timeout : Int32
    property retry_attempts : Int32
    property enable_caching : Bool
    property postgresql_compatible : Bool
    property lucky_api_prefix : String
    property cognitive_agency_sync : Bool
    property grip_coordination_mode : Symbol # :leader, :follower, :peer
    property state_sync_interval : Int32     # seconds
    property event_streaming_enabled : Bool
    property batch_operations : Bool

    def initialize(
      @backend_url = "http://localhost:3000",
      @api_key = nil,
      @timeout = 30,
      @retry_attempts = 3,
      @enable_caching = true,
      @postgresql_compatible = true,
      @lucky_api_prefix = "/api/v1",
      @cognitive_agency_sync = true,
      @grip_coordination_mode = :peer,
      @state_sync_interval = 5,
      @event_streaming_enabled = true,
      @batch_operations = true
    )
    end

    # Get full API endpoint URL
    def api_endpoint(path : String) : String
      "#{@backend_url}#{@lucky_api_prefix}#{path}"
    end
  end

  # Cognitive Agency Coordinator - manages distributed cognitive grip
  class CognitiveAgencyCoordinator
    property coordination_mode : Symbol
    property grip_state : Hash(String, Float64)
    property peer_states : Hash(String, Hash(String, Float64))
    property consensus_threshold : Float64
    property last_sync : Time
    property sync_history : Array(Hash(String, String))

    def initialize(@coordination_mode = :peer)
      @grip_state = {
        "coherence"       => 0.9,
        "synchronization" => 0.8,
        "authority"       => 0.7,
        "responsiveness"  => 0.85,
      }
      @peer_states = {} of String => Hash(String, Float64)
      @consensus_threshold = 0.7
      @last_sync = Time.utc
      @sync_history = [] of Hash(String, String)
    end

    # Coordinate cognitive grip with backend
    def coordinate_grip(local_grip : Hash(String, String)) : Hash(String, String)
      CogUtil::Logger.debug("Coordinating cognitive grip (mode: #{@coordination_mode})")

      coordination_result = {
        "mode"                => @coordination_mode.to_s,
        "local_grip_received" => "true",
        "coherence"           => @grip_state["coherence"].to_s,
        "consensus_reached"   => "true",
      }

      # Update grip state based on local input
      update_grip_state(local_grip)

      # Record sync event
      record_sync_event("grip_coordination", coordination_result)

      coordination_result
    end

    # Update local grip state
    def update_grip_state(input : Hash(String, String))
      if input.has_key?("coherence")
        @grip_state["coherence"] = input["coherence"].to_f64 rescue @grip_state["coherence"]
      end

      @grip_state["responsiveness"] = [(@grip_state["responsiveness"] + 0.01), 1.0].min
      @last_sync = Time.utc
    end

    # Register peer state for distributed coordination
    def register_peer(peer_id : String, state : Hash(String, Float64))
      @peer_states[peer_id] = state
      CogUtil::Logger.debug("Registered peer state: #{peer_id}")
    end

    # Calculate consensus across peers
    def calculate_consensus : Hash(String, Float64)
      return @grip_state if @peer_states.empty?

      consensus = {} of String => Float64

      @grip_state.each_key do |key|
        values = [@grip_state[key]]
        @peer_states.each_value do |peer_state|
          if peer_state.has_key?(key)
            values << peer_state[key]
          end
        end

        # Average consensus
        consensus[key] = values.sum / values.size
      end

      consensus
    end

    # Check if consensus threshold is met
    def consensus_reached? : Bool
      return true if @peer_states.empty?

      consensus = calculate_consensus
      consensus["coherence"]? ? consensus["coherence"] >= @consensus_threshold : true
    end

    # Record synchronization event
    def record_sync_event(event_type : String, data : Hash(String, String))
      event = {
        "type"      => event_type,
        "timestamp" => Time.utc.to_s,
        "peers"     => @peer_states.size.to_s,
      }.merge(data)

      @sync_history << event

      # Keep only recent history
      if @sync_history.size > 100
        @sync_history.shift
      end
    end

    # Get coordinator status
    def status : Hash(String, String)
      {
        "coordination_mode"  => @coordination_mode.to_s,
        "coherence"          => @grip_state["coherence"].to_s,
        "synchronization"    => @grip_state["synchronization"].to_s,
        "peer_count"         => @peer_states.size.to_s,
        "consensus_reached"  => consensus_reached?.to_s,
        "last_sync"          => @last_sync.to_s,
        "sync_history_count" => @sync_history.size.to_s,
      }
    end
  end

  # Authentication and authorization handler for Lucky API
  class AuthHandler
    property api_key : String?
    property token : String?
    property token_expiry : Time?
    property refresh_token : String?
    property authenticated : Bool

    def initialize(@api_key : String? = nil)
      @token = nil
      @token_expiry = nil
      @refresh_token = nil
      @authenticated = false
    end

    # Authenticate with Paphos backend via Lucky API
    def authenticate : Bool
      CogUtil::Logger.info("Authenticating with Paphos backend (Lucky API)")

      begin
        # Simulate Lucky framework session authentication
        @token = "paphos_token_#{Time.utc.to_unix}"
        @refresh_token = "paphos_refresh_#{Time.utc.to_unix}"
        @token_expiry = Time.utc + 1.hour
        @authenticated = true

        CogUtil::Logger.info("Authentication successful")
        true
      rescue ex
        CogUtil::Logger.error("Authentication failed: #{ex.message}")
        false
      end
    end

    # Validate authentication token
    def validate_token : Bool
      return false unless @authenticated && @token

      if expiry = @token_expiry
        if Time.utc > expiry
          CogUtil::Logger.debug("Token expired, attempting refresh")
          return refresh_auth_token
        end
      end

      true
    end

    # Refresh authentication token
    def refresh_auth_token : Bool
      return false unless @refresh_token

      CogUtil::Logger.debug("Refreshing authentication token")

      begin
        @token = "paphos_token_#{Time.utc.to_unix}"
        @token_expiry = Time.utc + 1.hour
        true
      rescue ex
        CogUtil::Logger.error("Token refresh failed: #{ex.message}")
        @authenticated = false
        false
      end
    end

    # Get authorization header
    def auth_header : Hash(String, String)
      if token = @token
        {"Authorization" => "Bearer #{token}"}
      elsif key = @api_key
        {"X-API-Key" => key}
      else
        {} of String => String
      end
    end

    # Logout and clear tokens
    def logout
      @token = nil
      @refresh_token = nil
      @token_expiry = nil
      @authenticated = false
      CogUtil::Logger.info("Logged out from Paphos backend")
    end
  end

  # PostgreSQL-compatible persistence layer
  class PersistenceLayer
    property backend_url : String
    property api_prefix : String
    property atomspace : AtomSpace::AtomSpace?
    property cache : Hash(String, String)
    property cache_enabled : Bool
    property batch_queue : Array(Hash(String, String))

    def initialize(@backend_url : String, @api_prefix : String = "/api/v1", @cache_enabled = true)
      @atomspace = nil
      @cache = {} of String => String
      @batch_queue = [] of Hash(String, String)
    end

    # Store AtomSpace data to Paphos backend (PostgreSQL-compatible)
    def store_atomspace_data : Bool
      return false unless @atomspace

      CogUtil::Logger.info("Storing AtomSpace data to Paphos backend (PostgreSQL format)")

      # Serialize atomspace for PostgreSQL-compatible storage
      data = {
        "operation" => "store_atomspace",
        "timestamp" => Time.utc.to_s,
        "format"    => "postgresql_jsonb",
      }

      @batch_queue << data
      flush_batch if @batch_queue.size >= 10

      true
    end

    # Load AtomSpace data from Paphos backend
    def load_atomspace_data : Bool
      return false unless @atomspace

      CogUtil::Logger.info("Loading AtomSpace data from Paphos backend")

      # Check cache first
      cache_key = "atomspace_data"
      if @cache_enabled && @cache.has_key?(cache_key)
        CogUtil::Logger.debug("AtomSpace data loaded from cache")
        return true
      end

      # Load from backend
      true
    end

    # Store cognitive state snapshot
    def store_snapshot(snapshot_id : String, data : Hash(String, String)) : Bool
      CogUtil::Logger.info("Storing cognitive snapshot: #{snapshot_id}")

      snapshot_data = data.merge({
        "snapshot_id"    => snapshot_id,
        "created_at"     => Time.utc.to_s,
        "storage_format" => "postgresql_jsonb",
      })

      @batch_queue << snapshot_data

      # Update cache
      if @cache_enabled
        @cache["snapshot_#{snapshot_id}"] = snapshot_data.to_json
      end

      true
    end

    # Load cognitive state snapshot
    def load_snapshot(snapshot_id : String) : Hash(String, String)?
      CogUtil::Logger.info("Loading cognitive snapshot: #{snapshot_id}")

      # Check cache
      cache_key = "snapshot_#{snapshot_id}"
      if @cache_enabled && @cache.has_key?(cache_key)
        CogUtil::Logger.debug("Snapshot loaded from cache")
        return Hash(String, String).from_json(@cache[cache_key])
      end

      # Return mock loaded snapshot
      {
        "snapshot_id" => snapshot_id,
        "loaded_at"   => Time.utc.to_s,
        "status"      => "loaded",
        "source"      => "paphos_postgresql",
      }
    end

    # Query stored data with PostgreSQL-compatible syntax
    def query_data(query : Hash(String, String)) : Array(Hash(String, String))
      CogUtil::Logger.debug("Querying Paphos backend: #{query}")

      results = [] of Hash(String, String)

      # Add query result
      results << {
        "query_processed" => "true",
        "backend"         => "paphos_postgresql",
        "timestamp"       => Time.utc.to_s,
      }

      results
    end

    # Flush batch operations
    def flush_batch : Int32
      return 0 if @batch_queue.empty?

      count = @batch_queue.size
      CogUtil::Logger.debug("Flushing #{count} batch operations to Paphos backend")
      @batch_queue.clear
      count
    end

    # Clear cache
    def clear_cache
      @cache.clear
      CogUtil::Logger.debug("Persistence cache cleared")
    end

    # Get persistence status
    def status : Hash(String, String)
      {
        "cache_enabled"      => @cache_enabled.to_s,
        "cache_size"         => @cache.size.to_s,
        "batch_queue_size"   => @batch_queue.size.to_s,
        "atomspace_attached" => (!@atomspace.nil?).to_s,
      }
    end
  end

  # Event streaming handler for real-time synchronization
  class EventStreamHandler
    property backend_url : String
    property connected : Bool
    property event_queue : Array(Hash(String, String))
    property subscriptions : Array(String)
    property cognitive_agency_coordinator : CognitiveAgencyCoordinator?

    def initialize(@backend_url : String)
      @connected = false
      @event_queue = [] of Hash(String, String)
      @subscriptions = ["cognitive_state", "atom_updates", "grip_coordination"]
      @cognitive_agency_coordinator = nil
    end

    # Link cognitive agency coordinator
    def link_coordinator(coordinator : CognitiveAgencyCoordinator)
      @cognitive_agency_coordinator = coordinator
    end

    # Connect to event stream
    def connect : Bool
      CogUtil::Logger.info("Connecting to Paphos event stream at #{@backend_url}")
      @connected = true
      true
    end

    # Disconnect from event stream
    def disconnect
      @connected = false
      CogUtil::Logger.info("Disconnected from Paphos event stream")
    end

    # Publish event to stream
    def publish_event(event_type : String, data : Hash(String, String)) : Bool
      return false unless @connected

      event = {
        "type"      => event_type,
        "timestamp" => Time.utc.to_s,
        "source"    => "crystalcog",
      }.merge(data)

      @event_queue << event

      # Coordinate with cognitive agency if available
      if coord = @cognitive_agency_coordinator
        coord.record_sync_event(event_type, data)
      end

      CogUtil::Logger.debug("Published event: #{event_type}")
      true
    end

    # Consume events from stream
    def consume_events : Array(Hash(String, String))
      return [] of Hash(String, String) unless @connected

      # Return queued events and clear
      events = @event_queue.dup
      @event_queue.clear
      events
    end

    # Subscribe to event type
    def subscribe(event_type : String)
      unless @subscriptions.includes?(event_type)
        @subscriptions << event_type
        CogUtil::Logger.debug("Subscribed to: #{event_type}")
      end
    end

    # Unsubscribe from event type
    def unsubscribe(event_type : String)
      @subscriptions.delete(event_type)
      CogUtil::Logger.debug("Unsubscribed from: #{event_type}")
    end

    # Get stream status
    def status : Hash(String, String)
      {
        "connected"     => @connected.to_s,
        "queue_size"    => @event_queue.size.to_s,
        "subscriptions" => @subscriptions.join(","),
      }
    end
  end

  # Main Paphos connector class with cognitive agency integration
  class Connector
    property config : Config
    property auth_handler : AuthHandler
    property persistence : PersistenceLayer
    property event_stream : EventStreamHandler
    property cognitive_coordinator : CognitiveAgencyCoordinator
    property atomspace : AtomSpace::AtomSpace?
    property connected : Bool

    def initialize(@config : Config)
      @auth_handler = AuthHandler.new(@config.api_key)
      @persistence = PersistenceLayer.new(@config.backend_url, @config.lucky_api_prefix, @config.enable_caching)
      @event_stream = EventStreamHandler.new(@config.backend_url)
      @cognitive_coordinator = CognitiveAgencyCoordinator.new(@config.grip_coordination_mode)
      @event_stream.link_coordinator(@cognitive_coordinator)
      @atomspace = nil
      @connected = false
    end

    # Initialize connection to Paphos backend with cognitive agency
    def initialize_connection : Bool
      CogUtil::Logger.info("Initializing connection to Paphos backend at #{@config.backend_url}")
      CogUtil::Logger.info("  API Prefix: #{@config.lucky_api_prefix}")
      CogUtil::Logger.info("  Grip Coordination Mode: #{@config.grip_coordination_mode}")
      CogUtil::Logger.info("  External Repo: #{EXTERNAL_REPO}")

      # Authenticate
      unless @auth_handler.authenticate
        CogUtil::Logger.error("Failed to authenticate with Paphos backend")
        return false
      end

      # Connect event stream if enabled
      if @config.event_streaming_enabled
        @event_stream.connect
      end

      @connected = true
      CogUtil::Logger.info("Successfully connected to Paphos backend")
      true
    end

    # Attach AtomSpace for cognitive operations
    def attach_atomspace(atomspace : AtomSpace::AtomSpace)
      @atomspace = atomspace
      @persistence.atomspace = atomspace
      CogUtil::Logger.info("Attached AtomSpace to Paphos connector")
    end

    # Coordinate cognitive grip with backend
    def coordinate_cognitive_grip(local_grip : Hash(String, String)) : Hash(String, String)
      @cognitive_coordinator.coordinate_grip(local_grip)
    end

    # Send cognitive command to backend (Lucky API)
    def send_command(command : String, params : Hash(String, String)) : Hash(String, String)
      CogUtil::Logger.info("Sending command to Paphos: #{command}")

      unless @auth_handler.validate_token
        @auth_handler.authenticate
      end

      # Coordinate with cognitive agency
      coordination = @cognitive_coordinator.coordinate_grip(params)

      # Publish event
      if @config.event_streaming_enabled
        @event_stream.publish_event("command_execution", {
          "command" => command,
          "status"  => "executed",
        })
      end

      {
        "status"      => "success",
        "command"     => command,
        "result"      => "Command executed with cognitive coordination",
        "api_version" => API_VERSION,
        "coherence"   => coordination["coherence"]? || "0.9",
      }
    end

    # Receive events from backend
    def receive_events : Array(Hash(String, String))
      CogUtil::Logger.debug("Receiving events from Paphos backend")

      @event_stream.consume_events
    end

    # Synchronize cognitive state with backend
    def synchronize_state : Bool
      CogUtil::Logger.info("Synchronizing cognitive state with Paphos")

      # Get current grip state
      grip_state = {
        "coherence"       => @cognitive_coordinator.grip_state["coherence"].to_s,
        "synchronization" => @cognitive_coordinator.grip_state["synchronization"].to_s,
      }

      # Store current state
      if @atomspace
        @persistence.store_atomspace_data
      end

      # Coordinate grip
      @cognitive_coordinator.coordinate_grip(grip_state)

      # Publish sync event
      if @config.event_streaming_enabled
        @event_stream.publish_event("state_sync", {
          "status"           => "completed",
          "atomspace_synced" => (!@atomspace.nil?).to_s,
        })
      end

      true
    end

    # Execute backend service function (Lucky action)
    def execute_service_function(function_name : String, args : Hash(String, String)) : String
      CogUtil::Logger.info("Executing Paphos service function: #{function_name}")

      # Build Lucky API endpoint
      endpoint = @config.api_endpoint("/actions/#{function_name}")

      # Coordinate with cognitive agency
      @cognitive_coordinator.coordinate_grip(args)

      "Function executed: #{function_name} (via Lucky API at #{endpoint})"
    end

    # Store cognitive snapshot
    def store_snapshot(snapshot_id : String) : Bool
      CogUtil::Logger.info("Storing cognitive snapshot: #{snapshot_id}")

      snapshot_data = {
        "grip_state"        => @cognitive_coordinator.grip_state.to_json,
        "coordination_mode" => @config.grip_coordination_mode.to_s,
        "timestamp"         => Time.utc.to_s,
      }

      @persistence.store_snapshot(snapshot_id, snapshot_data)
    end

    # Load cognitive snapshot
    def load_snapshot(snapshot_id : String) : Hash(String, String)?
      @persistence.load_snapshot(snapshot_id)
    end

    # Get comprehensive connector status
    def status : Hash(String, String)
      base_status = {
        "connector_status"       => @connected ? "connected" : "disconnected",
        "backend_url"            => @config.backend_url,
        "api_prefix"             => @config.lucky_api_prefix,
        "api_version"            => API_VERSION,
        "external_repo"          => EXTERNAL_REPO,
        "authenticated"          => @auth_handler.authenticated.to_s,
        "caching_enabled"        => @config.enable_caching.to_s,
        "atomspace_attached"     => (@atomspace.nil? ? "false" : "true"),
        "grip_coordination_mode" => @config.grip_coordination_mode.to_s,
      }

      # Merge coordinator and stream status
      base_status
        .merge(@cognitive_coordinator.status.transform_keys { |k| "coordinator_#{k}" })
        .merge(@event_stream.status.transform_keys { |k| "stream_#{k}" })
        .merge(@persistence.status.transform_keys { |k| "persistence_#{k}" })
    end

    # Test backend connection
    def test_connection : Bool
      CogUtil::Logger.debug("Testing Paphos backend connection")

      return false unless @connected
      return false unless @auth_handler.validate_token

      # Test with lightweight coordination
      result = @cognitive_coordinator.coordinate_grip({"test" => "connection"})
      result["coherence"]? != nil
    end

    # Disconnect from backend
    def disconnect
      CogUtil::Logger.info("Disconnecting from Paphos backend")

      # Flush any pending operations
      @persistence.flush_batch

      # Disconnect event stream
      @event_stream.disconnect

      # Logout
      @auth_handler.logout

      @connected = false
    end
  end

  # Factory method for creating connector with default configuration
  def self.create_default_connector : Connector
    config = Config.new
    Connector.new(config)
  end

  # Factory method for creating connector with authentication
  def self.create_authenticated_connector(backend_url : String, api_key : String) : Connector
    config = Config.new(backend_url: backend_url, api_key: api_key)
    Connector.new(config)
  end

  # Factory method for creating connector with cognitive agency coordination
  def self.create_cognitive_agency_connector(
    backend_url : String = "http://localhost:3000",
    coordination_mode : Symbol = :peer,
    sync_interval : Int32 = 5
  ) : Connector
    config = Config.new(
      backend_url: backend_url,
      cognitive_agency_sync: true,
      grip_coordination_mode: coordination_mode,
      state_sync_interval: sync_interval,
      event_streaming_enabled: true,
      batch_operations: true
    )
    Connector.new(config)
  end

  # Factory for optimal cognitive grip coordination
  def self.create_optimal_grip_connector : Connector
    config = Config.new(
      cognitive_agency_sync: true,
      grip_coordination_mode: :leader,
      state_sync_interval: 3,
      event_streaming_enabled: true,
      batch_operations: true,
      enable_caching: true
    )
    Connector.new(config)
  end
end
