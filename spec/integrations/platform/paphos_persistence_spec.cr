require "spec"
require "file_utils"
require "../../../src/integrations/platform/paphos_server"
require "../../../src/integrations/paphos_connector"

private def with_paphos_server(data_file : String? = nil, &)
  server = PaphosBackend::Server.new(requested_port: 0, secret: "test-secret", data_file: data_file).start
  begin
    yield server
  ensure
    server.stop
  end
end

private def connector_for(server, email : String, batch = false) : PaphosBackend::Connector
  PaphosBackend::Client.new(server.url).register(email, "secret123") rescue nil
  config = PaphosBackend::Config.new(backend_url: server.url.rchop("/api/v1"), api_key: nil,
    email: email, password: "secret123", batch_operations: batch)
  connector = PaphosBackend::Connector.new(config)
  connector.initialize_connection.should be_true
  connector
end

describe "Paphos snapshots API" do
  it "stores, lists, filters and deletes snapshots per user" do
    with_paphos_server do |server|
      ada = PaphosBackend::Client.new(server.url)
      ada.token = ada.register("ada@example.com", "secret123")
      bob = PaphosBackend::Client.new(server.url)
      bob.token = bob.register("bob@example.com", "secret123")

      ada.snapshot("state:1").should be_nil
      ada.put_snapshot("state:1", {"kind" => "cognitive_state", "note" => "first"})["key"].should eq("state:1")
      ada.put_snapshot("export", {"kind" => "atomspace", "atoms" => "(CONCEPTNODE \"x\") (1.0, 0.0)\n"})
      ada.put_snapshot("state:1", {"kind" => "cognitive_state", "note" => "second"})
      ada.snapshot("state:1").should eq({"kind" => "cognitive_state", "note" => "second"})

      ada.snapshots.map(&.["key"].as_s).should eq(["export", "state:1"])
      ada.snapshots({"kind" => "atomspace"}).map(&.["key"].as_s).should eq(["export"])
      ada.snapshots({"kind" => "nope"}).should be_empty
      # Snapshots belong to their owner.
      bob.snapshots.should be_empty
      bob.snapshot("state:1").should be_nil

      err = expect_raises(PaphosBackend::Client::Error) { ada.put_snapshot("bad key!", {"a" => "b"}) }
      err.status.should eq(400)
      ada.delete_snapshot("export")
      ada.snapshots.size.should eq(1)
      expect_raises(PaphosBackend::Client::Error) { ada.delete_snapshot("export") }.status.should eq(404)
    end
  end

  it "keeps snapshots across a server restart" do
    path = File.tempname("paphos-snapshots", ".json")
    begin
      token = ""
      with_paphos_server(path) do |server|
        client = PaphosBackend::Client.new(server.url)
        token = client.register("ada@example.com", "secret123")
        client.token = token
        client.put_snapshot("kept", {"value" => "42"})
      end
      with_paphos_server(path) do |server|
        PaphosBackend::Client.new(server.url, token).snapshot("kept").should eq({"value" => "42"})
      end
    ensure
      File.delete?(path)
    end
  end
end

describe PaphosBackend::PersistenceLayer do
  it "stores an AtomSpace on the backend and loads it into another process's AtomSpace" do
    with_paphos_server do |server|
      writer = connector_for(server, "ada@example.com")
      space = AtomSpace::AtomSpace.new
      cat = space.add_concept_node("cat", AtomSpace::SimpleTruthValue.new(0.9, 0.8))
      space.add_inheritance_link(cat, space.add_concept_node("animal"), AtomSpace::SimpleTruthValue.new(0.7, 0.6))
      writer.attach_atomspace(space)
      writer.persistence.store_atomspace_data.should be_true
      writer.persistence.batch_queue.should be_empty

      # A second connector shares nothing with the first but the backend.
      reader = connector_for(server, "ada@example.com")
      copy = AtomSpace::AtomSpace.new
      reader.attach_atomspace(copy)
      reader.persistence.load_atomspace_data.should be_true
      copy.size.should eq(3)
      link = copy.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).first
      link.truth_value.strength.should eq(0.7)
      link.outgoing[0].truth_value.confidence.should eq(0.8)

      # Another user has no such snapshot.
      stranger = connector_for(server, "bob@example.com")
      stranger.attach_atomspace(AtomSpace::AtomSpace.new)
      stranger.persistence.load_atomspace_data.should be_false
    end
  end

  it "stores and loads cognitive snapshots, and answers queries" do
    with_paphos_server do |server|
      connector = connector_for(server, "ada@example.com")
      connector.store_snapshot("grip-1").should be_true
      connector.persistence.store_snapshot("notes", {"kind" => "note", "text" => "remember this"}).should be_true

      fresh = connector_for(server, "ada@example.com")
      loaded = fresh.load_snapshot("grip-1").not_nil!
      loaded["kind"].should eq("cognitive_state")
      JSON.parse(loaded["grip_state"]).as_h.has_key?("coherence").should be_true
      # No invented record for a snapshot that was never stored.
      fresh.load_snapshot("never-stored").should be_nil

      fresh.persistence.query_data({} of String => String).map(&.["snapshot_id"]).should eq(["grip-1", "notes"])
      fresh.persistence.query_data({"kind" => "note"}).map(&.["snapshot_id"]).should eq(["notes"])
      fresh.persistence.delete_snapshot("notes").should be_true
      fresh.persistence.query_data({} of String => String).size.should eq(1)
    end
  end

  it "queues writes while batching and sends them on flush" do
    with_paphos_server do |server|
      connector = connector_for(server, "ada@example.com", batch: true)
      other = connector_for(server, "ada@example.com")
      3.times { |i| connector.persistence.store_snapshot("batched-#{i}", {"n" => i.to_s}).should be_true }
      connector.persistence.store_snapshot("batched-0", {"n" => "replaced"})
      connector.persistence.batch_queue.size.should eq(3)
      other.load_snapshot("batched-1").should be_nil
      # The writer still sees its own pending write.
      connector.load_snapshot("batched-0").not_nil!["n"].should eq("replaced")

      connector.persistence.flush_batch.should eq(3)
      connector.persistence.batch_queue.should be_empty
      other.load_snapshot("batched-0").not_nil!["n"].should eq("replaced")
    end
  end

  it "keeps writes queued when the backend is unreachable" do
    layer = PaphosBackend::PersistenceLayer.new("http://127.0.0.1:1")
    layer.store_snapshot("offline", {"a" => "b"}).should be_true
    layer.flush_batch.should eq(0)
    layer.batch_queue.size.should eq(1)
    layer.load_snapshot("offline").not_nil!["a"].should eq("b")
    layer.load_snapshot("missing").should be_nil

    layer.client = PaphosBackend::Client.new("http://127.0.0.1:1/api/v1", "token", timeout: 1.second)
    layer.flush_batch.should eq(0)
    layer.batch_queue.size.should eq(1)
    layer.last_error.should_not be_empty
    layer.status["backend_attached"].should eq("true")
  end
end
