require "spec"
require "http/server"
require "../../src/integrations/integration"

# In-process stand-in for an Aphrodite / OpenAI-compatible Pygmalion backend.
# Records every request so specs can assert on the wire format.
class MockPygmalionServer
  getter requests = [] of {String, String, HTTP::Headers, String}
  property health_body = %({"status":"ok","version":"0.6.0","model":"pygmalion-2-7b"})
  property fail_chat_with : Int32? = nil
  property tool_round = 0

  @server : HTTP::Server

  def initialize
    @server = HTTP::Server.new { |ctx| handle(ctx) }
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url : String
    "http://127.0.0.1:#{@address.port}"
  end

  def close
    @server.close
  end

  def last_body : JSON::Any
    JSON.parse(@requests.last[3])
  end

  private def handle(ctx)
    req = ctx.request
    body = req.body.try(&.gets_to_end) || ""
    @requests << {req.method, req.path, req.headers, body}
    res = ctx.response
    res.content_type = "application/json"

    case {req.method, req.path}
    when {"GET", "/v1/models"}
      res.print %({"object":"list","data":[{"id":"pygmalion-2-7b"},{"id":"mythalion-13b"}]})
    when {"GET", "/health"}
      res.print @health_body
    when {"POST", "/v1/chat/completions"}
      if code = @fail_chat_with
        res.status_code = code
        res.print %({"error":"boom"})
        return
      end
      json = JSON.parse(body)
      if json["stream"]?.try(&.as_bool?)
        res.content_type = "text/event-stream"
        ["Hel", "lo ", "there"].each do |piece|
          res.print "data: #{{"id" => "s1", "choices" => [{"index" => 0, "delta" => {"content" => piece}, "finish_reason" => nil}]}.to_json}\n\n"
        end
        res.print "data: #{{"id" => "s1", "choices" => [{"index" => 0, "delta" => {} of String => String, "finish_reason" => "stop"}]}.to_json}\n\n"
        res.print "data: [DONE]\n\n"
      elsif json["tools"]? && @tool_round == 0
        @tool_round += 1
        res.print({
          "id" => "t1", "model" => "pygmalion-2-7b",
          "choices" => [{"index" => 0, "finish_reason" => "tool_calls", "message" => {
            "role" => "assistant", "content" => nil,
            "tool_calls" => [{"id" => "call_1", "type" => "function",
                              "function" => {"name" => "get_weather", "arguments" => %({"city":"Paris"})}}],
          }}],
          "usage" => {"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15},
        }.to_json)
      else
        last = json["messages"].as_a.last
        reply = last["role"] == "tool" ? "It is #{last["content"]} in Paris." : "Echo: #{last["content"]}"
        res.print({
          "id" => "c1", "model" => json["model"], "created" => 1_700_000_000,
          "choices" => [{"index" => 0, "finish_reason" => "stop",
                         "logprobs" => nil,
                         "message" => {"role" => "assistant", "content" => reply, "tool_calls" => nil}}],
          "usage" => {"prompt_tokens" => 12, "completion_tokens" => 4, "total_tokens" => 16},
        }.to_json)
      end
    when {"POST", "/v1/completions"}
      res.print %({"choices":[{"index":0,"text":" world","finish_reason":"stop"}]})
    when {"POST", "/v1/embeddings"}
      input = JSON.parse(body)["input"]
      count = input.as_a? ? input.as_a.size : 1
      data = (0...count).map { |i| {"index" => i, "embedding" => [0.1 * (i + 1), 0.2, 0.3]} }
      res.print({"model" => "e", "data" => data, "usage" => {"prompt_tokens" => 3, "total_tokens" => 3}}.to_json)
    when {"POST", "/v1/tokenize"}
      res.print %({"tokens":[1,22,333],"count":3})
    when {"POST", "/v1/detokenize"}
      res.print %({"text":"hello"})
    else
      res.status_code = 404
      res.print %({"error":"not found"})
    end
  end
end

private def with_mock(&)
  server = MockPygmalionServer.new
  begin
    yield server
  ensure
    server.close
  end
end

private def fast_agent(url : String, model = "pygmalion-2-7b") : PygmalionAgent::Agent
  agent = PygmalionAgent.create_agent(model, url)
  agent.config.api.max_retries = 1
  agent.config.api.timeout = 5.seconds
  agent
end

describe PygmalionAgent::Agent do
  it "connects and lists models from /v1/models" do
    with_mock do |server|
      agent = fast_agent(server.url)
      agent.initialize_agent.should be_true
      agent.connected?.should be_true
      agent.models.should eq(["pygmalion-2-7b", "mythalion-13b"])
      agent.status["agent_status"].should eq("connected")
    end
  end

  it "reports a JSON health payload" do
    with_mock do |server|
      health = fast_agent(server.url).health
      health.healthy?.should be_true
      health.model.should eq("pygmalion-2-7b")
    end
  end

  it "treats Aphrodite's empty 200 /health body as healthy" do
    with_mock do |server|
      server.health_body = ""
      fast_agent(server.url).health.healthy?.should be_true
    end
  end

  it "sends an OpenAI-compatible chat request and records the reply" do
    with_mock do |server|
      agent = fast_agent(server.url)
      agent.chat("hi there").should eq("Echo: hi there")

      method, path, _, _ = server.requests.last
      {method, path}.should eq({"POST", "/v1/chat/completions"})
      body = server.last_body
      body["model"].should eq("pygmalion-2-7b")
      body["messages"].as_a.last["content"].should eq("hi there")
      body["temperature"]?.should_not be_nil
      agent.conversation_history.map(&.role).should eq(["user", "assistant"])
    end
  end

  it "streams server-sent events chunk by chunk" do
    with_mock do |server|
      agent = fast_agent(server.url)
      pieces = [] of String
      agent.chat_stream("stream please") { |p| pieces << p }.should eq("Hello there")
      pieces.should eq(["Hel", "lo ", "there"])
      server.last_body["stream"].should eq(true)
    end
  end

  it "runs a tool-call round trip" do
    with_mock do |server|
      agent = fast_agent(server.url)
      params = PygmalionAgent::ToolParameters.new
      params.add_string("city", "City name", required: true)
      tool = PygmalionAgent::ToolDefinition.new("get_weather", "Get weather", params)
      calls = [] of String
      reply = agent.chat_with_tools("weather in Paris?", [tool]) do |call|
        calls << call.parsed_arguments["city"].as_s
        "sunny"
      end
      calls.should eq(["Paris"])
      reply.should eq("It is sunny in Paris.")
    end
  end

  it "covers completions, embeddings and tokenization endpoints" do
    with_mock do |server|
      agent = fast_agent(server.url)
      agent.complete("hello").should eq(" world")
      agent.embed("x").should eq([0.1, 0.2, 0.3])
      agent.embed_batch(["a", "b"]).size.should eq(2)
      agent.tokenize("hello").tokens.should eq([1, 22, 333])
      agent.count_tokens("hello").should eq(3)
      agent.detokenize([1, 22]).should eq("hello")
    end
  end

  it "sends the bearer token for authenticated backends" do
    with_mock do |server|
      agent = PygmalionAgent.create_authenticated_agent(server.url, "sk-test", "pygmalion-2-7b")
      agent.config.api.max_retries = 1
      agent.chat("hi")
      server.requests.last[2]["Authorization"].should eq("Bearer sk-test")
    end
  end

  it "applies character persona and roleplay stop sequences" do
    with_mock do |server|
      character = PygmalionAgent::CharacterConfig.new(name: "Galatea", personality: "curious")
      agent = PygmalionAgent.create_roleplay_agent(server.url, character)
      agent.config.api.max_retries = 1
      agent.chat("hello")
      body = server.last_body
      body["messages"].as_a.first["role"].should eq("system")
      body["stop"].as_a.map(&.as_s).should contain("\nGalatea:")
    end
  end

  it "raises on non-200 generation responses" do
    with_mock do |server|
      server.fail_chat_with = 500
      expect_raises(Exception, /Generation failed: 500/) { fast_agent(server.url).chat("hi") }
    end
  end

  it "stores the conversation in an attached AtomSpace and reads it back as context" do
    with_mock do |server|
      space = AtomSpace::AtomSpace.new
      agent = fast_agent(server.url)
      agent.attach_atomspace(space)
      agent.chat("cats like fish")
      space.size.should be > 0 # stored automatically after each reply
      agent.get_cognitive_context.should contain("cats")
      size_after_first = space.size
      agent.store_conversation_in_atomspace.should be_true
      space.size.should eq(size_after_first) # nothing new to store
    end
  end

  it "reads backend settings from PYGMALION_* environment variables" do
    with_mock do |server|
      ENV["PYGMALION_API_URL"] = server.url + "/"
      ENV["PYGMALION_API_KEY"] = "sk-env"
      ENV["PYGMALION_MODEL"] = "mythalion-13b"
      begin
        agent = PygmalionAgent.create_default_agent
        agent.config.api.max_retries = 1
        agent.chat("hi")
        server.requests.last[2]["Authorization"].should eq("Bearer sk-env")
        server.last_body["model"].should eq("mythalion-13b")
      ensure
        %w(PYGMALION_API_URL PYGMALION_API_KEY PYGMALION_MODEL).each { |k| ENV.delete(k) }
      end
    end
  end
end

describe CrystalCogIntegration::Manager do
  it "routes the cognitive pipeline through a live Pygmalion backend" do
    with_mock do |server|
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(AtomSpace::AtomSpace.new)
      manager.pygmalion_agent = fast_agent(server.url)
      result = manager.execute_cognitive_pipeline("hello pipeline")
      result["pygmalion_response"]?.should eq("Echo: hello pipeline")
    end
  end

  it "keeps the pipeline running when the backend returns an HTTP error" do
    with_mock do |server|
      server.fail_chat_with = 503
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(AtomSpace::AtomSpace.new)
      manager.pygmalion_agent = fast_agent(server.url)
      result = manager.execute_cognitive_pipeline("hello")
      result["pygmalion_status"]?.should eq("unavailable")
    end
  end
end
