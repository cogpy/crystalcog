require "spec"
require "http/client"
require "json"
require "../../src/cogserver/cogserver"

private def with_cog_server(telnet_port : Int32, ws_port : Int32, &)
  server = CogServer::Server.new("127.0.0.1", telnet_port, ws_port)
  server.start
  # Server#start binds its listeners in fibers; wait until HTTP answers.
  deadline = Time.monotonic + 10.seconds
  loop do
    ready = begin
      HTTP::Client.get("http://127.0.0.1:#{ws_port}/ping").status_code == 200
    rescue Socket::Error | IO::Error
      false
    end
    break if ready || Time.monotonic > deadline
    sleep 10.milliseconds
  end
  begin
    yield server
  ensure
    server.stop
  end
end

describe AtomSpace::AtomWire do
  it "round-trips nested links with truth values" do
    cat = AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "cat", AtomSpace::SimpleTruthValue.new(0.9, 0.8))
    animal = AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "animal")
    inner = AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [cat, animal] of AtomSpace::Atom,
      AtomSpace::SimpleTruthValue.new(0.7, 0.6))
    outer = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [inner, cat] of AtomSpace::Atom)

    copy = AtomSpace::AtomWire.read(JSON.parse(AtomSpace::AtomWire.to_json(outer)))
    copy.to_s.should eq(outer.to_s)
    copy.outgoing[0].truth_value.strength.should eq(0.7)
    copy.outgoing[0].outgoing[0].truth_value.confidence.should eq(0.8)
  end

  it "interns into an AtomSpace, merging or replacing truth values" do
    space = AtomSpace::AtomSpace.new
    existing = space.add_concept_node("cat", AtomSpace::SimpleTruthValue.new(0.9, 0.9))
    described = AtomSpace::AtomWire.read(JSON.parse(
      %({"type": "INHERITANCE_LINK", "outgoing": [{"type": "CONCEPT_NODE", "name": "cat",
         "truth_value": {"strength": 0.2, "confidence": 0.1}}, {"type": "CONCEPT_NODE", "name": "pet"}]})))

    link = AtomSpace::AtomWire.intern(described, space, replace: true)
    link.outgoing[0].should be(existing)
    existing.truth_value.strength.should eq(0.2)
    existing.truth_value.confidence.should eq(0.1)
    space.size.should eq(3)

    expect_raises(ArgumentError, /Unknown outgoing handle: 424242/) do
      AtomSpace::AtomWire.read(JSON.parse(%({"type": "LIST_LINK", "outgoing": [424242]}))) { |h| space.get_atom(h) }
    end
  end
end

describe AtomSpace::CogStorageNode do
  it "stores, fetches, loads and removes atoms on a remote CogServer" do
    with_cog_server(19192, 19193) do |server|
      local = AtomSpace::AtomSpace.new
      cat = local.add_concept_node("cat", AtomSpace::SimpleTruthValue.new(0.9, 0.8))
      animal = local.add_concept_node("animal")
      link = local.add_inheritance_link(cat, animal, AtomSpace::SimpleTruthValue.new(0.75, 0.5))
      likes = local.add_evaluation_link(local.add_predicate_node("likes"), local.add_list_link([cat, animal] of AtomSpace::Atom))

      storage = AtomSpace::CogStorageNode.new("remote", "127.0.0.1", 19193)
      storage.open.should be_true
      # Local handles mean nothing to the server: links arrive by content.
      storage.store_atomspace(local).should be_true

      remote = server.atomspace
      remote.size.should eq(local.size)
      remote_link = remote.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).first
      remote_link.to_s.should eq(link.to_s)
      remote_link.truth_value.strength.should eq(0.75)
      remote.get_nodes_by_name("cat").first.truth_value.confidence.should eq(0.8)

      # Storing again with a new truth value replaces it, as a store should.
      cat.truth_value = AtomSpace::SimpleTruthValue.new(0.1, 0.2)
      storage.store_atom(cat).should be_true
      remote.get_nodes_by_name("cat").first.truth_value.strength.should eq(0.1)

      fetched = storage.fetch_atom(likes.handle).not_nil!
      fetched.to_s.should eq(likes.to_s)
      storage.fetch_atom(remote_link.handle).not_nil!.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)
      storage.fetch_atom(9_999_999_u64).should be_nil

      copy = AtomSpace::AtomSpace.new
      other = AtomSpace::CogStorageNode.new("reader", "127.0.0.1", 19193)
      other.open.should be_true
      other.load_atomspace(copy).should be_true
      copy.size.should eq(local.size)
      copy.get_all_atoms.map(&.to_s).sort.should eq(local.get_all_atoms.map(&.to_s).sort)
      copy.get_nodes_by_name("cat").first.truth_value.strength.should eq(0.1)
      copy.get_incoming(copy.get_nodes_by_name("cat").first).size.should eq(2)

      # A node still used by links is refused; the link itself can go.
      storage.remove_atom(cat).should be_false
      storage.remove_atom(link).should be_true
      remote.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).should be_empty
      # `other` never stored this atom, so the server finds it by content.
      copy_eval = copy.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).first
      fresh = AtomSpace::CogStorageNode.new("fresh", "127.0.0.1", 19193)
      fresh.open.should be_true
      fresh.remove_atom(copy_eval).should be_true
      remote.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).should be_empty
      fresh.remove_atom(copy_eval).should be_false
    end
  end
end

describe "CogServer HTTP atom API by handle" do
  it "gets and deletes single atoms and accepts nested content" do
    with_cog_server(19194, 19195) do |server|
      url = "http://127.0.0.1:19195"
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      created = HTTP::Client.post("#{url}/atoms", headers, {
        "type"        => "INHERITANCE_LINK",
        "truth_value" => {"strength" => 0.6, "confidence" => 0.4},
        "outgoing"    => [{"type" => "CONCEPT_NODE", "name" => "sparrow"}, {"type" => "CONCEPT_NODE", "name" => "bird"}],
      }.to_json)
      created.status_code.should eq(201)
      handle = JSON.parse(created.body)["atom"]["handle"].as_i64
      server.atomspace.size.should eq(3)

      got = JSON.parse(HTTP::Client.get("#{url}/atoms/#{handle}").body)
      got["type"].should eq("INHERITANCE_LINK")
      got["truth_value"]["strength"].should eq(0.6)
      got["wire"]["outgoing"][1]["name"].should eq("bird")
      HTTP::Client.get("#{url}/atoms/123456789").status_code.should eq(404)
      HTTP::Client.get("#{url}/atoms/not-a-handle").status_code.should eq(404)

      sparrow = server.atomspace.get_nodes_by_name("sparrow").first.handle
      HTTP::Client.delete("#{url}/atoms/#{sparrow}").status_code.should eq(409)
      HTTP::Client.delete("#{url}/atoms/#{handle}").status_code.should eq(200)
      HTTP::Client.delete("#{url}/atoms/#{handle}").status_code.should eq(404)
      HTTP::Client.delete("#{url}/atoms/#{sparrow}").status_code.should eq(200)
      server.atomspace.size.should eq(1)

      # A bad nested atom leaves the AtomSpace untouched.
      bad = HTTP::Client.post("#{url}/atoms", headers,
        {"type" => "LIST_LINK", "outgoing" => [{"type" => "CONCEPT_NODE", "name" => "new"}, 987654321]}.to_json)
      bad.status_code.should eq(400)
      server.atomspace.size.should eq(1)
    end
  end
end
