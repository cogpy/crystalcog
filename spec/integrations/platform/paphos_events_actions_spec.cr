require "spec"
require "../../../src/integrations/platform/paphos_server"
require "../../../src/integrations/paphos_connector"

private def with_paphos_server(&)
  server = PaphosBackend::Server.new(requested_port: 0, secret: "test-secret").start
  begin
    yield server
  ensure
    server.stop
  end
end

private def client_for(server, email : String) : PaphosBackend::Client
  client = PaphosBackend::Client.new(server.url)
  client.token = client.register(email, "secret123")
  client
end

private def connector_for(server, email : String) : PaphosBackend::Connector
  PaphosBackend::Client.new(server.url).register(email, "secret123") rescue nil
  config = PaphosBackend::Config.new(backend_url: server.url.rchop("/api/v1"), api_key: nil,
    email: email, password: "secret123")
  connector = PaphosBackend::Connector.new(config)
  connector.initialize_connection.should be_true
  connector
end

describe "Paphos events API" do
  it "stores events per user and lists those after an id" do
    with_paphos_server do |server|
      ada = client_for(server, "ada@example.com")
      bob = client_for(server, "bob@example.com")

      first = ada.publish_event("atom_updates", {"atom" => "cat", "change" => "added"})
      first["type"].as_s.should eq("atom_updates")
      first["source"].as_s.should eq("crystalcog")
      first["data"].as_h.transform_values(&.as_s).should eq({"atom" => "cat", "change" => "added"})
      second = ada.publish_event("cognitive_state", source: "galatea")
      bob.publish_event("atom_updates", {"atom" => "dog"})

      ada.events.map(&.["type"].as_s).should eq(["atom_updates", "cognitive_state"])
      ada.events(after: first["id"].as_i64).map(&.["id"].as_i64).should eq([second["id"].as_i64])
      ada.events(types: ["cognitive_state", "other"]).map(&.["source"].as_s).should eq(["galatea"])
      ada.events(limit: 1).size.should eq(1)
      # One user's events are not another's.
      bob.events.map { |event| event["data"]["atom"].as_s }.should eq(["dog"])
    end
  end

  it "validates what it is given" do
    with_paphos_server do |server|
      ada = client_for(server, "ada@example.com")
      expect_raises(PaphosBackend::Client::Error) { ada.publish_event("bad type!") }.status.should eq(400)
      expect_raises(PaphosBackend::Client::Error) { PaphosBackend::Client.new(server.url).events }.status.should eq(401)

      # Non-string data is refused rather than stringified.
      response = HTTP::Client.post("#{server.url}/events",
        headers: HTTP::Headers{"Authorization" => "Bearer #{ada.token}", "Content-Type" => "application/json"},
        body: %({"event": {"type": "x", "data": {"count": 3}}}))
      response.status_code.should eq(400)
      JSON.parse(response.body)["details"].as_s.should eq("data.count must be a string")
      ada.events.should be_empty
    end
  end

  it "holds a waiting request until an event arrives" do
    with_paphos_server do |server|
      ada = client_for(server, "ada@example.com")
      # Nothing arrives: the wait runs out.
      elapsed = Time.measure { ada.events(wait: 150.milliseconds).should be_empty }
      elapsed.should be >= 140.milliseconds

      spawn do
        sleep 100.milliseconds
        ada.publish_event("atom_updates", {"atom" => "late"})
      end
      elapsed = Time.measure do
        ada.events(wait: 5.seconds).map { |event| event["data"]["atom"].as_s }.should eq(["late"])
      end
      elapsed.should be < 3.seconds
    end
  end

  it "keeps only the most recent events" do
    with_paphos_server do |server|
      ada = client_for(server, "ada@example.com")
      user_id = 1_i64
      (PaphosBackend::Server::EVENT_LIMIT + 5).times { |i| server.publish_event(user_id, "tick", {"n" => i.to_s}) }
      kept = ada.events(limit: PaphosBackend::Server::EVENT_LIMIT)
      kept.size.should eq(PaphosBackend::Server::EVENT_LIMIT)
      kept.first["data"]["n"].as_s.should eq("5")
    end
  end
end

