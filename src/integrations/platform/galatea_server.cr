# Galatea frontend server: serves the galatea.v1 Connect-RPC API defined in
# 9cog/galatea-frontend (shared/galatea/v1/*.proto) over the Connect JSON
# protocol, plus the /api/auth/* routes and static files the React web app
# uses. Accounts, bots and chats live in a Paphos backend; bot replies come
# from a Pygmalion agent talking to an Aphrodite (OpenAI-compatible) engine.
#
# A chat message that starts with "/" is a crystalcog command (see
# CrystalCog::CogChat.command): it runs against the server's AtomSpace and
# its output is stored as the bot's reply. With tools_enabled, the model
# can also call the crystalcog tools (CrystalCog::CogTools) while it replies.

require "http/server"
require "json"
require "./jwt"
require "./paphos_client"
require "../pygmalion_agent"
require "../../cogutil/logger"
require "../../atomspace/atomspace"
require "../../tools/cog_chat"

module GalateaFrontend
  class Server
    SESSION_COOKIE = "galatea_session"
    SESSION_TTL    = 7.days
    CONNECT_PREFIX = "/galatea.v1."

    # Connect error codes and the HTTP status each maps to.
    CONNECT_STATUS = {
      "invalid_argument"  => 400,
      "unauthenticated"   => 401,
      "permission_denied" => 403,
      "not_found"         => 404,
      "already_exists"    => 409,
      "internal"          => 500,
      "unimplemented"     => 501,
      "unavailable"       => 503,
    }

    class ConnectError < Exception
      getter code : String

      def initialize(@code : String, message : String)
        super(message)
      end

      def status : Int32
        CONNECT_STATUS[@code]? || 500
      end
    end

    record Session, email : String, paphos_token : String, session_id : String

    alias AgentFactory = Proc(PygmalionAgent::Agent)

    getter port : Int32 = 0
    property atomspace : AtomSpace::AtomSpace?
    property reply_attempts : Int32 = 3
    property paphos_url : String
    # Engine for the /engine and /tokenize commands.
    property engine : CrystalCog::CogChat::Engine?
    # Let the model call crystalcog tools while replying.
    property tools_enabled : Bool = false
    @server : HTTP::Server?
    @cog_tools : CrystalCog::CogTools?

    def initialize(@paphos_url : String, @agent_factory : AgentFactory,
                   @host : String = "127.0.0.1", @requested_port : Int32 = 8080,
                   @secret : String = ENV["JWT_SECRET"]? || Random::Secure.hex(32),
                   @static_dir : String? = nil)
    end

    def url : String
      "http://#{@host}:#{@port}"
    end

    def start : self
      server = HTTP::Server.new { |ctx| handle(ctx) }
      address = server.bind_tcp(@host, @requested_port)
      @port = address.port
      @server = server
      spawn { server.listen }
      Fiber.yield
      CogUtil::Logger.info("Galatea server listening on #{url} (Paphos: #{@paphos_url})")
      self
    end

    def stop
      @server.try(&.close)
    end

    def handle(ctx : HTTP::Server::Context)
      path = ctx.request.path
      if path.starts_with?(CONNECT_PREFIX)
        connect_call(ctx, path)
      elsif path.starts_with?("/api/")
        web_api(ctx, path)
      else
        static(ctx, path)
      end
    end

    # ================================================== Connect (galatea.v1)

    private def connect_call(ctx, path)
      ctx.response.content_type = "application/json"
      unless ctx.request.method == "POST" || ctx.request.method == "GET"
        raise ConnectError.new("unimplemented", "HTTP method #{ctx.request.method} not supported")
      end
      service, _, method = path.lchop("/galatea.v1.").partition('/')
      body = read_message(ctx)
      result = case {service, method}
               when {"AuthService", "SignUp"}          then sign_up(body)
               when {"AuthService", "SignIn"}          then sign_in(body)
               when {"AuthService", "Check"}           then check(session!(ctx))
               when {"BotService", "BotAll"}           then bot_all(session!(ctx))
               when {"BotService", "BotCreate"}        then bot_create(session!(ctx), body)
               when {"BotService", "BotUpdate"}        then bot_update(session!(ctx), body)
               when {"BotService", "BotDelete"}        then bot_delete(session!(ctx), body)
               when {"ChatService", "ChatAll"}         then chat_all(session!(ctx))
               when {"ChatService", "ChatGet"}         then chat_get(session!(ctx), body)
               when {"ChatService", "ChatCreate"}      then chat_create(session!(ctx), body)
               when {"ChatService", "ChatDelete"}      then chat_delete(session!(ctx), body)
               when {"ChatService", "ChatSendMessage"} then chat_send_message(session!(ctx), body)
               else
                 raise ConnectError.new("unimplemented", "galatea.v1.#{service}/#{method} is not implemented")
               end
      ctx.response.print result.to_json
    rescue ex : ConnectError
      connect_error(ctx, ex.code, ex.message.to_s)
    rescue ex : PaphosBackend::Client::Error
      connect_error(ctx, paphos_code(ex.status), ex.message.to_s)
    rescue ex : IO::Error | Socket::Error
      connect_error(ctx, "unavailable", "backend unavailable: #{ex.message}")
    rescue ex : JSON::ParseException
      connect_error(ctx, "invalid_argument", "invalid JSON: #{ex.message}")
    rescue ex
      CogUtil::Logger.error("Galatea RPC failed: #{ex.class}: #{ex.message}")
      connect_error(ctx, "internal", ex.message.to_s)
    end

    private def connect_error(ctx, code, message)
      ctx.response.status_code = CONNECT_STATUS[code]? || 500
      ctx.response.print({"code" => code, "message" => message}.to_json)
    end

    private def paphos_code(status : Int32) : String
      case status
      when 400           then "invalid_argument"
      when 401           then "unauthenticated"
      when 403           then "permission_denied"
      when 404           then "not_found"
      when 502, 503, 504 then "unavailable"
      else                    "internal"
      end
    end

    # Connect GET requests carry the message in ?message=, POSTs in the body.
    private def read_message(ctx) : JSON::Any
      raw = if ctx.request.method == "GET"
              ctx.request.query_params["message"]? || "{}"
            else
              ctx.request.body.try(&.gets_to_end) || ""
            end
      raw = "{}" if raw.strip.empty?
      json = JSON.parse(raw)
      raise ConnectError.new("invalid_argument", "request message must be a JSON object") unless json.as_h?
      json
    end

    private def str(body : JSON::Any, *keys : String) : String?
      keys.each do |key|
        if value = body.as_h?.try(&.[key]?).try(&.as_s?)
          return value
        end
      end
      nil
    end

    private def required(body : JSON::Any, *keys : String) : String
      value = str(body, *keys)
      raise ConnectError.new("invalid_argument", "#{keys.first} is required") if value.nil? || value.empty?
      value
    end

    # ------------------------------------------------------------ AuthService

    private def sign_up(body)
      email = required(body, "email")
      password = required(body, "password")
      paphos.register(email, password)
      {"id" => email, "email" => email, "confirmationSentAt" => ""}
    end

    private def sign_in(body)
      email = required(body, "email")
      password = required(body, "password")
      token = paphos.login(email, password)
      access, expires_at = issue_session(email, token)
      {"accessToken" => access, "tokenType" => "bearer", "expiresIn" => SESSION_TTL.total_seconds.to_i,
       "expiresAt" => expires_at, "refreshToken" => ""}
    end

    private def check(session)
      {"userId" => session.email, "email" => session.email, "sessionId" => session.session_id}
    end

    private def issue_session(email : String, paphos_token : String) : {String, Int32}
      expires_at = (Time.utc + SESSION_TTL).to_unix
      claims = {"sub" => JSON::Any.new(email), "email" => JSON::Any.new(email),
                "session_id" => JSON::Any.new(Random::Secure.hex(8)),
                "paphos" => JSON::Any.new(paphos_token), "exp" => JSON::Any.new(expires_at)}
      {PygmalionPlatform::JWT.encode(claims, @secret), expires_at.to_i32}
    end

    private def session_from(token : String?) : Session?
      return nil if token.nil? || token.empty?
      claims = PygmalionPlatform::JWT.decode(token, @secret)
      Session.new(claims["email"].as_s, claims["paphos"].as_s, claims["session_id"].as_s)
    rescue PygmalionPlatform::JWT::Error | KeyError | TypeCastError
      nil
    end

    private def session!(ctx) : Session
      bearer = ctx.request.headers["Authorization"]?.try(&.sub(/\A\s*Bearer\s+/i, "").strip)
      token = bearer.presence || ctx.request.cookies[SESSION_COOKIE]?.try(&.value)
      session_from(token) || raise ConnectError.new("unauthenticated", "missing or invalid access token")
    end

    private def paphos(session : Session? = nil) : PaphosBackend::Client
      PaphosBackend::Client.new(@paphos_url, session.try(&.paphos_token))
    end

    # ------------------------------------------------------------- BotService

    private def bot_json(character : JSON::Any)
      {"id" => character["slug"].as_s, "name" => character["name"].as_s,
       "description" => character["description"]?.try(&.as_s?) || "",
       "avatarUrl" => character["avatar_id"]?.try(&.as_s?) || ""}
    end

    private def bot_all(session)
      {"bots" => paphos(session).characters.map { |c| bot_json(c) }}
    end

    # Bot only carries name/description/avatarUrl; Paphos also needs a
    # persona and greeting, which callers may pass as extra Bot fields.
    private def character_attrs(bot : JSON::Any, partial : Bool) : Hash(String, String | Bool | Nil)
      attrs = {} of String => String | Bool | Nil
      name = str(bot, "name")
      description = str(bot, "description")
      attrs["name"] = name if name
      attrs["description"] = description if description
      attrs["avatar_id"] = str(bot, "avatarUrl", "avatar_url") if str(bot, "avatarUrl", "avatar_url")
      persona = str(bot, "personality", "persona")
      greeting = str(bot, "greeting", "firstMessage")
      unless partial
        raise ConnectError.new("invalid_argument", "bot.name is required") unless name
        persona ||= "#{name}: #{description || "a friendly companion"}"
        greeting ||= "Hello! I'm #{name}."
        attrs["description"] ||= "A character named #{name}"
        attrs["visibility"] = str(bot, "visibility") || "private"
      end
      attrs["persona"] = persona if persona
      attrs["greeting"] = greeting if greeting
      attrs["world_scenario"] = str(bot, "scenario") if str(bot, "scenario")
      attrs
    end

    private def bot_create(session, body)
      bot = body["bot"]? || raise ConnectError.new("invalid_argument", "bot is required")
      {"bot" => bot_json(paphos(session).create_character(character_attrs(bot, partial: false)))}
    end

    private def bot_update(session, body)
      id = required(body, "id")
      bot = body["bot"]? || raise ConnectError.new("invalid_argument", "bot is required")
      {"bot" => bot_json(paphos(session).update_character(id, character_attrs(bot, partial: true)))}
    end

    private def bot_delete(session, body)
      id = required(body, "id")
      client = paphos(session)
      existing = client.character(id)
      client.delete_character(id)
      {"bot" => bot_json(existing)}
    end

    # ------------------------------------------------------------ ChatService

    private def message_json(message : JSON::Any)
      sender = message["sender"].as_s == "user" ? "SENDER_TYPE_USER" : "SENDER_TYPE_BOT"
      {"id" => message["id"].to_s, "sender" => sender, "message" => message["content"].as_s,
       "createdAt" => message["created_at"].to_s}
    end

    private def chat_json(session, chat : JSON::Any, client : PaphosBackend::Client, with_messages = true)
      id = chat["id"].as_s
      messages = with_messages ? client.messages(id).map { |m| message_json(m) } : [] of Hash(String, String)
      {"id" => id, "userId" => session.email,
       "botId" => chat["characters"].as_a.first?.try(&.["slug"].as_s) || "",
       "messages" => messages}
    end

    private def chat_all(session)
      client = paphos(session)
      {"chats" => client.chats.map { |c| chat_json(session, c, client, with_messages: false) }}
    end

    private def chat_get(session, body)
      client = paphos(session)
      {"chat" => chat_json(session, client.chat(required(body, "id")), client)}
    end

    private def chat_create(session, body)
      client = paphos(session)
      chat = client.create_chat([required(body, "botId", "bot_id")])
      {"chat" => chat_json(session, chat, client)}
    end

    private def chat_delete(session, body)
      client = paphos(session)
      id = required(body, "id")
      chat = chat_json(session, client.chat(id), client)
      client.delete_chat(id)
      {"chat" => chat}
    end

    private def chat_send_message(session, body)
      client = paphos(session)
      chat_id = required(body, "chatId", "chat_id")
      text = required(body, "message")
      chat = client.chat(chat_id)
      slug = chat["characters"].as_a.first?.try(&.["slug"].as_s) ||
             raise ConnectError.new("invalid_argument", "chat has no bot")
      character = client.character(slug)
      history = client.messages(chat_id)

      client.post_message(chat_id, text)
      reply = text.lstrip.starts_with?('/') ? run_command(text) : generate_reply(character, history, text)
      bot_message = client.post_message(chat_id, reply, "character", slug)
      {"message" => message_json(bot_message)}
    end

    # crystalcog tools over the server's AtomSpace.
    def cog_tools : CrystalCog::CogTools
      @cog_tools ||= begin
        @atomspace ||= AtomSpace::AtomSpace.new
        CrystalCog::CogTools.new(@atomspace.not_nil!)
      end
    end

    private def run_command(text : String) : String
      CrystalCog::CogChat.command(text, cog_tools, @engine)
    rescue ex
      "error: #{ex.message}"
    end

    private def tool_definitions : Array(PygmalionAgent::ToolDefinition)
      cog_tools.tools.map do |tool|
        params = PygmalionAgent::ToolParameters.new
        tool.params.each do |p|
          if p.type == "array"
            params.add_array(p.name, p.description, "string", p.required)
          else
            params.add_property(p.name, PygmalionAgent::ParameterProperty.new(p.type, p.description), p.required)
          end
        end
        PygmalionAgent::ToolDefinition.new(tool.name, tool.description, params)
      end
    end

    private def generate_reply(character : JSON::Any, history : Array(JSON::Any), text : String) : String
      name = character["name"].as_s
      agent = @agent_factory.call
      agent.attach_atomspace(@atomspace.not_nil!) if @atomspace
      agent.set_character(PygmalionAgent::CharacterConfig.new(
        name: name,
        description: character["description"]?.try(&.as_s?) || "",
        personality: character["persona"]?.try(&.as_s?) || "",
        scenario: character["world_scenario"]?.try(&.as_s?) || ""
      ))
      history.each do |m|
        content = m["content"].as_s
        if m["sender"].as_s == "user"
          agent.conversation_history << PygmalionAgent::ChatMessage.user(content, agent.user_name)
        else
          agent.conversation_history << PygmalionAgent::ChatMessage.assistant(content, name)
        end
      end

      base = agent.conversation_history.dup
      tools = @tools_enabled ? tool_definitions : nil
      @reply_attempts.times do
        agent.conversation_history = base.dup
        reply = if tools
                  agent.chat_with_tools(text, tools) do |call|
                    begin
                      cog_tools.call(call.function_name, call.function_arguments)
                    rescue ex
                      "error: #{ex.message}"
                    end
                  end
                else
                  agent.chat(text)
                end.strip
        return reply unless reply.empty?
      end
      raise ConnectError.new("unavailable", "the model returned an empty reply #{@reply_attempts} times")
    rescue ex : PygmalionAgent::BackendError
      raise ConnectError.new("unavailable", "inference backend error: #{ex.message}")
    end

    # ================================================ web app /api/* routes

    private def web_api(ctx, path)
      ctx.response.content_type = "application/json"
      case {ctx.request.method, path}
      when {"GET", "/api/health"}
        ctx.response.content_type = "text/plain"
        ctx.response.print "OK"
      when {"POST", "/api/auth/signup"}
        body = read_message(ctx)
        paphos.register(required(body, "email"), required(body, "password"))
        ctx.response.print({"message" => "Signed up"}.to_json)
      when {"POST", "/api/auth/login"}
        body = read_message(ctx)
        email = required(body, "email")
        token = paphos.login(email, required(body, "password"))
        access, _ = issue_session(email, token)
        ctx.response.cookies << HTTP::Cookie.new(SESSION_COOKIE, access, path: "/", http_only: true,
          samesite: HTTP::Cookie::SameSite::Lax, max_age: SESSION_TTL)
        ctx.response.print({"message" => "Logged in", "user" => {"email" => email}}.to_json)
      when {"GET", "/api/auth/status"}
        ctx.response.print (!session_from(ctx.request.cookies[SESSION_COOKIE]?.try(&.value)).nil?).to_json
      when {"GET", "/api/auth/logout"}
        ctx.response.cookies << HTTP::Cookie.new(SESSION_COOKIE, "", path: "/", max_age: 0.seconds)
        ctx.response.print({"message" => "Logged out"}.to_json)
      else
        ctx.response.status_code = 404
        ctx.response.print({"error" => "Not found"}.to_json)
      end
    rescue ex : PaphosBackend::Client::Error
      ctx.response.status_code = ex.status == 401 ? 401 : 400
      ctx.response.print({"message" => "Request failed", "error" => ex.message}.to_json)
    rescue ex : ConnectError
      ctx.response.status_code = ex.status
      ctx.response.print({"message" => "Request failed", "error" => ex.message}.to_json)
    rescue ex : IO::Error | Socket::Error
      ctx.response.status_code = 503
      ctx.response.print({"message" => "Backend unavailable", "error" => ex.message}.to_json)
    end

    # ===================================================== static web app

    MIME = {".html" => "text/html; charset=utf-8", ".js" => "text/javascript", ".css" => "text/css",
            ".svg" => "image/svg+xml", ".png" => "image/png", ".jpg" => "image/jpeg",
            ".ico" => "image/x-icon", ".json" => "application/json", ".webp" => "image/webp",
            ".woff2" => "font/woff2", ".txt" => "text/plain"}

    # Serve the built React app (web/dist) with an SPA fallback to index.html.
    private def static(ctx, path)
      root = @static_dir
      unless root && Dir.exists?(root) && {"GET", "HEAD"}.includes?(ctx.request.method)
        ctx.response.status_code = 404
        ctx.response.print "Not found"
        return
      end
      clean = Path.posix(URI.decode(path)).normalize.to_s
      file = File.join(root, clean.lchop("/"))
      inside = File.expand_path(file).starts_with?(File.expand_path(root))
      file = File.join(root, "index.html") unless inside && File.file?(file)
      ctx.response.content_type = MIME[File.extname(file)]? || "application/octet-stream"
      File.open(file) { |io| IO.copy(io, ctx.response) }
    end
  end
end
