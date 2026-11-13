require "spec"
require "http/client"
require "http/web_socket"
require "json"
require "socket"
require "../../src/cogserver/cogserver_shell"

# Poll until the block holds, for up to `limit`. Used where another fiber
# finishes the work (accepting a connection, tearing a session down); the
# assertions that follow still decide the outcome.
private def eventually(limit : Time::Span = 10.seconds, &) : Nil
  deadline = Time.monotonic + limit
  until yield
    break if Time.monotonic > deadline
    sleep 10.milliseconds
  end
end

# Server#start binds its listeners in fibers; wait until HTTP answers.
private def wait_for_http(port : Int32) : Nil
  eventually do
    begin
      HTTP::Client.get("http://127.0.0.1:#{port}/ping").status_code == 200
    rescue Socket::Error | IO::Error
      false
    end
  end
end

private def with_server(telnet_port : Int32, ws_port : Int32, &)
  server = CogServer::Server.new("127.0.0.1", telnet_port, ws_port)
  server.start
  wait_for_http(ws_port)
  begin
    yield server
  ensure
    server.stop
  end
end

# Read from the socket until the shell prompt, returning what came before it.
private def read_to_prompt(socket : TCPSocket) : String
  socket.read_timeout = 5.seconds
  text = String::Builder.new
  buffer = Bytes.new(1)
  tail = ""
  loop do
    break if socket.read(buffer) == 0
    text.write(buffer)
    tail = (tail + String.new(buffer))[-5..]? || tail + String.new(buffer)
    break if tail == "cog> "
  end
  text.to_s.chomp("cog> ")
end

private def next_message(channel : Channel(JSON::Any)) : JSON::Any
  select
  when message = channel.receive
    message
  when timeout(5.seconds)
    raise "no WebSocket message within 5 seconds"
  end
end

# The next message of the given type, skipping others (events and replies
# share one connection).
private def next_of_type(channel : Channel(JSON::Any), type : String) : JSON::Any
  20.times do
    message = next_message(channel)
    return message if message["type"] == type
  end
  raise "no #{type} message"
end

private def open_websocket(port : Int32) : {HTTP::WebSocket, Channel(JSON::Any)}
  socket = HTTP::WebSocket.new("ws://127.0.0.1:#{port}/")
  inbox = Channel(JSON::Any).new(64)
  socket.on_message { |message| inbox.send(JSON.parse(message)) }
  spawn { socket.run rescue nil }
  {socket, inbox}
end

describe "CogServer telnet port" do
  it "serves an interactive shell over raw TCP" do
    with_server(19180, 19181) do |server|
      socket = TCPSocket.new("127.0.0.1", 19180)
      banner = read_to_prompt(socket)
      banner.should contain("Welcome to CogServer")
      banner.should contain("Type 'help' for available commands")
      server.stats["active_sessions"].should eq(1)

      socket << "inherit cat animal\r\n"
      read_to_prompt(socket).should contain(%((INHERITANCELINK (CONCEPTNODE "cat") (CONCEPTNODE "animal"))))
      server.atomspace.get_nodes_by_name("cat").size.should eq(1)

      # Telnet option negotiation (IAC WILL ECHO) and a backspace are ignored.
      socket.write(Bytes[0xFF, 0xFB, 0x01])
      socket << "infox\b\r\n"
      read_to_prompt(socket).should contain("CogServer #{CogServer::VERSION} - Host: 127.0.0.1")

      socket << "help\r\n"
      help = read_to_prompt(socket)
      help.should contain("inherit <child> <parent>")
      help.should contain("quit, exit")

      socket << "frobnicate\r\n"
      read_to_prompt(socket).should contain("Unknown command: frobnicate")

      socket << "quit\r\n"
      socket.gets_to_end.should contain("Goodbye")
      socket.close
      eventually { server.stats["active_sessions"] == 0 }
      server.stats["active_sessions"].should eq(0)
    end
  end

  it "runs a command sent before the banner, as netcat pipes do" do
    with_server(19182, 19183) do |server|
      socket = TCPSocket.new("127.0.0.1", 19182)
      socket << "concept piped\n"
      socket.flush
      socket.close_write
      output = socket.gets_to_end
      output.should contain(%((CONCEPTNODE "piped")))
      socket.close
    end
  end

  it "still answers HTTP ?cmd= requests on the same port without leaking sessions" do
    with_server(19184, 19185) do |server|
      info = HTTP::Client.get("http://127.0.0.1:19184/?cmd=info")
      info.status_code.should eq(200)
      info.body.should contain("CogServer #{CogServer::VERSION} - Host: 127.0.0.1")

      HTTP::Client.get("http://127.0.0.1:19184/?cmd=concept%20dog").body.should contain(%((CONCEPTNODE "dog")))
      HTTP::Client.get("http://127.0.0.1:19184/?cmd=list").body.should contain("Atoms in AtomSpace")
      HTTP::Client.get("http://127.0.0.1:19184/").body.should contain("Send commands via ?cmd=")
      server.stats["active_sessions"].should eq(0)
    end
  end
