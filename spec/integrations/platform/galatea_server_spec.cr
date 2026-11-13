require "spec"
require "file_utils"
require "http/server"
require "../../../src/integrations/platform/paphos_server"
require "../../../src/integrations/platform/galatea_server"

# Minimal OpenAI-compatible engine: replies with the persona it was given
# and the last user message, so specs can see both reached the model. With
# tool_call set, a request that offers tools gets that call back, and the
# reply to a tool result repeats the result.
class StubEngine
  getter requests = [] of JSON::Any
  property empty_replies = 0
  property tool_call : {String, String}? = nil

  def initialize
    @server = HTTP::Server.new do |ctx|
      body = JSON.parse(ctx.request.body.try(&.gets_to_end) || "{}")
      @requests << body
      ctx.response.content_type = "application/json"
      messages = body["messages"].as_a
      system = messages.find { |m| m["role"] == "system" }.try(&.["content"].as_s) || ""
      last = messages.last["content"].as_s
      if (call = @tool_call) && body["tools"]? && messages.last["role"] != "tool"
        ctx.response.print({"id" => "x", "model" => body["model"], "choices" => [{"index" => 0, "finish_reason" => "tool_calls",
                                                                                  "message" => {"role" => "assistant", "content" => nil, "tool_calls" => [{"id" => "call_1", "type" => "function",
                                                                                                                                                           "function" => {"name" => call[0], "arguments" => call[1]}}]}}]}.to_json)
        next
      end
      reply = if messages.last["role"] == "tool"
                "tool said: #{last}"
              elsif @empty_replies > 0
                @empty_replies -= 1
                ""
              else
                "[#{system.includes?("curious") ? "persona ok" : "no persona"}] you said: #{last}"
              end
      ctx.response.print({"id" => "x", "model" => body["model"], "choices" => [{"index" => 0,
                                                                                "finish_reason" => "stop", "message" => {"role" => "assistant", "content" => reply}}],
                          "usage" => {"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}}.to_json)
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url
    "http://127.0.0.1:#{@address.port}"
  end

  def close
    @server.close
  end
end

class Platform
  getter engine = StubEngine.new
  getter paphos : PaphosBackend::Server
  getter galatea : GalateaFrontend::Server

  def initialize(static_dir : String? = nil)
    @paphos = PaphosBackend::Server.new(requested_port: 0, secret: "paphos-secret").start
    engine_url = @engine.url
    factory = GalateaFrontend::Server::AgentFactory.new do
      agent = PygmalionAgent.create_agent("pygmalion-test", engine_url)
      agent.config.api.max_retries = 1
      agent
    end
    @galatea = GalateaFrontend::Server.new(@paphos.url, factory, requested_port: 0,
      secret: "galatea-secret", static_dir: static_dir).start
  end

  def rpc(method : String, body = {} of String => String, token : String? = nil) : {Int32, JSON::Any}
    headers = HTTP::Headers{"Content-Type" => "application/json", "Connect-Protocol-Version" => "1"}
    headers["Authorization"] = "Bearer #{token}" if token
    res = HTTP::Client.post("#{@galatea.url}/galatea.v1.#{method}", headers: headers, body: body.to_json)
    {res.status_code, JSON.parse(res.body)}
  end

  def close
    @galatea.stop
    @paphos.stop
    @engine.close
  end
end

private def with_platform(static_dir : String? = nil, &)
  platform = Platform.new(static_dir)
  begin
    yield platform
  ensure
    platform.close
  end
end

private def signed_in(p : Platform) : String
  p.rpc("AuthService/SignUp", {"email" => "ada@example.com", "password" => "secret123"})
  _, res = p.rpc("AuthService/SignIn", {"email" => "ada@example.com", "password" => "secret123"})
  res["accessToken"].as_s
end

describe GalateaFrontend::Server do
  it "signs up, signs in and checks the session over Connect JSON" do
    with_platform do |p|
      status, res = p.rpc("AuthService/SignUp", {"email" => "ada@example.com", "password" => "secret123"})
      status.should eq(200)
      res["email"].should eq("ada@example.com")

      status, res = p.rpc("AuthService/SignIn", {"email" => "ada@example.com", "password" => "secret123"})
      status.should eq(200)
      res["tokenType"].should eq("bearer")
      token = res["accessToken"].as_s

      _, check = p.rpc("AuthService/Check", token: token)
      check["email"].should eq("ada@example.com")
      check["sessionId"].as_s.should_not be_empty
    end
  end

  it "returns Connect errors with code and HTTP status" do
    with_platform do |p|
      status, res = p.rpc("BotService/BotAll")
      {status, res["code"].as_s}.should eq({401, "unauthenticated"})

      status, res = p.rpc("AuthService/SignIn", {"email" => "nobody@example.com", "password" => "secret123"})
      {status, res["code"].as_s}.should eq({400, "invalid_argument"})

      status, res = p.rpc("ChatService/ChatSubscribe", {"id" => "x"}, signed_in(p))
      {status, res["code"].as_s}.should eq({501, "unimplemented"})
    end
  end

  it "manages bots backed by Paphos characters" do
    with_platform do |p|
      token = signed_in(p)
      _, created = p.rpc("BotService/BotCreate", {"bot" => {"name" => "Galatea",
                                                            "description" => "A sculpture come to life", "personality" => "warm and curious"}}, token)
      created["bot"]["id"].should eq("galatea")

      _, all = p.rpc("BotService/BotAll", token: token)
      all["bots"].as_a.map(&.["name"].as_s).should eq(["Galatea"])

      _, updated = p.rpc("BotService/BotUpdate", {"id"  => "galatea",
                                                  "bot" => {"description" => "An updated sculpture"}}, token)
      updated["bot"]["description"].should eq("An updated sculpture")

      _, deleted = p.rpc("BotService/BotDelete", {"id" => "galatea"}, token)
      deleted["bot"]["id"].should eq("galatea")
      _, all = p.rpc("BotService/BotAll", token: token)
      all["bots"].as_a.should be_empty
    end
  end

  it "chats end to end: persona reaches the engine and messages persist in Paphos" do
    with_platform do |p|
      p.galatea.atomspace = AtomSpace::AtomSpace.new
      token = signed_in(p)
      p.rpc("BotService/BotCreate", {"bot" => {"name" => "Galatea",
                                               "description" => "A sculpture come to life", "personality" => "warm and curious",
                                               "greeting" => "I have just woken up."}}, token)

      _, created = p.rpc("ChatService/ChatCreate", {"botId" => "galatea"}, token)
      chat_id = created["chat"]["id"].as_s
      created["chat"]["botId"].should eq("galatea")
      created["chat"]["messages"][0]["message"].should eq("I have just woken up.")

      status, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "Hello there"}, token)
      status.should eq(200)
      sent["message"]["sender"].should eq("SENDER_TYPE_BOT")
      sent["message"]["message"].should eq("[persona ok] you said: Hello there")

      # History (greeting) and the new user turn reached the engine.
      roles = p.engine.requests.last["messages"].as_a.map(&.["role"].as_s)
      roles.should eq(["system", "assistant", "user"])

      _, chat = p.rpc("ChatService/ChatGet", {"id" => chat_id}, token)
      chat["chat"]["messages"].as_a.map(&.["sender"].as_s)
        .should eq(["SENDER_TYPE_BOT", "SENDER_TYPE_USER", "SENDER_TYPE_BOT"])
      p.galatea.atomspace.not_nil!.size.should be > 0

      _, all = p.rpc("ChatService/ChatAll", token: token)
      all["chats"].as_a.size.should eq(1)
      p.rpc("ChatService/ChatDelete", {"id" => chat_id}, token)
      _, all = p.rpc("ChatService/ChatAll", token: token)
      all["chats"].as_a.should be_empty
    end
  end

  it "runs /commands against the AtomSpace without calling the model" do
    with_platform do |p|
      token = signed_in(p)
      p.rpc("BotService/BotCreate", {"bot" => {"name" => "Galatea", "description" => "A sculpture come to life"}}, token)
      _, created = p.rpc("ChatService/ChatCreate", {"botId" => "galatea"}, token)
      chat_id = created["chat"]["id"].as_s

      _, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "/inherit cat animal"}, token)
      sent["message"]["message"].as_s.should contain(%(INHERITANCELINK (CONCEPTNODE "cat") (CONCEPTNODE "animal")))
      _, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "/query cat"}, token)
      sent["message"]["message"].as_s.should contain(%(CONCEPTNODE "cat"))
      _, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "/tool query_atoms {\"name\": \"animal\"}"}, token)
      sent["message"]["message"].as_s.should contain(%(CONCEPTNODE "animal"))
      _, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "/tool nope"}, token)
      sent["message"]["message"].as_s.should start_with("error: unknown tool")
      _, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "/tokenize hi"}, token)
      sent["message"]["message"].should eq("error: no engine attached")

      p.engine.requests.should be_empty
      p.galatea.cog_tools.atomspace.get_nodes_by_name("cat").size.should eq(1)
      _, chat = p.rpc("ChatService/ChatGet", {"id" => chat_id}, token)
      senders = chat["chat"]["messages"].as_a.map(&.["sender"].as_s)
      senders.count("SENDER_TYPE_USER").should eq(5)
      senders.last.should eq("SENDER_TYPE_BOT")
    end
  end

  it "lets the model call crystalcog tools when tools are enabled" do
    with_platform do |p|
      p.galatea.tools_enabled = true
      p.engine.tool_call = {"add_inheritance", %({"child": "dog", "parent": "animal"})}
      token = signed_in(p)
      p.rpc("BotService/BotCreate", {"bot" => {"name" => "Galatea", "description" => "A sculpture come to life"}}, token)
      _, created = p.rpc("ChatService/ChatCreate", {"botId" => "galatea"}, token)
      chat_id = created["chat"]["id"].as_s

      _, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "Dogs are animals."}, token)
      sent["message"]["message"].as_s.should eq(%(tool said: => (INHERITANCELINK (CONCEPTNODE "dog") (CONCEPTNODE "animal"))))

      offered = p.engine.requests.first["tools"].as_a.map(&.["function"]["name"].as_s)
      offered.should contain("add_inheritance")
      offered.should contain("pln_reason")
      p.engine.requests.last["messages"].as_a.map(&.["role"].as_s).last(2).should eq(["assistant", "tool"])
      p.galatea.cog_tools.run("list inheritance").should contain(%(CONCEPTNODE "dog"))
    end
  end

  it "retries empty model replies before giving up" do
    with_platform do |p|
      token = signed_in(p)
      p.rpc("BotService/BotCreate", {"bot" => {"name" => "Galatea", "description" => "A sculpture come to life",
                                               "personality" => "warm and curious"}}, token)
      _, created = p.rpc("ChatService/ChatCreate", {"botId" => "galatea"}, token)
      chat_id = created["chat"]["id"].as_s

      p.engine.empty_replies = 2
      _, sent = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "hi"}, token)
      sent["message"]["message"].as_s.should contain("you said: hi")

      p.engine.empty_replies = 5
      status, res = p.rpc("ChatService/ChatSendMessage", {"chatId" => chat_id, "message" => "hi"}, token)
      {status, res["code"].as_s}.should eq({503, "unavailable"})
    end
  end

  it "serves the web app's /api/auth routes with a session cookie" do
    with_platform do |p|
      base = p.galatea.url
      json = HTTP::Headers{"Content-Type" => "application/json"}
      HTTP::Client.get("#{base}/api/health").body.should eq("OK")
      HTTP::Client.post("#{base}/api/auth/signup", headers: json,
        body: {email: "ada@example.com", username: "ada", password: "secret123"}.to_json).status_code.should eq(200)

      bad = HTTP::Client.post("#{base}/api/auth/login", headers: json,
        body: {email: "ada@example.com", password: "nope-nope"}.to_json)
      bad.status_code.should eq(400)
      JSON.parse(bad.body)["error"].as_s.should_not be_empty

      login = HTTP::Client.post("#{base}/api/auth/login", headers: json,
        body: {email: "ada@example.com", password: "secret123"}.to_json)
      cookie = login.cookies[GalateaFrontend::Server::SESSION_COOKIE].value
      with_cookie = HTTP::Headers{"Cookie" => "#{GalateaFrontend::Server::SESSION_COOKIE}=#{cookie}"}
      HTTP::Client.get("#{base}/api/auth/status", headers: with_cookie).body.should eq("true")
      HTTP::Client.get("#{base}/api/auth/status").body.should eq("false")
    end
  end

  it "serves static files with an SPA fallback and no path traversal" do
    dir = File.tempname("galatea-dist")
    Dir.mkdir_p(File.join(dir, "assets"))
    File.write(File.join(dir, "index.html"), "<html>galatea</html>")
    File.write(File.join(dir, "assets", "app.js"), "console.log(1)")
    begin
      with_platform(dir) do |p|
        HTTP::Client.get("#{p.galatea.url}/assets/app.js").body.should eq("console.log(1)")
        HTTP::Client.get("#{p.galatea.url}/chat").body.should eq("<html>galatea</html>")
        HTTP::Client.get("#{p.galatea.url}/../../etc/passwd").body.should eq("<html>galatea</html>")
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
