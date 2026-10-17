require "spec"
require "http/client"
require "json"
require "../../src/cogserver/cogserver_main"

describe "CogServer command-line options" do
  it "uses defaults when no options are provided" do
    options = CogServer.parse_options([] of String)

    options.should eq({host: CogServer::DEFAULT_HOST, port: CogServer::DEFAULT_PORT, ws_port: CogServer::DEFAULT_WS_PORT})
  end

  it "accepts validated custom host and ports" do
    options = CogServer.parse_options(["--host", "127.0.0.1", "--port", "19080", "--ws-port", "19081"])

    options.should eq({host: "127.0.0.1", port: 19080, ws_port: 19081})
  end

  it "rejects invalid, missing, and colliding ports before starting a server" do
    CogServer.parse_options(["--port", "not-a-port"]).should be_nil
    CogServer.parse_options(["--ws-port"]).should be_nil
    CogServer.parse_options(["--port", "19080", "--ws-port", "19080"]).should be_nil
  end
end

describe "CogServer HTTP atom API" do
  it "returns created atoms and lists all atom types" do
    server = CogServer::Server.new("127.0.0.1", 19080, 19081)
    server.start

    begin
      # Server#start binds in fibers; yielding allows both listeners to initialize.
      sleep 50.milliseconds
      url = "http://127.0.0.1:19081"
      headers = HTTP::Headers{"Content-Type" => "application/json"}

      created = HTTP::Client.post("#{url}/atoms", headers, %({"type":"CONCEPT_NODE","name":"http-api-spec-concept"}))
      created.status_code.should eq(201)
      created_json = JSON.parse(created.body)
      created_json["success"].as_bool.should be_true
      created_json["atom"]["handle"].as_i.should be > 0
      created_json["atom"]["name"].as_s.should eq("http-api-spec-concept")

      child_handle = created_json["atom"]["handle"].as_i64
      parent = HTTP::Client.post("#{url}/atoms", headers, %({"type":"CONCEPT_NODE","name":"parent"}))
      parent_handle = JSON.parse(parent.body)["atom"]["handle"].as_i64
      relationship = HTTP::Client.post("#{url}/atoms", headers,
        {"type" => "INHERITANCE_LINK", "outgoing" => [child_handle, parent_handle]}.to_json)
      relationship.status_code.should eq(201)
      link_handle = JSON.parse(relationship.body)["atom"]["handle"].as_i64.to_u64
      link = server.atomspace.get_atom(link_handle).not_nil!
      link.outgoing.map(&.handle).should eq([child_handle.to_u64, parent_handle.to_u64])
      server.atomspace.get_incoming(link.outgoing.first).map(&.handle).should contain(link_handle)

      original_size = server.atomspace.size
      invalid = HTTP::Client.post("#{url}/atoms", headers,
        {"type" => "INHERITANCE_LINK", "outgoing" => [child_handle, -1_i64]}.to_json)
      invalid.status_code.should eq(400)
      missing = HTTP::Client.post("#{url}/atoms", headers,
        {"type" => "LIST_LINK", "outgoing" => [9_999_999_i64]}.to_json)
      missing.status_code.should eq(400)
      server.atomspace.size.should eq(original_size)

      listed = HTTP::Client.get("#{url}/atoms")
      listed.status_code.should eq(200)
      listed_json = JSON.parse(listed.body)
      listed_json["count"].as_i.should be >= 1
      listed_json["atoms"].as_a.any? { |atom| atom["name"].as_s == "http-api-spec-concept" }.should be_true

      atomspace = HTTP::Client.get("#{url}/atomspace")
      atomspace.status_code.should eq(200)
      atomspace_json = JSON.parse(atomspace.body)
      atomspace_json["atoms"].as_a.any?(&.as_s.includes?("http-api-spec-concept")).should be_true
    ensure
      server.stop
    end
  end
end