end

describe "CogServer WebSocket" do
  it "completes the RFC 6455 handshake and rejects bad upgrades" do
    with_server(19186, 19187) do |server|
      headers = HTTP::Headers{"Connection" => "Upgrade", "Upgrade" => "websocket",
                              "Sec-WebSocket-Key" => "dGhlIHNhbXBsZSBub25jZQ==", "Sec-WebSocket-Version" => "13"}
      client = HTTP::Client.new("127.0.0.1", 19187)
      response = client.get("/", headers)
      response.status_code.should eq(101)
      # The accept value RFC 6455 gives for this key.
      response.headers["Sec-WebSocket-Accept"].should eq("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
      response.headers["Sec-WebSocket-Protocol"]?.should be_nil
      client.close

      with_protocol = headers.dup
      with_protocol["Sec-WebSocket-Protocol"] = "chat, json"
      client = HTTP::Client.new("127.0.0.1", 19187)
      client.get("/", with_protocol).headers["Sec-WebSocket-Protocol"].should eq("json")
      client.close

      no_key = HTTP::Headers{"Connection" => "Upgrade", "Upgrade" => "websocket"}
      HTTP::Client.get("http://127.0.0.1:19187/", no_key).status_code.should eq(400)
      keep_alive = HTTP::Headers{"Connection" => "keep-alive", "Upgrade" => "websocket"}
      HTTP::Client.get("http://127.0.0.1:19187/", keep_alive).status_code.should eq(400)
      old = headers.dup
      old["Sec-WebSocket-Version"] = "8"
      rejected = HTTP::Client.get("http://127.0.0.1:19187/", old)
      rejected.status_code.should eq(426)
      rejected.headers["Sec-WebSocket-Version"].should eq("13")
    end
  end

  it "streams subscribed AtomSpace events and runs commands" do
    with_server(19188, 19189) do |server|
      socket, inbox = open_websocket(19189)
      welcome = next_message(inbox)
      welcome["type"].should eq("welcome")
      welcome["events"].as_a.map(&.as_s).should contain("AtomAdded")
      server.stats["active_sessions"].should eq(1)
      server.broadcaster.active_monitors.should eq(1)

      # Nothing is delivered before subscribing.
      server.atomspace.add_concept_node("unseen")
      socket.send({"action" => "ping", "id" => 7}.to_json)
      pong = next_message(inbox)
      pong["type"].should eq("pong")
      pong["id"].should eq(7)

      socket.send({"action" => "subscribe", "events" => ["atom_added", "TruthValueChanged"]}.to_json)
      next_message(inbox)["events"].as_a.map(&.as_s).should eq(["AtomAdded", "TruthValueChanged"])

      atom = server.atomspace.add_concept_node("seen")
      added = next_of_type(inbox, "AtomAdded")
      added["data"]["name"].should eq("seen")
      added["data"]["handle"].should eq(atom.handle.to_i64)
      added["timestamp"].as_s.should_not be_empty

      server.atomspace.add_concept_node("seen", AtomSpace::SimpleTruthValue.new(0.4, 0.8))
      changed = next_of_type(inbox, "TruthValueChanged")
      changed["data"]["name"].should eq("seen")

      # A command runs on the server's AtomSpace; its additions are streamed too.
      socket.send({"action" => "command", "command" => "inherit cat animal", "id" => "c1"}.to_json)
      # The reply and the events travel separately, so either may come first.
      messages = [] of JSON::Any
      until messages.any? { |m| m["type"] == "result" } && messages.count { |m| m["type"] == "AtomAdded" } >= 3
        messages << next_message(inbox)
      end
      result = messages.find! { |m| m["type"] == "result" }
      result["id"].should eq("c1")
      result["output"].as_s.should contain("INHERITANCELINK")
      messages.select { |m| m["type"] == "AtomAdded" }.map(&.["data"]["type"].as_s).should contain("INHERITANCE_LINK")

      # Plain text is a shell command.
      socket.send("size")
      next_of_type(inbox, "result")["output"].as_s.should contain("AtomSpace size=")

      socket.send({"action" => "stats"}.to_json)
      next_of_type(inbox, "stats")["data"]["atomspace_size"].as_i.should eq(server.atomspace.size)

      socket.send({"action" => "subscribe", "events" => ["Nope"]}.to_json)
      next_of_type(inbox, "error")["message"].as_s.should contain(%(unknown event "Nope"))
      socket.send({"action" => "dance"}.to_json)
      next_of_type(inbox, "error")["message"].as_s.should contain("unknown action")

      socket.send({"action" => "unsubscribe", "events" => ["AtomAdded", "TruthValueChanged"]}.to_json)
      next_of_type(inbox, "subscribed")["events"].as_a.should be_empty
      server.atomspace.add_concept_node("after-unsubscribe")
      socket.send({"action" => "ping"}.to_json)
      next_message(inbox)["type"].should eq("pong")

      socket.close
      eventually { server.stats["active_sessions"] == 0 && server.broadcaster.active_monitors == 0 }
      server.stats["active_sessions"].should eq(0)
      server.broadcaster.active_monitors.should eq(0)
    end
  end

  it "broadcasts to every subscriber of * and survives a client that goes away" do
    with_server(19190, 19191) do |server|
      first, first_inbox = open_websocket(19191)
      second, second_inbox = open_websocket(19191)
      [first_inbox, second_inbox].each { |inbox| next_message(inbox)["type"].should eq("welcome") }
      first.send({"action" => "subscribe", "events" => "*"}.to_json)
      second.send({"action" => "subscribe", "events" => ["AtomRemoved"]}.to_json)
      next_of_type(first_inbox, "subscribed")
      next_of_type(second_inbox, "subscribed")

      atom = server.atomspace.add_concept_node("shared")
      next_of_type(first_inbox, "AtomAdded")["data"]["name"].should eq("shared")
      server.atomspace.remove_atom(atom)
      next_of_type(first_inbox, "AtomRemoved")["data"]["handle"].should eq(atom.handle.to_i64)
      next_of_type(second_inbox, "AtomRemoved")["data"]["handle"].should eq(atom.handle.to_i64)

      first.close
      eventually { server.broadcaster.active_monitors == 1 }
      server.broadcaster.active_monitors.should eq(1)
      gone = server.atomspace.add_concept_node("still-works")
      server.atomspace.remove_atom(gone)
      next_of_type(second_inbox, "AtomRemoved")["data"]["handle"].should eq(gone.handle.to_i64)
      second.close
    end
  end
end

describe CogServer::WebSocketMonitor do
  it "drops events instead of blocking when the client stops reading" do
    monitor = CogServer::WebSocketMonitor.new("slow")
    CogServer::WebSocketMonitor::OUTBOX_CAPACITY.times { monitor.deliver("event").should be_true }
    monitor.deliver("overflow").should be_false
    monitor.dropped.should eq(1)
    monitor.outbox.receive.should eq("event")
    monitor.deliver("fits again").should be_true
    monitor.close
    monitor.deliver("after close").should be_false
  end

  it "resolves event names without regard to case or underscores" do
    CogServer::MonitorEventType.resolve("atom_added").should eq("AtomAdded")
    CogServer::MonitorEventType.resolve("HEARTBEAT").should eq("Heartbeat")
    CogServer::MonitorEventType.resolve("*").should eq("*")
    CogServer::MonitorEventType.resolve("nope").should be_nil
  end
end

describe "CogServer without the knowledge base shell" do
  it "still serves its built-in commands" do
    factory = CogServer::Server.shell_factory
    CogServer::Server.shell_factory = nil
    begin
      with_server(19196, 19197) do |server|
        HTTP::Client.get("http://127.0.0.1:19196/?cmd=info").body.should contain("CogServer #{CogServer::VERSION}")
        HTTP::Client.get("http://127.0.0.1:19196/?cmd=concept%20x").body.should contain("Unknown command: concept x")
        server.atomspace.size.should eq(0)
      end
    ensure
      CogServer::Server.shell_factory = factory
    end
  end
end
