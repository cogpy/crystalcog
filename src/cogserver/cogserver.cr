# Crystal implementation of OpenCog CogServer
# Converted from cogserver/opencog/cogserver components
#
# This provides a network server interface to the OpenCog system,
# allowing remote access to AtomSpace operations and reasoning capabilities.

require "socket"
require "http/server"
require "http/web_socket"
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

    getter broadcaster : EventBroadcaster

    # How long a new connection on the telnet port may stay silent before it
    # is treated as an interactive shell (HTTP clients speak first).
    TELNET_SNIFF_TIMEOUT = 300.milliseconds
    HTTP_METHODS         = {"GET ", "POST ", "HEAD ", "PUT ", "DELETE ", "OPTIONS ", "PATCH "}

    @server : TCPServer?
    @ws_server : HTTP::Server?
    @running : Bool = false
    @sessions : Hash(String, Session)
    @sessions_mutex = Mutex.new
    @shell_mutex = Mutex.new
    @shell : Proc(String, String)?

    # Builds the command shell for a server's AtomSpace. The AtomSpace core
    # reaches this file through the cluster code, so the shell (PLN, URE,
    # NLP, vision) is not required here: requiring "cogserver_shell"
    # installs it. Without it only the built-in server commands exist.
    class_property shell_factory : Proc(AtomSpace::AtomSpace, Proc(String, String))?
    @metrics : MetricsCollector
    @observer : AtomSpace::AtomSpaceSignal?
    @telnet_http : HTTP::Server::RequestProcessor?

    def initialize(@host : String = DEFAULT_HOST, @port : Int32 = DEFAULT_PORT, @ws_port : Int32 = DEFAULT_WS_PORT)
      @atomspace = AtomSpace::AtomSpace.new
      @sessions = Hash(String, Session).new
      @shell = Server.shell_factory.try(&.call(@atomspace))
      @broadcaster = EventBroadcaster.new
      @metrics = MetricsCollector.new

      CogUtil::Logger.info("CogServer #{VERSION} initializing")
      CogUtil::Logger.info("Telnet server will listen on #{@host}:#{@port}")
      CogUtil::Logger.info("WebSocket server will listen on #{@host}:#{@ws_port}")
    end

    # Start the server
    def start
      return if @running

      @running = true
      CogUtil::Logger.info("Starting CogServer...")

      # AtomSpace changes become monitor events for WebSocket subscribers.
      @broadcaster.start
      broadcaster = @broadcaster
      observer = AtomSpace::AtomSpaceSignal.new do |event, atom|
        case event
        when .atom_added?              then broadcaster.broadcast_atom_added(atom)
        when .atom_removed?            then broadcaster.broadcast_atom_removed(atom)
        when .truth_value_changed?     then broadcaster.broadcast_atom_changed(MonitorEventType::TruthValueChanged, atom)
        when .attention_value_changed? then broadcaster.broadcast_atom_changed(MonitorEventType::AttentionChanged, atom)
        end
        nil
      end
      @observer = observer
      @atomspace.add_observer(observer)
      @metrics.attach(@atomspace, @broadcaster)
      @metrics.start

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

      @metrics.stop
      @observer.try { |observer| @atomspace.remove_observer(observer) }
      @observer = nil
      @broadcaster.stop

      @sessions_mutex.synchronize do
        @sessions.each_value(&.close)
        @sessions.clear
      end

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

    # The telnet port speaks two protocols. A client that stays silent, or
    # whose first bytes are not an HTTP request line, gets an interactive
    # line-based shell (`telnet host 17001`, `nc`). A client that opens with
    # an HTTP request gets the one-shot `?cmd=` interface.
    private def start_telnet_server
      server = TCPServer.new(@host, @port)
      @server = server
      @telnet_http = HTTP::Server::RequestProcessor.new { |context| handle_telnet_request(context) }
      CogUtil::Logger.info("Telnet server listening on #{server.local_address}")

      while @running
        socket = server.accept? || break
        spawn handle_telnet_connection(socket)
      end
    rescue ex
      CogUtil::Logger.error("Telnet server error: #{ex.message}") if @running
    end

    private def handle_telnet_connection(socket : TCPSocket)
      socket.read_timeout = TELNET_SNIFF_TIMEOUT
      first = begin
        socket.peek
      rescue IO::TimeoutError
        nil
      end
      socket.read_timeout = nil

      if first && http_request?(first)
        @telnet_http.try(&.process(socket, socket))
      elsif first.nil? || !first.empty? # silent client, or one that already typed a command
        run_telnet_session(socket)
      end
    rescue ex : IO::Error
      CogUtil::Logger.debug("Telnet connection closed: #{ex.message}")
    ensure
      socket.close rescue nil
    end

    private def http_request?(bytes : Bytes) : Bool
      head = String.new(bytes[0, Math.min(bytes.size, 8)])
      HTTP_METHODS.any? { |method| head.starts_with?(method) }
    end

    private def run_telnet_session(socket : TCPSocket)
      session = open_session(:telnet)
      socket << "Welcome to CogServer #{VERSION}\r\n"
      socket << "Session ID: #{session.id}\r\n"
      socket << "AtomSpace contains #{@atomspace.size} atoms\r\n"
      socket << "Type 'help' for available commands\r\n"
      until session.closed? || !@running
        socket << "cog> "
        socket.flush
        line = socket.gets || break
        command = clean_telnet_line(line)
        next if command.empty?
        output = process_telnet_command(command, session)
        socket << output.gsub(/\r?\n/, "\r\n") << "\r\n" unless output.empty?
      end
      socket.flush
    ensure
      close_session(session) if session
    end

    # Drop telnet option negotiation (IAC sequences) and control characters.
    private def clean_telnet_line(line : String) : String
      bytes = line.to_slice
      clean = IO::Memory.new(bytes.size)
      i = 0
      while i < bytes.size
        byte = bytes[i]
        if byte == 0xFF_u8 # IAC
          option = bytes[i + 1]?
          i += option && option >= 0xFB_u8 ? 3 : 2
        elsif byte == 0x08_u8 || byte == 0x7F_u8 # backspace / delete
          clean.seek(-1, IO::Seek::Current) if clean.pos > 0
          i += 1
        else
          clean.write_byte(byte) if byte >= 0x20_u8 || byte == 0x09_u8
          i += 1
        end
      end
      String.new(clean.to_slice[0, clean.pos]).scrub.strip
    end

    private def open_session(type : Symbol) : Session
      session = Session.new(generate_session_id, @atomspace, type)
      @sessions_mutex.synchronize { @sessions[session.id] = session }
      session
    end

    private def close_session(session : Session)
      session.close
      @sessions_mutex.synchronize { @sessions.delete(session.id) }
    end

    # Run a CogShell command (AtomSpace, PLN, URE, NLP, vision) on the
    # server's AtomSpace.
    def run_shell_command(command : String) : String
      shell = @shell || return "Unknown command: #{command}. The knowledge base shell is not loaded."
      @shell_mutex.synchronize { shell.call(command).rstrip }
    rescue ex
      "Error: #{ex.message}"
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
      session = open_session(:telnet)
      session_id = session.id

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
    ensure
      # One HTTP request is one session; nothing keeps it open afterwards.
      close_session(session) if session
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
        sessions      - Show open sessions
        quit, exit    - Close session

        Knowledge base commands:
        concept <name>                 Create ConceptNode
        predicate <name>               Create PredicateNode
        inherit <child> <parent> [s c] InheritanceLink
        eval <pred> <a> [b ...]        EvaluationLink
        imply <a> <b> [s c]            ImplicationLink
        reason [steps]                 Run PLN
        ure                            Run URE forward chaining
        query <name>                   Lookup by name
        list <type>                    List atoms of a type
        size, clear, tv, nlp, parse    See CogShell
        HELP
      when "info"
        "CogServer #{VERSION} - Host: #{@host}, Port: #{@port}, WebSocket: #{@ws_port}"
      when "atomspace"
        "AtomSpace: #{@atomspace.size} atoms (#{@atomspace.node_count} nodes, #{@atomspace.link_count} links)"
      when "list"
        atoms = @atomspace.get_all_atoms
        if atoms.empty?
          "AtomSpace is empty"
        else
          "Atoms in AtomSpace:\n" + atoms.first(10).map_with_index { |atom, i| "#{i + 1}. #{atom}" }.join("\n") +
            (atoms.size > 10 ? "\n... and #{atoms.size - 10} more" : "")
        end
      when "stats"
        "Session #{session.id} (#{session.session_type}), Active: #{session.duration.total_seconds.round(1)}s"
      when "sessions"
        sessions = @sessions_mutex.synchronize { @sessions.values }
        sessions.map { |s| "#{s.id} (#{s.session_type}) #{s.duration.total_seconds.round(1)}s" }.join("\n")
      when "quit", "exit"
        session.close
        "Session closed. Goodbye!"
      else
        output = run_shell_command(command.strip)
        if output.starts_with?("Unknown command:")
          "Unknown command: #{command}. Type 'help' for available commands."
        else
          output
        end
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

    # WebSocket endpoint (RFC 6455) for real-time monitoring and control.
    #
    # Client -> server, JSON text frames (an optional "id" is echoed back):
    #   {"action": "subscribe",   "events": ["AtomAdded", "*"]}
    #   {"action": "unsubscribe", "events": ["AtomAdded"]}
    #   {"action": "command",     "command": "inherit cat animal"}
    #   {"action": "stats"}  {"action": "ping"}
    # A frame that is not a JSON object is run as a shell command.
    #
    # Server -> client: {"type": "welcome" | "subscribed" | "result" | "stats"
    # | "pong" | "error", ...} replies, and the subscribed monitor events
    # {"type": "AtomAdded", "timestamp": ..., "data": {...}}.
    private def handle_websocket_upgrade(context)
      request = context.request
      unless request.headers["Connection"]?.try(&.downcase.includes?("upgrade")) &&
             request.headers["Upgrade"]?.try(&.downcase) == "websocket"
        return websocket_reject(context, 400, "Invalid WebSocket upgrade request")
      end
      websocket_key = request.headers["Sec-WebSocket-Key"]?
      return websocket_reject(context, 400, "Missing WebSocket key") unless websocket_key
      version = request.headers["Sec-WebSocket-Version"]?
      if version && version != "13"
        context.response.headers["Sec-WebSocket-Version"] = "13"
        return websocket_reject(context, 426, "Unsupported WebSocket version")
      end

      response = context.response
      response.status = HTTP::Status::SWITCHING_PROTOCOLS
      response.headers["Upgrade"] = "websocket"
      response.headers["Connection"] = "Upgrade"
      response.headers["Sec-WebSocket-Accept"] = HTTP::WebSocket::Protocol.key_challenge(websocket_key)
      # A server may only select a subprotocol the client offered.
      offered = request.headers.get?("Sec-WebSocket-Protocol").try(&.flat_map(&.split(',')).map(&.strip)) || [] of String
      response.headers["Sec-WebSocket-Protocol"] = "json" if offered.includes?("json")

      response.upgrade do |io|
        serve_websocket(HTTP::WebSocket.new(io))
      end
    rescue ex
      CogUtil::Logger.error("WebSocket upgrade error: #{ex.message}")
      websocket_reject(context, 500, "WebSocket upgrade failed")
    end

    private def websocket_reject(context, status : Int32, message : String)
      context.response.status_code = status
      context.response.content_type = "application/json"
      context.response.print({"error" => message}.to_json)
    end

    private def serve_websocket(socket : HTTP::WebSocket)
      session = open_session(:websocket)
      monitor = @broadcaster.register_monitor(session.id, persistent: true)
      CogUtil::Logger.info("WebSocket connection established for session #{session.id}")

      # One writer per connection: replies and events share the outbox, so
      # frames never interleave and a slow client cannot stall the broadcaster.
      writer_done = Channel(Nil).new
      spawn do
        while message = monitor.outbox.receive?
          begin
            socket.send(message)
          rescue IO::Error
            break
          end
        end
        writer_done.send(nil)
      end

      monitor.reply({"type" => "welcome", "session" => session.id, "version" => VERSION,
                     "events" => MonitorEventType.names}.to_json)
      socket.on_message { |message| handle_websocket_message(message, monitor) }
      socket.run
    rescue ex : IO::Error
      CogUtil::Logger.debug("WebSocket closed: #{ex.message}")
    ensure
      if session
        @broadcaster.unregister_monitor(session.id)
        close_session(session)
      end
      if writer_done
        select
        when writer_done.receive
        when timeout(1.second)
        end
      end
    end

    private def handle_websocket_message(message : String, monitor : WebSocketMonitor)
      monitor.touch
      request = begin
        JSON.parse(message).as_h?
      rescue JSON::ParseException
        nil
      end
      # Anything that is not a JSON object is a shell command.
      return monitor.reply({"type" => "result", "command" => message.strip,
                            "output" => run_shell_command(message.strip)}.to_json) unless request

      id = request["id"]?
      action = request["action"]?.try(&.as_s?) || request["command"]?.try { "command" }
      reply = case action
              when "subscribe", "unsubscribe"
                names = request["events"]?.try { |e| e.as_a?.try(&.compact_map(&.as_s?)) || e.as_s?.try { |one| [one] } } || [] of String
                resolved = names.map { |name| {name, MonitorEventType.resolve(name)} }
                if bad = resolved.find { |(_, canonical)| canonical.nil? }
                  {"type" => JSON::Any.new("error"), "message" => JSON::Any.new("unknown event #{bad[0].inspect}; " \
                                                                                "expected * or one of #{MonitorEventType.names.join(", ")}")}
                else
                  resolved.each do |(_, canonical)|
                    action == "subscribe" ? monitor.subscribe(canonical.not_nil!) : monitor.unsubscribe(canonical.not_nil!)
                  end
                  {"type"   => JSON::Any.new("subscribed"),
                   "events" => JSON::Any.new(monitor.subscriptions.to_a.sort.map { |e| JSON::Any.new(e) })}
                end
              when "command"
                command = request["command"]?.try(&.as_s?).to_s.strip
                if command.empty?
                  {"type" => JSON::Any.new("error"), "message" => JSON::Any.new("command is required")}
                else
                  {"type" => JSON::Any.new("result"), "command" => JSON::Any.new(command),
                   "output" => JSON::Any.new(run_shell_command(command))}
                end
              when "stats"
                {"type" => JSON::Any.new("stats"), "data" => JSON.parse(stats.to_json)}
              when "ping"
                {"type" => JSON::Any.new("pong")}
              else
                {"type" => JSON::Any.new("error"), "message" => JSON::Any.new("unknown action #{action.inspect}; " \
                                                                              "expected subscribe, unsubscribe, command, stats or ping")}
              end
      reply["id"] = id if id
      monitor.reply(reply.to_json)
    end

    private def handle_http_api(context)
      case context.request.path
      when "/status"
        handle_status_request(context)
      when "/summary"
        handle_summary_request(context)
      when "/metrics"
        handle_metrics_request(context)
      when "/atomspace"
        handle_atomspace_request(context)
      when "/atom"
        handle_create_atom(context)
      when "/atoms"
        handle_atoms_request(context)
      when .starts_with?("/atoms/")
        handle_atom_request(context, context.request.path.lchop("/atoms/"))
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

    private def handle_summary_request(context)
      response = {
        "server"          => "CogServer #{VERSION}",
        "host"            => @host,
        "port"            => @port,
        "ws_port"         => @ws_port,
        "running"         => @running,
        "active_sessions" => @sessions.size,
        "atomspace"       => {
          "size"  => @atomspace.size,
          "nodes" => @atomspace.node_count,
          "links" => @atomspace.link_count,
        },
        "uptime" => Time.utc.to_rfc3339,
      }
      context.response.content_type = "application/json"
      context.response.print(response.to_json)
    end

    private def handle_metrics_request(context)
      response = {
        "atomspace_size"  => @atomspace.size,
        "atomspace_nodes" => @atomspace.node_count,
        "atomspace_links" => @atomspace.link_count,
        "active_sessions" => @sessions.size,
        "server_running"  => @running,
        "timestamp"       => Time.utc.to_rfc3339,
      }
      context.response.content_type = "application/json"
      context.response.print(response.to_json)
    end

    private def handle_atomspace_request(context)
      case context.request.method
      when "GET"
        atoms = @atomspace.get_all_atoms
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
                  @atomspace.get_all_atoms
                end

        response = {
          "count" => atoms.size,
          "atoms" => atoms.map { |atom| atom_entry(atom) },
        }

        context.response.content_type = "application/json"
        context.response.print(response.to_json)
      when "POST"
        # Create new atom
        handle_create_atom(context)
      when "DELETE"
        # Remove the atom described by {"atom": <content form>}.
        begin
          data = JSON.parse(context.request.body.try(&.gets_to_end) || "")
          described = AtomSpace::AtomWire.read(data["atom"]? || data) { |handle| @atomspace.get_atom(handle) }
          remove_atom_response(context, @atomspace.find_equivalent(described))
        rescue ex : JSON::ParseException | KeyError | ArgumentError | TypeCastError | OverflowError
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

    private def atom_entry(atom : AtomSpace::Atom)
      {
        "handle"      => atom.handle,
        "type"        => atom.type.to_s,
        "name"        => atom.node? ? atom.name : nil,
        "outgoing"    => atom.link? ? atom.outgoing.map(&.handle) : nil,
        "truth_value" => {
          "strength"   => atom.truth_value.strength,
          "confidence" => atom.truth_value.confidence,
        },
        "string" => atom.to_s,
      }
    end

    # GET /atoms/:handle returns one atom, with its full content form under
    # "wire"; DELETE /atoms/:handle removes it.
    private def handle_atom_request(context, handle_text : String)
      handle = handle_text.to_u64?
      atom = handle.try { |h| @atomspace.get_atom(h) }
      case context.request.method
      when "GET"
        context.response.content_type = "application/json"
        if atom
          entry = JSON.parse(atom_entry(atom).to_json).as_h
          entry["wire"] = JSON.parse(AtomSpace::AtomWire.to_json(atom))
          context.response.print(entry.to_json)
        else
          context.response.status_code = 404
          context.response.print({"error" => "No atom with handle #{handle_text}"}.to_json)
        end
      when "DELETE"
        remove_atom_response(context, atom)
      else
        context.response.status_code = 405
        context.response.content_type = "application/json"
        context.response.print({"error" => "Method not allowed"}.to_json)
      end
    end

    private def remove_atom_response(context, atom : AtomSpace::Atom?)
      context.response.content_type = "application/json"
      if atom.nil?
        context.response.status_code = 404
        context.response.print({"error" => "No such atom"}.to_json)
      elsif @atomspace.remove_atom(atom)
        context.response.print({"success" => true, "removed" => atom.handle}.to_json)
      else
        context.response.status_code = 409
        context.response.print({"error" => "Atom is still used by other links", "handle" => atom.handle}.to_json)
      end
    end

    # POST /atoms takes an atom in its content form, either at the top level
    # or under "atom". Outgoing entries are nested atoms or existing handles.
    # Truth values merge with what is stored unless "replace" is true.
    private def handle_create_atom(context)
      begin
        body = context.request.body.try(&.gets_to_end) || ""
        data = JSON.parse(body)

        # Resolve every target before mutating the graph. Invalid handles must
        # not silently turn a submitted relationship into an empty link.
        described = AtomSpace::AtomWire.read(data["atom"]? || data) { |handle| @atomspace.get_atom(handle) }
        atom = AtomSpace::AtomWire.intern(described, @atomspace, data["replace"]?.try(&.as_bool?) || false)

        response = {
          "success" => true,
          "atom"    => {
            "handle" => atom.handle,
            "type"   => atom.type.to_s,
            "name"   => atom.name,
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
            @broadcaster.broadcast_storage(MonitorEventType::StorageAttached, storage.name, storage_type)
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
            @broadcaster.broadcast_storage(MonitorEventType::StorageDetached, storage_name, storage.class.name)
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
    # Messages waiting to be written to the client. Events are dropped when
    # it is full; replies wait for room.
    getter outbox : Channel(String)
    # Events dropped because the client was not reading fast enough.
    getter dropped : Int64 = 0_i64
    # A monitor bound to a live connection is never reaped for inactivity.
    getter? persistent : Bool
    @closed : Bool = false

    OUTBOX_CAPACITY = 256

    def initialize(@session_id : String, @persistent : Bool = false)
      @subscriptions = Set(String).new
      @created_at = Time.utc
      @last_activity = Time.utc
      @outbox = Channel(String).new(OUTBOX_CAPACITY)
    end

    # Queue an event without blocking; false when it had to be dropped.
    def deliver(message : String) : Bool
      return false if @closed
      select
      when @outbox.send(message)
        true
      else
        @dropped += 1
        false
      end
    rescue Channel::ClosedError
      false
    end

    # Queue a reply to a client request, waiting for room if necessary.
    def reply(message : String) : Nil
      @outbox.send(message) unless @closed
    rescue Channel::ClosedError
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
      return if @closed
      @closed = true
      @outbox.close
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

    # The canonical subscription name for `name` ("*" or an event type,
    # matched without regard to case or underscores), or nil.
    def self.resolve(name : String) : String?
      return "*" if name == "*"
      key = name.downcase.delete('_')
      names.find { |candidate| candidate.downcase == key }
    end
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

    def register_monitor(session_id : String, persistent : Bool = false) : WebSocketMonitor
      @mutex.synchronize do
        monitor = WebSocketMonitor.new(session_id, persistent)
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

    # Queue an event for the subscribed monitors. Never blocks the caller
    # (AtomSpace mutations call this): when the queue is full the event is
    # dropped and counted.
    def broadcast(event : MonitorEvent)
      return unless @running
      select
      when @event_queue.send(event)
      else
        @dropped_events += 1
      end
    end

    # Events dropped because the queue was full.
    getter dropped_events : Int64 = 0_i64

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

    def broadcast_atom_changed(event_type : MonitorEventType, atom : AtomSpace::Atom)
      data = Hash(String, JSON::Any).new
      data["handle"] = JSON::Any.new(atom.handle.to_i64)
      data["type"] = JSON::Any.new(atom.type.to_s)
      data["name"] = JSON::Any.new(atom.responds_to?(:name) ? atom.name : "")
      data["truth_value"] = JSON::Any.new({
        "strength"   => JSON::Any.new(atom.truth_value.strength),
        "confidence" => JSON::Any.new(atom.truth_value.confidence),
      })
      broadcast(MonitorEvent.new(event_type, data))
    end

    def broadcast_storage(event_type : MonitorEventType, name : String, kind : String)
      data = Hash(String, JSON::Any).new
      data["name"] = JSON::Any.new(name)
      data["storage_type"] = JSON::Any.new(kind)
      broadcast(MonitorEvent.new(event_type, data))
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
      targets = @mutex.synchronize do
        @monitors.values.select { |monitor| !monitor.closed? && monitor.subscribed_to?(event_type_str) }
      end
      return if targets.empty?
      message = event.to_json
      targets.each(&.deliver(message))
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
          if monitor.closed? || (!monitor.persistent? && (now - monitor.last_activity) > stale_timeout)
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