describe "Paphos events across a restart" do
  it "keeps the events and goes on numbering after them" do
    path = File.tempname("paphos-events", ".json")
    begin
      last_id = 0_i64
      first = PaphosBackend::Server.new(requested_port: 0, secret: "test-secret", data_file: path).start
      begin
        ada = client_for(first, "ada@example.com")
        ada.publish_event("atom_updates", {"atom" => "cat"})
        last_id = ada.publish_event("cognitive_state", {"mood" => "calm"})["id"].as_i64
      ensure
        first.stop
      end

      second = PaphosBackend::Server.new(requested_port: 0, secret: "test-secret", data_file: path).start
      begin
        ada = PaphosBackend::Client.new(second.url)
        ada.token = ada.login("ada@example.com", "secret123")
        ada.events.map { |event| {event["type"].as_s, event["data"].as_h.values.first.as_s} }.should eq([
          {"atom_updates", "cat"}, {"cognitive_state", "calm"},
        ])
        # A client that had read everything sees only what is new.
        ada.events(after: last_id).should be_empty
        ada.publish_event("atom_updates", {"atom" => "dog"})["id"].as_i64.should eq(last_id + 1)
        ada.events(after: last_id).size.should eq(1)

        ada.call_action("events.clear")["removed"].should eq("3")
      ensure
        second.stop
      end

      # Clearing is kept too; the action's own event came after the clear.
      third = PaphosBackend::Server.new(requested_port: 0, secret: "test-secret", data_file: path).start
      begin
        ada = PaphosBackend::Client.new(third.url)
        ada.token = ada.login("ada@example.com", "secret123")
        ada.events.map { |event| event["data"]["action"].as_s }.should eq(["events.clear"])
      ensure
        third.stop
      end
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "reads a data file written before events were stored" do
    path = File.tempname("paphos-old", ".json")
    begin
      File.write(path, %({"snapshots":[],"users":[],"characters":[],"chats":[],"messages":[],"next_user_id":1,"next_message_id":1}))
      server = PaphosBackend::Server.new(requested_port: 0, secret: "test-secret", data_file: path).start
      begin
        ada = client_for(server, "ada@example.com")
        ada.events.should be_empty
        ada.publish_event("atom_updates")["id"].as_i64.should eq(1)
      ensure
        server.stop
      end
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end

describe "Paphos actions API" do
  it "lists and runs service functions" do
    with_paphos_server do |server|
      ada = client_for(server, "ada@example.com")
      ada.actions.map(&.["name"].as_s).should eq(["echo", "events.clear", "snapshot.copy", "stats"])
      ada.call_action("echo", {"a" => "1", "b" => "two"}).should eq({"a" => "1", "b" => "two"})

      ada.create_character({"name" => "Galatea", "description" => "A statue brought to life", "greeting" => "Hello there",
                            "persona" => "curious and warm", "visibility" => "private"})
      ada.put_snapshot("state", {"kind" => "cognitive_state", "note" => "v1"})
      ada.call_action("snapshot.copy", {"from" => "state", "to" => "state.backup"}).should eq({"key" => "state.backup", "fields" => "2"})
      ada.snapshot("state.backup").should eq({"kind" => "cognitive_state", "note" => "v1"})

      stats = ada.call_action("stats")
      stats["characters"].should eq("1")
      stats["snapshots"].should eq("2")
      stats["chats"].should eq("0")
      # echo and snapshot.copy each left an action_executed event.
      stats["events"].should eq("2")
      ada.events.map { |event| {event["type"].as_s, event["data"]["action"].as_s, event["data"]["status"].as_s} }.first(2).should eq([
        {"action_executed", "echo", "success"}, {"action_executed", "snapshot.copy", "success"},
      ])

      ada.call_action("events.clear")["removed"].should eq("3")
    end
  end

  it "reports refusals and unknown names" do
    with_paphos_server do |server|
      ada = client_for(server, "ada@example.com")
      refused = expect_raises(PaphosBackend::Client::Error) { ada.call_action("snapshot.copy", {"from" => "missing", "to" => "x"}) }
      refused.status.should eq(422)
      refused.message.should eq("no snapshot named missing")
      ada.events.last["data"]["status"].as_s.should eq("refused")

      expect_raises(PaphosBackend::Client::Error) { ada.call_action("no.such.action") }.status.should eq(404)
      expect_raises(PaphosBackend::Client::Error) { PaphosBackend::Client.new(server.url).actions }.status.should eq(401)
    end
  end

  it "runs functions registered by the host program" do
    with_paphos_server do |server|
      server.register_action("greet", "Say hello") do |args, user|
        raise PaphosBackend::Server::ActionError.new("name is required") unless args["name"]?
        {"greeting" => "Hello, #{args["name"]}", "user" => user.to_s}
      end
      expect_raises(ArgumentError) { server.register_action("bad name") { |args, _user| args } }

      ada = client_for(server, "ada@example.com")
      ada.actions.map(&.["name"].as_s).should contain("greet")
      ada.call_action("greet", {"name" => "Ada"}).should eq({"greeting" => "Hello, Ada", "user" => "1"})
      expect_raises(PaphosBackend::Client::Error, "name is required") { ada.call_action("greet") }
    end
  end
