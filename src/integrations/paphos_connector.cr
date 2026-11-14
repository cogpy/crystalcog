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
require "../atomspace/atomspace_main"
require "./platform/paphos_client"

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
    property email : String?
    property password : String?

    def initialize(
      @backend_url = ENV["PAPHOS_BACKEND_URL"]? || "http://localhost:3000",
      @api_key = ENV["PAPHOS_API_KEY"]?,
      @timeout = 30,
      @retry_attempts = 3,
      @enable_caching = true,
      @postgresql_compatible = true,
      @lucky_api_prefix = "/api/v1",
      @cognitive_agency_sync = true,
      @grip_coordination_mode = :peer,
      @state_sync_interval = 5,
      @event_streaming_enabled = true,
      @batch_operations = true,
      @email = ENV["PAPHOS_EMAIL"]?,
      @password = ENV["PAPHOS_PASSWORD"]?
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
    property client : PaphosBackend::Client?
    property email : String?
    property password : String?

    def initialize(@api_key : String? = nil, @client = nil, @email = nil, @password = nil)
      @token = nil
      @token_expiry = nil
      @refresh_token = nil
      @authenticated = false
    end

    # Log in to the Paphos backend (POST /api/v1/users/login). An api_key is
    # treated as a ready-made bearer token. Without either, stay
    # unauthenticated rather than inventing a token.
    def authenticate : Bool
      CogUtil::Logger.info("Authenticating with Paphos backend (Lucky API)")

      if (client = @client) && (email = @email) && (password = @password)
        @token = client.login(email, password)
      elsif key = @api_key
        @token = key
      else
        CogUtil::Logger.warn("No Paphos credentials configured (set PAPHOS_EMAIL/PAPHOS_PASSWORD or PAPHOS_API_KEY)")
        return false
      end
      @authenticated = true
      CogUtil::Logger.info("Authentication successful")
      true
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      CogUtil::Logger.error("Authentication failed: #{ex.message}")
      @authenticated = false
      false
    end

    # Paphos JWTs do not expire, so a token is valid until logout.
    def validate_token : Bool
      @authenticated && !@token.nil?
    end

    def refresh_auth_token : Bool
      authenticate
    end

    def auth_header : Hash(String, String)
      if token = @token
        {"Authorization" => "Bearer #{token}"}
      else
        {} of String => String
      end
    end

    def logout
      @token = nil
      @refresh_token = nil
      @token_expiry = nil
      @authenticated = false
      CogUtil::Logger.info("Logged out from Paphos backend")
    end
  end

  # Persistence through the Paphos backend's snapshot store: named
  # documents of string fields, owned by the authenticated user.
  #
  # Writes go straight to the backend. With `batch_writes`, or while no
  # client is attached, they wait in `batch_queue` until `flush_batch`
  # sends them; a queued write is still visible to `load_snapshot`.
  class PersistenceLayer
    ATOMSPACE_SNAPSHOT = "atomspace"
    ATOMSPACE_FORMAT   = "crystalcog-text-v1"
    BATCH_LIMIT        = 10

    property backend_url : String
    property api_prefix : String
    property atomspace : AtomSpace::AtomSpace?
    property cache : Hash(String, String)
    property cache_enabled : Bool
    property batch_queue : Array(Hash(String, String))
    property client : PaphosBackend::Client?
    property batch_writes : Bool = false
    getter last_error : String = ""

    def initialize(@backend_url : String, @api_prefix : String = "/api/v1", @cache_enabled = true)
      @atomspace = nil
      @cache = {} of String => String
      @batch_queue = [] of Hash(String, String)
      @client = nil
    end

    # Store the attached AtomSpace: every atom, with its truth value.
    def store_atomspace_data(snapshot_id : String = ATOMSPACE_SNAPSHOT) : Bool
      atomspace = @atomspace || return false

      CogUtil::Logger.info("Storing AtomSpace (#{atomspace.size} atoms) to Paphos backend")
      store_snapshot(snapshot_id, {
        "format"     => ATOMSPACE_FORMAT,
        "atom_count" => atomspace.size.to_s,
        "atoms"      => AtomSpace::Serialization.to_text(atomspace),
      })
    end

    # Load a stored AtomSpace into the attached one. False when nothing is
    # attached, nothing is stored, or the stored text cannot be read.
    def load_atomspace_data(snapshot_id : String = ATOMSPACE_SNAPSHOT) : Bool
      atomspace = @atomspace || return false

      snapshot = load_snapshot(snapshot_id) || return false
      unless snapshot["format"]? == ATOMSPACE_FORMAT && (atoms = snapshot["atoms"]?)
        @last_error = "snapshot #{snapshot_id} is not an AtomSpace export"
        return false
      end
      count = AtomSpace::Serialization.from_text(atomspace, atoms)
      CogUtil::Logger.info("Loaded #{count} atoms from Paphos backend")
      true
    rescue ex : AtomSpace::Serialization::ParseError
      @last_error = ex.message || "malformed AtomSpace export"
      false
    end

    # Store cognitive state snapshot
    def store_snapshot(snapshot_id : String, data : Hash(String, String)) : Bool
      snapshot_data = data.merge({
        "snapshot_id" => snapshot_id,
        "created_at"  => Time.utc.to_rfc3339,
      })
      @cache["snapshot_#{snapshot_id}"] = snapshot_data.to_json if @cache_enabled

      if @batch_writes || @client.nil?
        @batch_queue.reject! { |queued| queued["snapshot_id"]? == snapshot_id }
        @batch_queue << snapshot_data
        flush_batch if @client && @batch_queue.size >= BATCH_LIMIT
        true
      else
        write(snapshot_data)
      end
    end

    # Load cognitive state snapshot; nil when there is none.
    def load_snapshot(snapshot_id : String) : Hash(String, String)?
      cache_key = "snapshot_#{snapshot_id}"
      if @cache_enabled && (cached = @cache[cache_key]?)
        return Hash(String, String).from_json(cached)
      end
      if queued = @batch_queue.find { |entry| entry["snapshot_id"]? == snapshot_id }
        return queued
      end

      client = @client || return nil
      data = client.snapshot(snapshot_id) || return nil
      @cache[cache_key] = data.to_json if @cache_enabled
      data
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      @last_error = ex.message || ex.class.name
      nil
    end

    # Stored snapshots whose fields have the given values, as summaries
    # (snapshot_id, updated_at, bytes). An empty query lists them all.
    def query_data(query : Hash(String, String)) : Array(Hash(String, String))
      client = @client
      unless client
        return @batch_queue.select { |entry| query.all? { |field, value| entry[field]? == value } }
          .map { |entry| {"snapshot_id" => entry["snapshot_id"]? || "", "pending" => "true"} }
      end
      client.snapshots(query).map do |summary|
        {"snapshot_id" => summary["key"].as_s, "updated_at" => summary["updated_at"].as_i64.to_s,
         "bytes" => summary["bytes"].as_i64.to_s}
      end
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      @last_error = ex.message || ex.class.name
      [] of Hash(String, String)
    end

    def delete_snapshot(snapshot_id : String) : Bool
      @cache.delete("snapshot_#{snapshot_id}")
      @batch_queue.reject! { |queued| queued["snapshot_id"]? == snapshot_id }
      client = @client || return false
      client.delete_snapshot(snapshot_id)
      true
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      @last_error = ex.message || ex.class.name
      false
    end

    # Send the queued writes. Returns how many the backend accepted; the
    # rest stay queued.
    def flush_batch : Int32
      return 0 if @batch_queue.empty? || @client.nil?

      pending = @batch_queue.dup
      sent = pending.select { |entry| write(entry) }
      @batch_queue.reject! { |entry| sent.includes?(entry) }
      sent.size
    end

    private def write(snapshot_data : Hash(String, String)) : Bool
      client = @client || return false
      client.put_snapshot(snapshot_data["snapshot_id"], snapshot_data)
      true
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      @last_error = ex.message || ex.class.name
      CogUtil::Logger.error("Paphos snapshot write failed: #{@last_error}")
      false
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
        "backend_attached"   => (!@client.nil?).to_s,
      }
    end
  end

  # Event stream between this node and the Paphos backend.
  #
  # With a backend client attached, events are published to the backend's
  # `/events` and read back from it, so every client of the same account
  # sees them. Without one (offline, or before authentication) they are
  # queued in this process.
  class EventStreamHandler
    property backend_url : String
    property connected : Bool
    property event_queue : Array(Hash(String, String))
    property subscriptions : Array(String)
    property cognitive_agency_coordinator : CognitiveAgencyCoordinator?
    # Set once authenticated; nil keeps the stream local.
    property client : PaphosBackend::Client?
    # Id of the newest backend event already consumed.
    getter last_event_id : Int64 = 0_i64
    getter last_error : String?

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

    def remote? : Bool
      !@client.nil?
    end

    # Connect to event stream. Events published before a backend was
    # attached are sent to it now.
    def connect : Bool
      CogUtil::Logger.info("Connecting to Paphos event stream at #{@backend_url}")
      @connected = true
      flush_queue if remote?
      true
    end

    # Disconnect from event stream
    def disconnect
      stop_following
      @connected = false
      CogUtil::Logger.info("Disconnected from Paphos event stream")
    end

    # Publish event to stream. Returns false when the stream is closed or
    # the backend could not be reached; in the second case the event stays
    # queued for the next `connect` or `publish_event`.
    def publish_event(event_type : String, data : Hash(String, String)) : Bool
      return false unless @connected

      event = {
        "type"      => event_type,
        "timestamp" => Time.utc.to_s,
        "source"    => "crystalcog",
      }.merge(data)

      # Coordinate with cognitive agency if available
      if coord = @cognitive_agency_coordinator
        coord.record_sync_event(event_type, data)
      end

      @event_queue << event
      delivered = remote? ? flush_queue : true
      CogUtil::Logger.debug("Published event: #{event_type}")
      delivered
    end

    # Send queued events to the backend, oldest first. Stops at the first
    # failure so the order is kept.
    private def flush_queue : Bool
      client = @client || return false
      until @event_queue.empty?
        event = @event_queue.first
        data = event.reject("type", "source")
        client.publish_event(event["type"], data, event["source"]? || "crystalcog")
        @event_queue.shift
      end
      @last_error = nil
      true
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      @last_error = ex.message
      CogUtil::Logger.warn("Paphos event not delivered: #{ex.message}")
      false
    end

    # Consume events from stream: the events of this account that arrived
    # since the last call, from any client, each as flat string fields.
    # `wait` holds the request until one arrives. Offline, the events
    # queued in this process are returned and cleared.
    def consume_events(wait : Time::Span? = nil) : Array(Hash(String, String))
      return [] of Hash(String, String) unless @connected

      client = @client
      unless client
        events = @event_queue.dup
        @event_queue.clear
        return events
      end

      fetched = client.events(after: @last_event_id, wait: wait)
      fetched.map { |event| event_fields(event) }
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      @last_error = ex.message
      CogUtil::Logger.warn("Paphos events not read: #{ex.message}")
      [] of Hash(String, String)
    end

    # One backend event as flat string fields, counted as consumed.
    private def event_fields(event : JSON::Any) : Hash(String, String)
      @last_event_id = Math.max(@last_event_id, event["id"].as_i64)
      fields = {
        "type"      => event["type"].as_s,
        "source"    => event["source"].as_s,
        "id"        => event["id"].as_i64.to_s,
        "timestamp" => Time.unix_ms(event["created_at"].as_i64).to_s,
      }
      # The event's own fields; `timestamp` is the publisher's clock when
      # it sent one. The envelope's type, source and id are not overridden.
      event["data"].as_h.each do |key, value|
        fields[key] = value.as_s unless {"type", "source", "id"}.includes?(key)
      end
      fields
    end

    # The stream opened by `follow_events`, while it is open.
    getter follow : PaphosBackend::Client::EventFollow?

    # Have the block called with each event of this account as the backend
    # publishes it, starting after the last one consumed. Only the
    # subscribed types are sent unless `subscribed_only` is false. Returns
    # false without a backend, or when the stream could not be opened.
    # `consume_events` afterwards returns only what the block has not seen.
    def follow_events(subscribed_only : Bool = true, &block : Hash(String, String) ->) : Bool
      return false unless @connected
      client = @client || return false
      stop_following
      types = subscribed_only ? @subscriptions : nil
      @follow = client.follow_events(after: @last_event_id, types: types) do |event|
        block.call(event_fields(event))
      end
      @last_error = nil
      true
    rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
      @last_error = ex.message
      CogUtil::Logger.warn("Paphos events not followed: #{ex.message}")
      false
    end

    # True while the backend is sending this handler its events.
    def following? : Bool
      @follow.try { |follow| !follow.closed? } || false
    end

    def stop_following : Nil
      @follow.try(&.close)
      @follow = nil
    end

    # The consumed events whose type this handler subscribes to.
    def consume_subscribed(wait : Time::Span? = nil) : Array(Hash(String, String))
      consume_events(wait).select { |event| @subscriptions.includes?(event["type"]?) }
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
        "remote"        => remote?.to_s,
        "last_event_id" => @last_event_id.to_s,
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
    getter client : PaphosBackend::Client

    def initialize(@config : Config)
      @client = PaphosBackend::Client.new(@config.api_endpoint(""), timeout: @config.timeout.seconds)
      @auth_handler = AuthHandler.new(@config.api_key, @client, @config.email, @config.password)
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
      @client.token = @auth_handler.token
      # Persistence talks to the backend from here on; anything stored
      # while offline is sent now.
      @persistence.client = @client
      @persistence.batch_writes = @config.batch_operations
      @persistence.flush_batch unless @config.batch_operations

      # Connect event stream if enabled
      if @config.event_streaming_enabled
        @event_stream.client = @client
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

    # Send a command to the backend. Connected, the command is the name of
    # a backend action (`POST /actions/:name`) and `result` is what it
    # returned, as JSON; a refusal or an unknown command gives
    # `status: "error"` with the reason in `error`. Offline, the command is
    # only coordinated and recorded locally, and `status` is `"local"`.
    def send_command(command : String, params : Hash(String, String)) : Hash(String, String)
      CogUtil::Logger.info("Sending command to Paphos: #{command}")

      # Coordinate with cognitive agency
      coordination = @cognitive_coordinator.coordinate_grip(params)
      response = {
        "command"     => command,
        "api_version" => API_VERSION,
        "coherence"   => coordination["coherence"]? || "0.9",
      }

      unless @connected
        response["status"] = "local"
        response["result"] = "Not connected to a Paphos backend; the command was coordinated locally"
        return response
      end

      @auth_handler.authenticate unless @auth_handler.validate_token
      begin
        result = @client.call_action(command, params)
        response["status"] = "success"
        response["result"] = result.to_json
        result.each { |field, value| response["result.#{field}"] = value }
      rescue ex : PaphosBackend::Client::Error | IO::Error | Socket::Error
        response["status"] = "error"
        response["error"] = ex.message || ex.class.name
        response["result"] = ""
      end

      if @config.event_streaming_enabled
        @event_stream.publish_event("command_execution", {
          "command" => command,
          "status"  => response["status"],
        })
      end

      response
    end

    # The backend's service functions: name => description.
    def service_functions : Hash(String, String)
      return {} of String => String unless @connected
      @client.actions.to_h { |action| {action["name"].as_s, action["description"].as_s} }
    rescue PaphosBackend::Client::Error | IO::Error | Socket::Error
      {} of String => String
    end

    # Receive events from backend
    def receive_events(wait : Time::Span? = nil) : Array(Hash(String, String))
      CogUtil::Logger.debug("Receiving events from Paphos backend")

      @event_stream.consume_events(wait)
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

    # Execute a backend service function and return its result as JSON.
    # Raises `PaphosBackend::Client::Error` when the backend refuses or
    # does not know the function, and when there is no connection.
    def execute_service_function(function_name : String, args : Hash(String, String)) : String
      CogUtil::Logger.info("Executing Paphos service function: #{function_name}")
      raise PaphosBackend::Client::Error.new(503, "Not connected to a Paphos backend") unless @connected

      # Coordinate with cognitive agency
      @cognitive_coordinator.coordinate_grip(args)

      @auth_handler.authenticate unless @auth_handler.validate_token
      @client.call_action(function_name, args).to_json
    end

    # Store cognitive snapshot
    def store_snapshot(snapshot_id : String) : Bool
      CogUtil::Logger.info("Storing cognitive snapshot: #{snapshot_id}")

      snapshot_data = {
        "grip_state"        => @cognitive_coordinator.grip_state.to_json,
        "coordination_mode" => @config.grip_coordination_mode.to_s,
        "timestamp"         => Time.utc.to_s,
        "kind"              => "cognitive_state",
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

      # A real round trip: an authenticated read of the character list.
      @client.characters
      true
    rescue PaphosBackend::Client::Error | IO::Error | Socket::Error
      false
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
