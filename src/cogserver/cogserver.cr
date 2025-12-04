# Crystal implementation of OpenCog CogServer
# Converted from cogserver/opencog/cogserver components
#
# This provides a network server interface to the OpenCog system,
# allowing remote access to AtomSpace operations and reasoning capabilities.

require "socket"
require "http/server"
require "json"
require "base64"
require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../opencog/opencog"

module CogServer
  VERSION = "0.1.0"

  # Default configuration
  DEFAULT_PORT    = 17001
  DEFAULT_WS_PORT = 18080
  DEFAULT_HOST    = "localhost"

  # CogServer main class
  class Server
    getter host : String
    getter port : Int32
    getter ws_port : Int32
    getter atomspace : AtomSpace::AtomSpace

    @server : HTTP::Server?
    @ws_server : HTTP::Server?
    @running : Bool = false
    @sessions : Hash(String, Session)

    def initialize(@host : String = DEFAULT_HOST, @port : Int32 = DEFAULT_PORT, @ws_port : Int32 = DEFAULT_WS_PORT)
      @atomspace = AtomSpace::AtomSpace.new
      @sessions = Hash(String, Session).new

      CogUtil::Logger.info("CogServer #{VERSION} initializing")
      CogUtil::Logger.info("Telnet server will listen on #{@host}:#{@port}")
      CogUtil::Logger.info("WebSocket server will listen on #{@host}:#{@ws_port}")
    end

    # Start the server
    def start
      return if @running

      @running = true
      CogUtil::Logger.info("Starting CogServer...")

      # Start telnet server in a fiber
      spawn do
        start_telnet_server
      end

      # Start WebSocket server in a fiber
      spawn do
        start_websocket_server
      end

      CogUtil::Logger.info("CogServer started successfully")
    end

    # Stop the server
    def stop
      return unless @running

      @running = false
      CogUtil::Logger.info("Stopping CogServer...")

      @server.try(&.close)
      @ws_server.try(&.close)

      @sessions.each_value(&.close)
      @sessions.clear

      CogUtil::Logger.info("CogServer stopped")
    end

    # Check if server is running
    def running?
      @running
    end

    # Get server statistics
    def stats
      {
        "running"         => @running,
        "host"            => @host,
        "port"            => @port,
        "ws_port"         => @ws_port,
        "active_sessions" => @sessions.size,
        "atomspace_size"  => @atomspace.size,
        "atomspace_nodes" => @atomspace.node_count,
        "atomspace_links" => @atomspace.link_count,
      }
    end

    private def start_telnet_server
      @server = HTTP::Server.new do |context|
        handle_telnet_request(context)
      end

      address = @server.not_nil!.bind_tcp(@host, @port)
      CogUtil::Logger.info("Telnet server listening on #{address}")

      @server.not_nil!.listen
    rescue ex
      CogUtil::Logger.error("Telnet server error: #{ex.message}")
    end

    private def start_websocket_server
      @ws_server = HTTP::Server.new do |context|
        handle_websocket_request(context)
      end

      address = @ws_server.not_nil!.bind_tcp(@host, @ws_port)
      CogUtil::Logger.info("WebSocket server listening on #{address}")

      @ws_server.not_nil!.listen
    rescue ex
      CogUtil::Logger.error("WebSocket server error: #{ex.message}")
    end

    private def handle_telnet_request(context)
      session_id = generate_session_id
      session = Session.new(session_id, @atomspace, :telnet)
      @sessions[session_id] = session

      context.response.content_type = "text/plain"
      context.response.print("Welcome to CogServer #{VERSION}\n")
      context.response.print("Session ID: #{session_id}\n")
      context.response.print("AtomSpace contains #{@atomspace.size} atoms\n")
      context.response.print("Type 'help' for available commands\n")
      context.response.print("cog> ")

      # Handle basic command processing
      # Note: This is a simplified implementation for HTTP-based telnet simulation
      # Real telnet would require persistent TCP connection with command parsing
      query = context.request.query_params["cmd"]?
      if query
        output = process_telnet_command(query, session)
        context.response.print("\n#{output}\ncog> ")
      else
        context.response.print("\n[Send commands via ?cmd=your_command parameter]\n")
      end
    rescue ex
      CogUtil::Logger.error("Telnet request error: #{ex.message}")
      context.response.status_code = 500
      context.response.print("Internal server error: #{ex.message}")
    end

    private def process_telnet_command(command : String, session : Session) : String
      case command.strip.downcase
      when "help"
        <<-HELP
        Available commands:
        help          - Show this help message
        info          - Show server information
        atomspace     - Show AtomSpace statistics
        list          - List atoms in AtomSpace
        stats         - Show session statistics
        quit, exit    - Close session
        HELP
      when "info"
        "CogServer #{VERSION} - Host: #{@host}, Port: #{@port}, WebSocket: #{@ws_port}"
      when "atomspace"
        "AtomSpace: #{@atomspace.size} atoms (#{@atomspace.node_count} nodes, #{@atomspace.link_count} links)"
      when "list"
        atoms = @atomspace.get_atoms_by_type(AtomSpace::AtomType::ATOM)
        if atoms.empty?
          "AtomSpace is empty"
        else
          "Atoms in AtomSpace:\n" + atoms.first(10).map_with_index { |atom, i| "#{i + 1}. #{atom}" }.join("\n") +
            (atoms.size > 10 ? "\n... and #{atoms.size - 10} more" : "")
        end
      when "stats"
        "Session #{session.id} (#{session.session_type}), Active: #{session.duration.total_seconds.round(1)}s"
      when "quit", "exit"
        session.close
        "Session closed. Goodbye!"
      else
        "Unknown command: #{command}. Type 'help' for available commands."
      end
    rescue ex
      "Command error: #{ex.message}"
    end

    private def handle_websocket_request(context)
      if context.request.headers["Upgrade"]? == "websocket"
        handle_websocket_upgrade(context)
      else
        handle_http_api(context)
      end
    end

    private def handle_websocket_upgrade(context)
      # Check for proper WebSocket upgrade headers
      if context.request.headers["Connection"]?.try(&.downcase.includes?("upgrade")) &&
         context.request.headers["Upgrade"]?.try(&.downcase) == "websocket"
        # Basic WebSocket handshake
        websocket_key = context.request.headers["Sec-WebSocket-Key"]?
        if websocket_key.nil?
          context.response.status_code = 400
          context.response.content_type = "application/json"
          context.response.print({"error" => "Missing WebSocket key"}.to_json)
          return
        end

        # Create session for WebSocket
        session_id = generate_session_id
        session = Session.new(session_id, @atomspace, :websocket)
        @sessions[session_id] = session

        # Generate WebSocket accept key (simplified)
        websocket_magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        accept_key = Base64.strict_encode("#{websocket_key}#{websocket_magic}")

        # Send WebSocket upgrade response
        context.response.status_code = 101
        context.response.headers["Upgrade"] = "websocket"
        context.response.headers["Connection"] = "Upgrade"
        context.response.headers["Sec-WebSocket-Accept"] = accept_key
        context.response.headers["Sec-WebSocket-Protocol"] = "json"

        CogUtil::Logger.info("WebSocket connection established for session #{session_id}")

        # Note: In a full implementation, this would handle the WebSocket frames
        # For now, we establish the connection successfully
      else
        context.response.status_code = 400
        context.response.content_type = "application/json"
        context.response.print({"error" => "Invalid WebSocket upgrade request"}.to_json)
      end
    rescue ex
      CogUtil::Logger.error("WebSocket upgrade error: #{ex.message}")
      context.response.status_code = 500
      context.response.content_type = "application/json"
      context.response.print({"error" => "WebSocket upgrade failed"}.to_json)
    end

    private def handle_http_api(context)
      case context.request.path
      when "/status"
        handle_status_request(context)
      when "/atomspace"
        handle_atomspace_request(context)
      when "/atoms"
        handle_atoms_request(context)
      when "/sessions"
        handle_sessions_request(context)
      when "/ping"
        handle_ping_request(context)
      when "/version"
        handle_version_request(context)
      when "/storage"
        handle_storage_request(context)
      when "/storage/save"
        handle_storage_save_request(context)
      when "/storage/load"
        handle_storage_load_request(context)
      when "/storage/attach"
        handle_storage_attach_request(context)
      when "/storage/detach"
        handle_storage_detach_request(context)
      else
        context.response.status_code = 404
        context.response.content_type = "application/json"
        context.response.print({"error" => "Not found"}.to_json)
      end
    rescue ex
      CogUtil::Logger.error("HTTP API error: #{ex.message}")
      context.response.status_code = 500
      context.response.content_type = "application/json"
      context.response.print({"error" => "Internal server error"}.to_json)
    end

    private def handle_status_request(context)
      context.response.content_type = "application/json"
      context.response.print(stats.to_json)
    end

    private def handle_atomspace_request(context)
      case context.request.method
      when "GET"
        atoms = @atomspace.get_atoms_by_type(AtomSpace::AtomType::ATOM)
        response = {
          "size"  => @atomspace.size,
          "nodes" => @atomspace.node_count,
          "links" => @atomspace.link_count,
          "atoms" => atoms.map(&.to_s),
        }
        context.response.content_type = "application/json"
        context.response.print(response.to_json)
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def handle_atoms_request(context)
      case context.request.method
      when "GET"
        # Get atoms with optional filtering
        type_param = context.request.query_params["type"]?

        atoms = if type_param
                  begin
                    atom_type = AtomSpace::AtomType.parse(type_param)
                    @atomspace.get_atoms_by_type(atom_type)
                  rescue
                    [] of AtomSpace::Atom
                  end
                else
                  @atomspace.get_atoms_by_type(AtomSpace::AtomType::ATOM)
                end

        response = {
          "count" => atoms.size,
          "atoms" => atoms.map { |atom|
            {
              "type"        => atom.type.to_s,
              "name"        => atom.responds_to?(:name) ? atom.name : nil,
              "outgoing"    => atom.responds_to?(:outgoing) ? atom.outgoing.map(&.to_s) : nil,
              "truth_value" => {
                "strength"   => atom.truth_value.strength,
                "confidence" => atom.truth_value.confidence,
              },
              "string" => atom.to_s,
            }
          },
        }

        context.response.content_type = "application/json"
        context.response.print(response.to_json)
      when "POST"
        # Create new atom
        handle_create_atom(context)
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def handle_create_atom(context)
      begin
        body = context.request.body.try(&.gets_to_end) || ""
        data = JSON.parse(body)

        type_str = data["type"].as_s
        atom_type = AtomSpace::AtomType.parse(type_str)

        if atom_type.node?
          name = data["name"].as_s
          atom = @atomspace.add_node(atom_type, name)
        else
          outgoing_data = data["outgoing"].as_a
          # This is simplified - would need proper atom resolution
          outgoing = [] of AtomSpace::Atom
          atom = @atomspace.add_link(atom_type, outgoing)
        end

        response = {
          "success" => true,
          "atom"    => {
            "type"   => atom.type.to_s,
            "string" => atom.to_s,
          },
        }

        context.response.status_code = 201
        context.response.content_type = "application/json"
        context.response.print(response.to_json)
      rescue ex
        context.response.status_code = 400
        context.response.content_type = "application/json"
        context.response.print({"error" => "Invalid request: #{ex.message}"}.to_json)
      end
    end

    private def handle_sessions_request(context)
      case context.request.method
      when "GET"
        sessions_data = @sessions.map do |id, session|
          {
            "id"         => id,
            "type"       => session.session_type.to_s,
            "created_at" => session.created_at.to_rfc3339,
            "duration"   => session.duration.total_seconds.round(1),
            "closed"     => session.closed?,
          }
        end

        response = {
          "active_sessions" => @sessions.size,
          "sessions"        => sessions_data,
        }

        context.response.content_type = "application/json"
        context.response.print(response.to_json)
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def handle_ping_request(context)
      context.response.content_type = "application/json"
      context.response.print({
        "status"    => "ok",
        "timestamp" => Time.utc.to_rfc3339,
        "server"    => "CogServer #{VERSION}",
      }.to_json)
    end

    private def handle_version_request(context)
      context.response.content_type = "application/json"
      context.response.print({
        "version"         => VERSION,
        "crystal_version" => Crystal::VERSION,
        "server_type"     => "CogServer",
        "api_version"     => "1.0",
      }.to_json)
    end

    # New persistence endpoints
    private def handle_storage_request(context)
      case context.request.method
      when "GET"
        # Get list of attached storage nodes
        storages = @atomspace.get_attached_storages
        response = {
          "storage_count" => storages.size,
          "storages"      => storages.map do |storage|
            stats = storage.get_stats
            {
              "name"      => storage.name,
              "type"      => stats["type"]?,
              "connected" => stats["connected"]?,
              "stats"     => stats,
            }
          end,
        }
        context.response.content_type = "application/json"
        context.response.print(response.to_json)
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def handle_storage_save_request(context)
      case context.request.method
      when "POST"
        begin
          body = context.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          if storage_name = data["storage"]?.try(&.as_s)
            # Save to specific storage
            storage = @atomspace.get_attached_storages.find { |s| s.name == storage_name }
            if storage
              success = @atomspace.store_to(storage)
              status_code = success ? 200 : 500
              response = {
                "success" => success,
                "message" => success ? "AtomSpace saved to #{storage_name}" : "Failed to save to #{storage_name}",
                "storage" => storage_name,
              }
            else
              status_code = 404
              response = {"error" => "Storage not found: #{storage_name}"}
            end
          else
            # Save to all attached storages
            success = @atomspace.store_all
            status_code = success ? 200 : 500
            response = {
              "success"       => success,
              "message"       => success ? "AtomSpace saved to all storages" : "Failed to save to some storages",
              "storage_count" => @atomspace.get_attached_storages.size,
            }
          end

          context.response.status_code = status_code
          context.response.content_type = "application/json"
          context.response.print(response.to_json)
        rescue ex
          context.response.status_code = 400
          context.response.content_type = "application/json"
          context.response.print({"error" => "Invalid request: #{ex.message}"}.to_json)
        end
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def handle_storage_load_request(context)
      case context.request.method
      when "POST"
        begin
          body = context.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          if storage_name = data["storage"]?.try(&.as_s)
            # Load from specific storage
            storage = @atomspace.get_attached_storages.find { |s| s.name == storage_name }
            if storage
              success = @atomspace.load_from(storage)
              status_code = success ? 200 : 500
              response = {
                "success"        => success,
                "message"        => success ? "AtomSpace loaded from #{storage_name}" : "Failed to load from #{storage_name}",
                "storage"        => storage_name,
                "atomspace_size" => @atomspace.size,
              }
            else
              status_code = 404
              response = {"error" => "Storage not found: #{storage_name}"}
            end
          else
            # Load from all attached storages
            success = @atomspace.load_all
            status_code = success ? 200 : 500
            response = {
              "success"        => success,
              "message"        => success ? "AtomSpace loaded from all storages" : "Failed to load from some storages",
              "storage_count"  => @atomspace.get_attached_storages.size,
              "atomspace_size" => @atomspace.size,
            }
          end

          context.response.status_code = status_code
          context.response.content_type = "application/json"
          context.response.print(response.to_json)
        rescue ex
          context.response.status_code = 400
          context.response.content_type = "application/json"
          context.response.print({"error" => "Invalid request: #{ex.message}"}.to_json)
        end
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def handle_storage_attach_request(context)
      case context.request.method
      when "POST"
        begin
          body = context.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          storage_type = data["type"].as_s
          storage_name = data["name"].as_s

          storage = case storage_type.downcase
                    when "file"
                      file_path = data["path"].as_s
                      file_storage = AtomSpace::FileStorageNode.new(storage_name, file_path)
                      file_storage.open if file_storage
                      file_storage
                    when "sqlite"
                      db_path = data["path"].as_s
                      sqlite_storage = AtomSpace::SQLiteStorageNode.new(storage_name, db_path)
                      sqlite_storage.open if sqlite_storage
                      sqlite_storage
                    when "cog", "network"
                      host = data["host"].as_s
                      port = data["port"].as_i
                      cog_storage = AtomSpace::CogStorageNode.new(storage_name, host, port)
                      cog_storage.open if cog_storage
                      cog_storage
                    else
                      nil
                    end

          if storage
            @atomspace.attach_storage(storage)
            response = {
              "success" => true,
              "message" => "Storage attached successfully",
              "storage" => {
                "name"      => storage.name,
                "type"      => storage_type,
                "connected" => storage.connected?,
              },
            }
            context.response.status_code = 201
          else
            response = {"error" => "Unsupported storage type: #{storage_type}"}
            context.response.status_code = 400
          end

          context.response.content_type = "application/json"
          context.response.print(response.to_json)
        rescue ex
          context.response.status_code = 400
          context.response.content_type = "application/json"
          context.response.print({"error" => "Invalid request: #{ex.message}"}.to_json)
        end
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def handle_storage_detach_request(context)
      case context.request.method
      when "POST"
        begin
          body = context.request.body.try(&.gets_to_end) || "{}"
          data = JSON.parse(body)

          storage_name = data["name"].as_s
          storage = @atomspace.get_attached_storages.find { |s| s.name == storage_name }

          if storage
            storage.close
            @atomspace.detach_storage(storage)
            response = {
              "success" => true,
              "message" => "Storage detached successfully",
              "storage" => storage_name,
            }
            context.response.status_code = 200
          else
            response = {"error" => "Storage not found: #{storage_name}"}
            context.response.status_code = 404
          end

          context.response.content_type = "application/json"
          context.response.print(response.to_json)
        rescue ex
          context.response.status_code = 400
          context.response.content_type = "application/json"
          context.response.print({"error" => "Invalid request: #{ex.message}"}.to_json)
        end
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def generate_session_id
      chars = "0123456789abcdef"
      String.build(16) do |io|
        16.times { io << chars[Random.rand(chars.size)] }
      end
    end
  end

  # Session management for client connections
  class Session
    getter id : String
    getter atomspace : AtomSpace::AtomSpace
    getter session_type : Symbol
    getter created_at : Time

    @closed : Bool = false

    def initialize(@id : String, @atomspace : AtomSpace::AtomSpace, @session_type : Symbol)
      @created_at = Time.utc
      CogUtil::Logger.info("Session #{@id} created (#{@session_type})")
    end

    def close
      return if @closed
      @closed = true
      CogUtil::Logger.info("Session #{@id} closed")
    end

    def closed?
      @closed
    end

    def duration
      Time.utc - @created_at
    end
  end

  # Initialize the CogServer subsystem
  def self.initialize
    CogUtil::Logger.info("CogServer #{VERSION} initializing")

    # Initialize dependencies
    CogUtil.initialize
    AtomSpace.initialize
    OpenCog.initialize

    CogUtil::Logger.info("CogServer #{VERSION} initialized")
  end

  # Exception classes for CogServer
  class CogServerException < CogUtil::OpenCogException
  end

  class NetworkException < CogServerException
  end

  class SessionException < CogServerException
  end

  # WebSocket real-time monitoring client
  class WebSocketMonitor
    property session_id : String
    property subscriptions : Set(String)
    property created_at : Time
    property last_activity : Time
    @closed : Bool = false

    def initialize(@session_id : String)
      @subscriptions = Set(String).new
      @created_at = Time.utc
      @last_activity = Time.utc
    end

    def subscribe(event_type : String)
      @subscriptions.add(event_type)
      @last_activity = Time.utc
    end

    def unsubscribe(event_type : String)
      @subscriptions.delete(event_type)
      @last_activity = Time.utc
    end

    def subscribed_to?(event_type : String) : Bool
      @subscriptions.includes?(event_type) || @subscriptions.includes?("*")
    end

    def touch
      @last_activity = Time.utc
    end

    def close
      @closed = true
    end

    def closed? : Bool
      @closed
    end
  end

  # Event types for real-time monitoring
  enum MonitorEventType
    AtomAdded
    AtomRemoved
    AtomUpdated
    TruthValueChanged
    AttentionChanged
    StorageAttached
    StorageDetached
    ServerStats
    AtomSpaceStats
    Heartbeat
  end

  # Real-time event for WebSocket broadcasting
  struct MonitorEvent
    property event_type : MonitorEventType
    property timestamp : Time
    property data : Hash(String, JSON::Any)

    def initialize(@event_type : MonitorEventType, @data : Hash(String, JSON::Any) = Hash(String, JSON::Any).new)
      @timestamp = Time.utc
    end

    def to_json(io : IO)
      {
        "type"      => @event_type.to_s,
        "timestamp" => @timestamp.to_rfc3339,
        "data"      => @data,
      }.to_json(io)
    end
  end

  # WebSocket event broadcaster for real-time monitoring
  class EventBroadcaster
    @monitors : Hash(String, WebSocketMonitor)
    @event_queue : Channel(MonitorEvent)
    @running : Bool = false
    @mutex : Mutex

    def initialize
      @monitors = Hash(String, WebSocketMonitor).new
      @event_queue = Channel(MonitorEvent).new(1000)
      @mutex = Mutex.new
    end

    def start
      return if @running
      @running = true

      # Start event processing fiber
      spawn do
        process_events
      end

      # Start heartbeat fiber
      spawn do
        send_heartbeats
      end

      CogUtil::Logger.info("EventBroadcaster started")
    end

    def stop
      @running = false
      CogUtil::Logger.info("EventBroadcaster stopped")
    end

    def running? : Bool
      @running
    end

    def register_monitor(session_id : String) : WebSocketMonitor
      @mutex.synchronize do
        monitor = WebSocketMonitor.new(session_id)
        @monitors[session_id] = monitor
        CogUtil::Logger.debug("WebSocket monitor registered: #{session_id}")
        monitor
      end
    end

    def unregister_monitor(session_id : String)
      @mutex.synchronize do
        if monitor = @monitors.delete(session_id)
          monitor.close
          CogUtil::Logger.debug("WebSocket monitor unregistered: #{session_id}")
        end
      end
    end

    def get_monitor(session_id : String) : WebSocketMonitor?
      @monitors[session_id]?
    end

    def broadcast(event : MonitorEvent)
      @event_queue.send(event) if @running
    end

    def broadcast_atom_added(atom : AtomSpace::Atom)
      data = Hash(String, JSON::Any).new
      data["handle"] = JSON::Any.new(atom.handle.to_i64)
      data["type"] = JSON::Any.new(atom.type.to_s)
      data["name"] = JSON::Any.new(atom.responds_to?(:name) ? atom.name : "")
      data["truth_value"] = JSON::Any.new({
        "strength"   => JSON::Any.new(atom.truth_value.strength),
        "confidence" => JSON::Any.new(atom.truth_value.confidence),
      })
      broadcast(MonitorEvent.new(MonitorEventType::AtomAdded, data))
    end

    def broadcast_atom_removed(atom : AtomSpace::Atom)
      data = Hash(String, JSON::Any).new
      data["handle"] = JSON::Any.new(atom.handle.to_i64)
      data["type"] = JSON::Any.new(atom.type.to_s)
      broadcast(MonitorEvent.new(MonitorEventType::AtomRemoved, data))
    end

    def broadcast_server_stats(stats : Hash)
      data = Hash(String, JSON::Any).new
      stats.each do |key, value|
        data[key.to_s] = JSON::Any.new(value.to_s)
      end
      broadcast(MonitorEvent.new(MonitorEventType::ServerStats, data))
    end

    def broadcast_atomspace_stats(atomspace : AtomSpace::AtomSpace)
      data = Hash(String, JSON::Any).new
      data["size"] = JSON::Any.new(atomspace.size.to_i64)
      data["nodes"] = JSON::Any.new(atomspace.node_count.to_i64)
      data["links"] = JSON::Any.new(atomspace.link_count.to_i64)
      broadcast(MonitorEvent.new(MonitorEventType::AtomSpaceStats, data))
    end

    def active_monitors : Int32
      @monitors.size
    end

    def get_all_monitors : Array(WebSocketMonitor)
      @monitors.values
    end

    private def process_events
      while @running
        select
        when event = @event_queue.receive
          dispatch_event(event)
        when timeout(100.milliseconds)
          # Cleanup stale monitors periodically
          cleanup_stale_monitors
        end
      end
    end

    private def dispatch_event(event : MonitorEvent)
      event_type_str = event.event_type.to_s
      @mutex.synchronize do
        @monitors.each_value do |monitor|
          next if monitor.closed?
          if monitor.subscribed_to?(event_type_str)
            # In a full implementation, this would send to the WebSocket connection
            # For now, we log the event dispatch
            CogUtil::Logger.debug("Event dispatched to #{monitor.session_id}: #{event_type_str}")
          end
        end
      end
    end

    private def send_heartbeats
      while @running
        sleep 10.seconds
        data = Hash(String, JSON::Any).new
        data["active_monitors"] = JSON::Any.new(@monitors.size.to_i64)
        broadcast(MonitorEvent.new(MonitorEventType::Heartbeat, data))
      end
    end

    private def cleanup_stale_monitors
      stale_timeout = 5.minutes
      now = Time.utc
      @mutex.synchronize do
        @monitors.reject! do |session_id, monitor|
          if monitor.closed? || (now - monitor.last_activity) > stale_timeout
            CogUtil::Logger.debug("Cleaning up stale monitor: #{session_id}")
            true
          else
            false
          end
        end
      end
    end
  end

  # Metrics collector for real-time monitoring
  class MetricsCollector
    @atomspace : AtomSpace::AtomSpace?
    @broadcaster : EventBroadcaster?
    @collection_interval : Time::Span
    @running : Bool = false

    def initialize(@collection_interval : Time::Span = 5.seconds)
    end

    def attach(atomspace : AtomSpace::AtomSpace, broadcaster : EventBroadcaster)
      @atomspace = atomspace
      @broadcaster = broadcaster
    end

    def start
      return if @running
      @running = true

      spawn do
        collect_metrics_loop
      end

      CogUtil::Logger.info("MetricsCollector started with #{@collection_interval.total_seconds}s interval")
    end

    def stop
      @running = false
      CogUtil::Logger.info("MetricsCollector stopped")
    end

    def running? : Bool
      @running
    end

    private def collect_metrics_loop
      while @running
        sleep @collection_interval
        collect_and_broadcast
      end
    end

    private def collect_and_broadcast
      atomspace = @atomspace
      broadcaster = @broadcaster
      return unless atomspace && broadcaster

      broadcaster.broadcast_atomspace_stats(atomspace)
    end
  end
end