end

describe "PaphosBackend::Connector commands and events" do
  it "runs a command on the backend and returns its result" do
    with_paphos_server do |server|
      server.register_action("add", "Add a and b") do |args, _user|
        {"sum" => (args["a"].to_i + args["b"].to_i).to_s}
      end
      connector = connector_for(server, "ada@example.com")

      response = connector.send_command("add", {"a" => "2", "b" => "40"})
      response["status"].should eq("success")
      response["command"].should eq("add")
      response["result.sum"].should eq("42")
      JSON.parse(response["result"]).should eq(JSON.parse(%({"sum": "42"})))

      connector.execute_service_function("echo", {"x" => "y"}).should eq(%({"x":"y"}))
      connector.service_functions["add"].should eq("Add a and b")

      failed = connector.send_command("no.such.command", {} of String => String)
      failed["status"].should eq("error")
      failed["error"].should eq("No action named no.such.command")
      expect_raises(PaphosBackend::Client::Error) { connector.execute_service_function("no.such.command", {} of String => String) }
      connector.disconnect
    end
  end

  it "publishes its events to the backend, where other clients read them" do
    with_paphos_server do |server|
      connector = connector_for(server, "ada@example.com")
      other = PaphosBackend::Client.new(server.url)
      other.token = other.login("ada@example.com", "secret123")

      connector.event_stream.remote?.should be_true
      connector.event_stream.publish_event("atom_updates", {"atom" => "cat"}).should be_true
      connector.send_command("echo", {"k" => "v"})["status"].should eq("success")
      connector.synchronize_state.should be_true

      # Seen from a second client of the same account.
      seen = other.events.map(&.["type"].as_s)
      seen.should eq(["atom_updates", "action_executed", "command_execution", "state_sync"])

      # An event from the other client reaches the connector.
      other.publish_event("cognitive_state", {"mood" => "curious"}, source: "galatea")
      received = connector.receive_events
      received.map(&.["type"]).should eq(seen + ["cognitive_state"])
      received.last["mood"].should eq("curious")
      received.last["source"].should eq("galatea")
      received.first["atom"].should eq("cat")
      # Each event is delivered once.
      connector.receive_events.should be_empty

      other.publish_event("grip_coordination", {"coherence" => "0.9"})
      other.publish_event("unrelated", {} of String => String)
      connector.event_stream.consume_subscribed.map(&.["type"]).should eq(["grip_coordination"])
      connector.status["stream_remote"].should eq("true")
      connector.disconnect
    end
  end

  it "keeps events queued while the backend is away and sends them on reconnect" do
    connector = uninitialized PaphosBackend::Connector
    port = 0
    with_paphos_server do |server|
      port = server.port
      connector = connector_for(server, "ada@example.com")
      connector.event_stream.publish_event("atom_updates", {"n" => "1"}).should be_true
    end

    # The server is gone.
    connector.event_stream.publish_event("atom_updates", {"n" => "2"}).should be_false
    connector.event_stream.publish_event("atom_updates", {"n" => "3"}).should be_false
    connector.event_stream.event_queue.size.should eq(2)
    connector.event_stream.last_error.should_not be_nil
    connector.receive_events.should be_empty
    connector.send_command("echo", {} of String => String)["status"].should eq("error")

    # A new server on the same port, with the same secret and a fresh store.
    server = PaphosBackend::Server.new(requested_port: port, secret: "test-secret").start
    begin
      PaphosBackend::Client.new(server.url).register("ada@example.com", "secret123")
      connector.event_stream.connect.should be_true
      connector.event_stream.event_queue.should be_empty
      connector.receive_events.map(&.["n"]?).compact.should eq(["2", "3"])
    ensure
      server.stop
    end
  end

  it "coordinates locally when it has no backend" do
    connector = PaphosBackend::Connector.new(PaphosBackend::Config.new(backend_url: "http://127.0.0.1:9", api_key: nil))
    response = connector.send_command("echo", {"k" => "v"})
    response["status"].should eq("local")
    response["command"].should eq("echo")
    connector.service_functions.should be_empty
    expect_raises(PaphosBackend::Client::Error, "Not connected") { connector.execute_service_function("echo", {} of String => String) }

    stream = PaphosBackend::EventStreamHandler.new("http://127.0.0.1:9")
    stream.publish_event("atom_updates", {"n" => "1"}).should be_false # not connected
    stream.connect
    stream.publish_event("atom_updates", {"n" => "1"}).should be_true
    stream.consume_events.map(&.["n"]).should eq(["1"])
    stream.consume_events.should be_empty
    stream.status["remote"].should eq("false")
  end
end
