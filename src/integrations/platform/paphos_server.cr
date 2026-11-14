# Paphos backend server: a Crystal implementation of the 9cog/paphos-backend
# REST contract (/api/v1, Lucky-style param keys, HS256 JWT bearer auth,
# {message,param,details} errors), extended with chat messages, which the
# upstream skeleton does not have yet.
#
# Storage is in memory, optionally persisted to a JSON file so the server can
# run without PostgreSQL.

require "http/server"
require "json"
require "uuid"
require "crypto/bcrypt/password"
require "./jwt"
require "../../cogutil/logger"

module PaphosBackend
  class Server
    API_PREFIX   = "/api/v1"
    VISIBILITIES = %w(public unlisted private)

    class ApiError < Exception
      getter status : Int32
      getter param : String?

      def initialize(@status : Int32, message : String, @param : String? = nil, @details : String? = nil)
        super(message)
      end

      def details : String
        @details || message.to_s
      end
    end

    record User, id : Int64, email : String, password_hash : String

    class Character
      include JSON::Serializable
      property slug : String
      property owner_id : Int64
      property name : String
      property description : String
      property avatar_id : String?
      property greeting : String
      property persona : String
      property world_scenario : String?
      property example_chats : String?
      property visibility : String
      property is_contentious : Bool

      def initialize(@slug, @owner_id, @name, @description, @avatar_id, @greeting, @persona,
                     @world_scenario, @example_chats, @visibility, @is_contentious)
      end

      def summary
        {"slug" => slug, "name" => name, "description" => description, "avatar_id" => avatar_id}
      end

      def full
        summary.merge({"greeting" => greeting, "persona" => persona, "world_scenario" => world_scenario,
                       "example_chats" => example_chats, "visibility" => visibility,
                       "is_contentious" => is_contentious})
      end
    end

    class Chat
      include JSON::Serializable
      property id : String
      property owner_id : Int64
      property name : String?
      property character_slugs : Array(String)

      def initialize(@id, @owner_id, @name, @character_slugs)
      end
    end

    class Message
      include JSON::Serializable
      property id : Int64
      property chat_id : String
      property sender : String # "user" | "character"
      property character_slug : String?
      property content : String
      property created_at : Int64

      def initialize(@id, @chat_id, @sender, @character_slug, @content, @created_at)
      end

      def to_h
        {"id" => id, "sender" => sender, "character_slug" => character_slug,
         "content" => content, "created_at" => created_at}
      end
    end

    # A named document a user stores: cognitive state, an exported
    # AtomSpace, any string fields. (Not part of upstream Paphos.)
    class Snapshot
      include JSON::Serializable
      property key : String
      property owner_id : Int64
      property data : Hash(String, String)
      property updated_at : Int64

      def initialize(@key, @owner_id, @data, @updated_at)
      end

      def summary
        {"key" => key, "updated_at" => updated_at, "bytes" => data.sum { |k, v| k.bytesize + v.bytesize }}
      end

      def full
        {"key" => key, "updated_at" => updated_at, "data" => data}
      end
    end

    class Store
      include JSON::Serializable
      property snapshots = [] of Snapshot
      property users = [] of Hash(String, String)
      property characters = [] of Character
      property chats = [] of Chat
      property messages = [] of Message
      property next_user_id : Int64 = 1
      property next_message_id : Int64 = 1
      # The most recent events, oldest first, and the id the next one gets.
      # Ids keep counting across restarts so a client's "after" still works.
      # Events are written to their own journal file, one line each, not
      # with the rest of the store; a store file that has them is still read.
      @[JSON::Field(ignore_serialize: true)]
      property events = [] of Event
      property next_event_id : Int64 = 1

      def initialize
      end
    end

    # Something that happened, published by a client or by the server. The
    # last `EVENT_LIMIT` are kept, in the data file when there is one.
    record Event, id : Int64, owner_id : Int64, type : String, source : String,
      data : Hash(String, String), created_at : Int64 do
      include JSON::Serializable

      def to_h
        {"id" => id, "type" => type, "source" => source, "data" => data, "created_at" => created_at}
      end
    end

    # A service function clients can call by name with string arguments.
    record Action, name : String, description : String,
      handler : Proc(Hash(String, String), Int64, Hash(String, String))

    # Raised by an action that cannot do what it was asked.
    class ActionError < Exception
    end

    # Events kept per server; older ones are dropped.
    EVENT_LIMIT = 1000
    # Longest a GET /events?wait= request is held open.
    EVENT_WAIT_LIMIT = 25.seconds

    # How often an open event stream gets a comment line when nothing
    # happens. Writing is how the server notices a client that went away.
    property stream_keepalive : Time::Span = 15.seconds
    # Event streams being served now.
    getter active_streams = 0
    @stopped = false
    # Lines in the journal file, to know when to cut it back.
    @journal_lines = 0

    getter port : Int32 = 0
    @actions = {} of String => Action
    @store : Store
    @users = {} of Int64 => User
    @mutex = Mutex.new
    @server : HTTP::Server?

    def initialize(@host : String = "127.0.0.1", @requested_port : Int32 = 3000,
                   @secret : String = ENV["SECRET_KEY_BASE"]? || Random::Secure.hex(32),
                   @data_file : String? = nil)
      @store = load_store
      load_journal
      @store.users.each do |u|
        user = User.new(u["id"].to_i64, u["email"], u["password_hash"])
        @users[user.id] = user
      end
      register_builtin_actions
    end

    # Add a service function. The block gets the caller's arguments and
    # user id and returns the result fields; it raises `ActionError` to
    # refuse. Registering a name again replaces the function.
    def register_action(name : String, description : String = "",
                        &handler : Hash(String, String), Int64 -> Hash(String, String)) : Nil
      unless name.matches?(ACTION_NAME)
        raise ArgumentError.new("action names are 1-100 characters of A-Z a-z 0-9 . _ : -")
      end
      @actions[name] = Action.new(name, description, handler)
    end

    # Record an event for a user, as POST /events does.
    def publish_event(owner_id : Int64, type : String, data : Hash(String, String), source : String = "paphos") : Event
      @mutex.synchronize do
        event = Event.new(@store.next_event_id, owner_id, type, source, data, Time.utc.to_unix_ms)
        @store.next_event_id += 1
        @store.events << event
        @store.events.shift if @store.events.size > EVENT_LIMIT
        journal(event)
        event
      end
    end

    def url : String
      url_for(@host, @port)
    end

    def url_for(host : String, port : Int32) : String
      "http://#{host}:#{port}#{API_PREFIX}"
    end

    # Bind and serve in a background fiber; returns once the port is bound.
    def start : self
      server = HTTP::Server.new { |ctx| handle(ctx) }
      address = server.bind_tcp(@host, @requested_port)
      @port = address.port
      @server = server
      @stopped = false
      spawn { server.listen }
      Fiber.yield
      CogUtil::Logger.info("Paphos backend listening on #{url}")
      self
    end

    def stop
      @stopped = true
      @server.try(&.close)
    end

    # Issue a token for a user id (used by tests and trusted callers).
    def token_for(user_id : Int64) : String
      PygmalionPlatform::JWT.encode({"user_id" => JSON::Any.new(user_id)}, @secret)
    end

    def handle(ctx : HTTP::Server::Context)
      ctx.response.content_type = "application/json"
      path = ctx.request.path
      unless path == API_PREFIX || path.starts_with?("#{API_PREFIX}/")
        raise ApiError.new(404, "Not found", nil, "No route for #{path}")
      end
      route(ctx, path.lchop(API_PREFIX).rchop("/"), ctx.request.method)
    rescue ex : ApiError
      error(ctx, ex.status, ex.message, ex.param, ex.details)
    rescue ex : JSON::ParseException
      error(ctx, 400, "Invalid JSON", nil, ex.message)
    rescue ex
      CogUtil::Logger.error("Paphos request failed: #{ex.class}: #{ex.message}")
      error(ctx, 500, "Something went wrong.", nil, ex.message)
    end

    private def error(ctx, status, message, param, details)
      ctx.response.status_code = status
      ctx.response.print({"message" => message, "param" => param, "details" => details}.to_json)
    end

    private def route(ctx, path : String, method : String)
      seg = path.split('/', remove_empty: true)
      case {method, seg.size, seg[0]?, seg[1]?, seg[2]?}
      when {"GET", 0, nil, nil, nil}
        respond(ctx, {"hello" => "Hello World from Home::Index"})
      when {"POST", 2, "users", "register", nil}
        register(ctx)
      when {"POST", 2, "users", "login", nil}
        login(ctx)
      when {"GET", 1, "characters", nil, nil}
        list_characters(ctx, current_user(ctx))
      when {"POST", 1, "characters", nil, nil}
        create_character(ctx, current_user(ctx))
      when {"GET", 1, "chats", nil, nil}
        list_chats(ctx, current_user(ctx))
      when {"POST", 1, "chats", nil, nil}
        create_chat(ctx, current_user(ctx))
      else
        if seg.size == 2 && seg[0] == "characters"
          character_member(ctx, method, seg[1], current_user(ctx))
        elsif seg.size == 2 && seg[0] == "chats"
          chat_member(ctx, method, seg[1], current_user(ctx))
        elsif seg.size == 3 && seg[0] == "chats" && seg[2] == "messages"
          chat_messages(ctx, method, seg[1], current_user(ctx))
        elsif seg.size == 1 && seg[0] == "snapshots" && method == "GET"
          list_snapshots(ctx, current_user(ctx))
        elsif seg.size == 2 && seg[0] == "snapshots"
          snapshot_member(ctx, method, URI.decode(seg[1]), current_user(ctx))
        elsif seg.size == 1 && seg[0] == "events" && method == "GET"
          list_events(ctx, current_user(ctx))
        elsif seg.size == 1 && seg[0] == "events" && method == "POST"
          create_event(ctx, current_user(ctx))
        elsif seg.size == 2 && seg[0] == "events" && seg[1] == "stream" && method == "GET"
          stream_events(ctx, current_user(ctx))
        elsif seg.size == 1 && seg[0] == "actions" && method == "GET"
          respond(ctx, {"actions" => @actions.values.sort_by(&.name).map { |action|
            {"name" => action.name, "description" => action.description}
          }})
        elsif seg.size == 2 && seg[0] == "actions" && method == "POST"
          call_action(ctx, URI.decode(seg[1]), current_user(ctx))
        else
          not_found(ctx.request.path)
        end
      end
    end

    # ---------------------------------------------------------------- auth

    private def register(ctx)
      params = param_key(ctx, "user")
      email = required_string(params, "email").strip.downcase
      password = required_string(params, "password")
      confirmation = params["password_confirmation"]?.try(&.as_s?)
      raise ApiError.new(400, "Invalid params", "email", "email is invalid") unless email.includes?('@')
      unless (6..72).includes?(password.size)
        raise ApiError.new(400, "Invalid params", "password", "password must be 6-72 characters")
      end
      if confirmation && confirmation != password
        raise ApiError.new(400, "Invalid params", "password_confirmation", "password_confirmation must match")
      end

      user = @mutex.synchronize do
        if @users.values.any? { |u| u.email == email }
          raise ApiError.new(400, "Invalid params", "email", "email is already taken")
        end
        u = User.new(@store.next_user_id, email, Crypto::Bcrypt::Password.create(password).to_s)
        @store.next_user_id += 1
        @users[u.id] = u
        @store.users << {"id" => u.id.to_s, "email" => u.email, "password_hash" => u.password_hash}
        persist
        u
      end
      respond(ctx, {"token" => token_for(user.id)})
    end

    private def login(ctx)
      params = param_key(ctx, "user")
      email = required_string(params, "email").strip.downcase
      password = required_string(params, "password")
      user = @users.values.find { |u| u.email == email }
      raise ApiError.new(400, "Invalid params", "email", "email is not in our system") unless user
      unless Crypto::Bcrypt::Password.new(user.password_hash).verify(password)
        raise ApiError.new(400, "Invalid params", "password", "password is wrong")
      end
      respond(ctx, {"token" => token_for(user.id)})
    end

    private def current_user(ctx) : User
      raw = ctx.request.headers["Authorization"]? || ctx.request.query_params["auth_token"]?
      token = raw.try(&.sub(/\A\s*Bearer\s*/i, "").strip)
      raise ApiError.new(401, "Not authenticated.", nil, "missing auth token") if token.nil? || token.empty?
      claims = PygmalionPlatform::JWT.decode(token, @secret)
      user_id = claims["user_id"]?.try(&.as_i64?)
      @users[user_id]? || raise ApiError.new(401, "Not authenticated.", nil, "unknown user")
    rescue ex : PygmalionPlatform::JWT::Error
      raise ApiError.new(401, "Not authenticated.", nil, ex.message)
    end

    # ---------------------------------------------------------- characters

    private def visible_to?(character : Character, user : User) : Bool
      character.visibility != "private" || character.owner_id == user.id
    end

    private def list_characters(ctx, user)
      list = @store.characters.select { |c| c.visibility == "public" || c.owner_id == user.id }
      respond(ctx, {"characters" => list.map(&.summary)})
    end

    private def create_character(ctx, user)
      params = param_key(ctx, "character")
      name = bounded(params, "name", 1, 32, required: true).not_nil!
      character = Character.new(
        slug: "",
        owner_id: user.id,
        name: name,
        description: bounded(params, "description", 8, 64, required: true).not_nil!,
        avatar_id: params["avatar_id"]?.try(&.as_s?),
        greeting: bounded(params, "greeting", 2, 1024, required: true).not_nil!,
        persona: bounded(params, "persona", 12, 1024, required: true).not_nil!,
        world_scenario: bounded(params, "world_scenario", 0, 512),
        example_chats: bounded(params, "example_chats", 0, 1024),
        visibility: visibility(params) || "private",
        is_contentious: params["is_contentious"]?.try(&.as_bool?) || false
      )
      @mutex.synchronize do
        character.slug = unique_slug(name)
        @store.characters << character
        persist
      end
      respond(ctx, {"character" => character.full})
    end

    private def character_member(ctx, method, slug, user)
      character = @store.characters.find { |c| c.slug == slug && visible_to?(c, user) }
      raise ApiError.new(404, "Not found", nil, "character #{slug} not found") unless character
      case method
      when "GET"
        respond(ctx, {"character" => character.full})
      when "PATCH", "PUT"
        require_owner(character.owner_id, user)
        params = param_key(ctx, "character")
        @mutex.synchronize do
          bounded(params, "name", 1, 32).try { |v| character.name = v }
          bounded(params, "description", 8, 64).try { |v| character.description = v }
          bounded(params, "greeting", 2, 1024).try { |v| character.greeting = v }
          bounded(params, "persona", 12, 1024).try { |v| character.persona = v }
          character.world_scenario = bounded(params, "world_scenario", 0, 512) if params.has_key?("world_scenario")
          character.example_chats = bounded(params, "example_chats", 0, 1024) if params.has_key?("example_chats")
          character.avatar_id = params["avatar_id"]?.try(&.as_s?) if params.has_key?("avatar_id")
          visibility(params).try { |v| character.visibility = v }
          params["is_contentious"]?.try(&.as_bool?).try { |v| character.is_contentious = v }
          persist
        end
        respond(ctx, {"character" => character.full})
      when "DELETE"
        require_owner(character.owner_id, user)
        @mutex.synchronize do
          @store.characters.delete(character)
          persist
        end
        ctx.response.print ""
      else
        not_found(ctx.request.path)
      end
    end

    private def unique_slug(name : String) : String
      base = name.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
      base = "character" if base.empty?
      slug = base
      n = 1
      while @store.characters.any? { |c| c.slug == slug }
        n += 1
        slug = "#{base}-#{n}"
      end
      slug
    end

    # --------------------------------------------------------------- chats

    private def chat_json(chat : Chat)
      characters = chat.character_slugs.compact_map { |s| @store.characters.find { |c| c.slug == s } }
      {"id" => chat.id, "name" => chat.name, "characters" => characters.map(&.summary)}
    end

    private def list_chats(ctx, user)
      respond(ctx, {"chats" => @store.chats.select { |c| c.owner_id == user.id }.map { |c| chat_json(c) }})
    end

    private def create_chat(ctx, user)
      params = param_key(ctx, "chat")
      slugs = params["character_slugs"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      raise ApiError.new(400, "Invalid params", "character_slugs", "at least one character is required") if slugs.empty?
      slugs.each do |slug|
        unless @store.characters.any? { |c| c.slug == slug && visible_to?(c, user) }
          raise ApiError.new(400, "Invalid params", "character_slugs", "unknown character #{slug}")
        end
      end
      chat = Chat.new(UUID.random.to_s, user.id, bounded(params, "name", 1, 32), slugs)
      @mutex.synchronize do
        @store.chats << chat
        # Seed the conversation with each character's greeting.
        slugs.each do |slug|
          if character = @store.characters.find { |c| c.slug == slug }
            add_message(chat.id, "character", slug, character.greeting)
          end
        end
        persist
      end
      respond(ctx, {"chat" => chat_json(chat)})
    end

    private def find_chat(id, user) : Chat
      chat = @store.chats.find { |c| c.id == id }
      raise ApiError.new(404, "Not found", nil, "chat #{id} not found") unless chat
      require_owner(chat.owner_id, user)
      chat
    end

    private def chat_member(ctx, method, id, user)
      chat = find_chat(id, user)
      case method
      when "GET"
        respond(ctx, {"chat" => chat_json(chat)})
      when "PATCH", "PUT"
        params = param_key(ctx, "chat")
        @mutex.synchronize do
          name = params["name"]?.try(&.as_s?)
          chat.name = (name.nil? || name == "null") ? nil : bounded(params, "name", 1, 32)
          persist
        end
        respond(ctx, {"chat" => chat_json(chat)})
      when "DELETE"
        @mutex.synchronize do
          @store.chats.delete(chat)
          @store.messages.reject! { |m| m.chat_id == chat.id }
          persist
        end
        ctx.response.print ""
      else
        not_found(ctx.request.path)
      end
    end

    private def chat_messages(ctx, method, id, user)
      chat = find_chat(id, user)
      case method
      when "GET"
        list = @store.messages.select { |m| m.chat_id == chat.id }
        respond(ctx, {"messages" => list.map(&.to_h)})
      when "POST"
        params = param_key(ctx, "message")
        content = required_string(params, "content")
        raise ApiError.new(400, "Invalid params", "content", "content can't be blank") if content.strip.empty?
        sender = params["sender"]?.try(&.as_s?) || "user"
        unless {"user", "character"}.includes?(sender)
          raise ApiError.new(400, "Invalid params", "sender", "sender must be user or character")
        end
        slug = params["character_slug"]?.try(&.as_s?)
        if sender == "character" && !chat.character_slugs.includes?(slug)
          raise ApiError.new(400, "Invalid params", "character_slug", "character is not in this chat")
        end
        message = @mutex.synchronize do
          m = add_message(chat.id, sender, slug, content)
          persist
          m
        end
        respond(ctx, {"message" => message.to_h})
      else
        not_found(ctx.request.path)
      end
    end

    # ----------------------------------------------------------- snapshots

    SNAPSHOT_KEY = /\A[A-Za-z0-9._:-]{1,200}\z/

    # GET /snapshots lists the caller's snapshots; query parameters keep
    # only those whose data has the given field values.
    private def list_snapshots(ctx, user)
      filters = ctx.request.query_params.to_h
      mine = @store.snapshots.select do |snapshot|
        snapshot.owner_id == user.id && filters.all? { |field, value| snapshot.data[field]? == value }
      end
      respond(ctx, {"snapshots" => mine.sort_by(&.key).map(&.summary)})
    end

    private def snapshot_member(ctx, method, key : String, user)
      unless key.matches?(SNAPSHOT_KEY)
        raise ApiError.new(400, "Invalid params", "key", "key must be 1-200 characters of A-Z a-z 0-9 . _ : -")
      end
      existing = @store.snapshots.find { |snapshot| snapshot.owner_id == user.id && snapshot.key == key }
      case method
      when "GET"
        respond(ctx, {"snapshot" => (existing || not_found(ctx.request.path)).full})
      when "PUT"
        params = param_key(ctx, "snapshot")
        fields = params["data"]?.try(&.as_h?) || raise ApiError.new(400, "Invalid params", "data", "data must be an object")
        data = fields.to_h do |field, value|
          {field, value.as_s? || raise ApiError.new(400, "Invalid params", "data", "data.#{field} must be a string")}
        end
        snapshot = @mutex.synchronize do
          saved = existing
          if saved
            saved.data = data
            saved.updated_at = Time.utc.to_unix_ms
          else
            saved = Snapshot.new(key, user.id, data, Time.utc.to_unix_ms)
            @store.snapshots << saved
          end
          persist
          saved
        end
        respond(ctx, {"snapshot" => snapshot.summary})
      when "DELETE"
        found = existing || not_found(ctx.request.path)
        @mutex.synchronize do
          @store.snapshots.delete(found)
          persist
        end
        respond(ctx, {"snapshot" => found.summary})
      else
        not_found(ctx.request.path)
      end
    end

    private def add_message(chat_id, sender, slug, content) : Message
      message = Message.new(@store.next_message_id, chat_id, sender, slug, content, Time.utc.to_unix_ms)
      @store.next_message_id += 1
      @store.messages << message
      message
    end

    # -------------------------------------------------------------- events

    EVENT_TYPE = /\A[A-Za-z0-9._:-]{1,100}\z/

    # POST /events {"event": {"type", "source"?, "data"?: {string: string}}}
    private def create_event(ctx, user)
      params = param_key(ctx, "event")
      type = required_string(params, "type")
      unless type.matches?(EVENT_TYPE)
        raise ApiError.new(400, "Invalid params", "type", "type must be 1-100 characters of A-Z a-z 0-9 . _ : -")
      end
      source = params["source"]?.try(&.as_s?) || "client"
      event = publish_event(user.id, type, string_fields(params["data"]?, "data"), source)
      ctx.response.status_code = 201
      respond(ctx, {"event" => event.to_h})
    end

    # GET /events lists the caller's events with an id above `after`,
    # oldest first. `types` (comma-separated) keeps only those types and
    # `limit` caps the count. With `wait` (seconds) the request is held
    # until an event arrives or the time is up, so a client can follow the
    # stream by asking again with the last id it saw.
    private def list_events(ctx, user)
      query = ctx.request.query_params
      after = query["after"]?.try(&.to_i64?) || 0_i64
      types = query["types"]?.try(&.split(',', remove_empty: true))
      limit = (query["limit"]?.try(&.to_i?) || 100).clamp(1, EVENT_LIMIT)
      wait = (query["wait"]?.try(&.to_f?) || 0.0).clamp(0.0, EVENT_WAIT_LIMIT.total_seconds).seconds

      deadline = Time.monotonic + wait
      matching = events_for(user.id, after, types, limit)
      while matching.empty? && Time.monotonic < deadline
        sleep 20.milliseconds
        matching = events_for(user.id, after, types, limit)
      end
      respond(ctx, {"events" => matching.map(&.to_h), "last_id" => matching.last?.try(&.id) || after})
    end

    # GET /events/stream sends the caller's events as server-sent events:
    # first those with an id above `after` (or above the Last-Event-ID
    # header a reconnecting client sends), then each new one as it is
    # published, until the client goes away. `types` filters as for
    # GET /events. Each event is
    #
    #   id: 17
    #   event: atom_updates
    #   data: {"id":17,"type":"atom_updates","source":...,"data":{...}}
    private def stream_events(ctx, user)
      query = ctx.request.query_params
      after = query["after"]?.try(&.to_i64?) || ctx.request.headers["Last-Event-ID"]?.try(&.to_i64?) || 0_i64
      types = query["types"]?.try(&.split(',', remove_empty: true))

      response = ctx.response
      response.content_type = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"

      # Counted before the first write, so a client that has the response
      # can rely on the count.
      @active_streams += 1
      last_write = Time.monotonic
      # The id the next event gets, as of the last look: nothing is
      # searched while it stands still.
      looked_at = 0_i64
      begin
        response.print ": stream open\n\n"
        response.flush
        until @stopped
          upcoming = @store.next_event_id
          pending = upcoming == looked_at ? [] of Event : events_for(user.id, after, types, EVENT_LIMIT)
          looked_at = upcoming
          if pending.empty?
            if Time.monotonic - last_write >= @stream_keepalive
              response.print ": keep-alive\n\n"
              response.flush
              last_write = Time.monotonic
            end
            sleep 20.milliseconds
            next
          end

          pending.each do |event|
            response.print "id: #{event.id}\nevent: #{event.type}\ndata: #{event.to_h.to_json}\n\n"
            after = event.id
          end
          response.flush
          last_write = Time.monotonic
        end
      rescue IO::Error
        # The client closed the connection.
      ensure
        @active_streams -= 1
      end
    end

    private def events_for(owner_id : Int64, after : Int64, types : Array(String)?, limit : Int32) : Array(Event)
      @mutex.synchronize do
        @store.events.select do |event|
          event.owner_id == owner_id && event.id > after && (types.nil? || types.includes?(event.type))
        end.first(limit)
      end
    end

    # ------------------------------------------------------------- actions

    ACTION_NAME = /\A[A-Za-z0-9._:-]{1,100}\z/

    # POST /actions/:name {"action": {"args"?: {string: string}}} runs a
    # service function and records an `action_executed` event.
    private def call_action(ctx, name : String, user)
      action = @actions[name]? || raise ApiError.new(404, "Not found", "name", "No action named #{name}")
      params = param_key(ctx, "action")
      args = string_fields(params["args"]?, "args")
      result = begin
        action.handler.call(args, user.id)
      rescue ex : ActionError
        publish_event(user.id, "action_executed", {"action" => name, "status" => "refused"})
        raise ApiError.new(422, "Action refused", name, ex.message)
      end
      publish_event(user.id, "action_executed", {"action" => name, "status" => "success"})
      respond(ctx, {"action" => name, "result" => result})
    end

    private def register_builtin_actions : Nil
      register_action("echo", "Return the arguments unchanged") { |args, _user| args }

      register_action("stats", "Count the caller's characters, chats, messages, snapshots and events") do |_args, user|
        chats = @store.chats.select { |chat| chat.owner_id == user }
        chat_ids = chats.map(&.id).to_set
        {
          "characters" => @store.characters.count { |character| character.owner_id == user }.to_s,
          "chats"      => chats.size.to_s,
          "messages"   => @store.messages.count { |message| chat_ids.includes?(message.chat_id) }.to_s,
          "snapshots"  => @store.snapshots.count { |snapshot| snapshot.owner_id == user }.to_s,
          "events"     => @mutex.synchronize { @store.events.count { |event| event.owner_id == user } }.to_s,
        }
      end

      register_action("snapshot.copy", "Copy snapshot `from` to the key `to`") do |args, user|
        from = args["from"]? || raise ActionError.new("from is required")
        to = args["to"]? || raise ActionError.new("to is required")
        raise ActionError.new("to must be 1-200 characters of A-Z a-z 0-9 . _ : -") unless to.matches?(SNAPSHOT_KEY)
        source = @store.snapshots.find { |snapshot| snapshot.owner_id == user && snapshot.key == from } ||
                 raise ActionError.new("no snapshot named #{from}")
        @mutex.synchronize do
          @store.snapshots.reject! { |snapshot| snapshot.owner_id == user && snapshot.key == to }
          @store.snapshots << Snapshot.new(to, user, source.data.dup, Time.utc.to_unix_ms)
          persist
        end
        {"key" => to, "fields" => source.data.size.to_s}
      end

      register_action("events.clear", "Forget the caller's events") do |_args, user|
        removed = @mutex.synchronize do
          before = @store.events.size
          @store.events.reject! { |event| event.owner_id == user }
          rewrite_journal
          before - @store.events.size
        end
        {"removed" => removed.to_s}
      end
    end

    # ------------------------------------------------------------- helpers

    # An optional JSON object whose values must all be strings.
    private def string_fields(value : JSON::Any?, field : String) : Hash(String, String)
      return {} of String => String if value.nil? || value.raw.nil?
      fields = value.as_h? || raise ApiError.new(400, "Invalid params", field, "#{field} must be an object")
      fields.to_h do |key, entry|
        {key, entry.as_s? || raise ApiError.new(400, "Invalid params", field, "#{field}.#{key} must be a string")}
      end
    end

    private def respond(ctx, body)
      ctx.response.print body.to_json
    end

    private def not_found(path)
      raise ApiError.new(404, "Not found", nil, "No route for #{path}")
    end

    private def require_owner(owner_id : Int64, user : User)
      return if owner_id == user.id
      raise ApiError.new(401, "You're not authorized to perform that action.", nil, "not the owner")
    end

    private def param_key(ctx, key : String) : Hash(String, JSON::Any)
      body = ctx.request.body.try(&.gets_to_end) || ""
      json = body.empty? ? JSON::Any.new({} of String => JSON::Any) : JSON.parse(body)
      json[key]?.try(&.as_h?) || raise ApiError.new(400, "Missing param key: #{key}", key, "expected {\"#{key}\": {...}}")
    end

    private def required_string(params, field) : String
      params[field]?.try(&.as_s?) || raise ApiError.new(400, "Invalid params", field, "#{field} is required")
    end

    private def bounded(params, field, min, max, required = false) : String?
      value = params[field]?.try(&.as_s?)
      if value.nil?
        raise ApiError.new(400, "Invalid params", field, "#{field} is required") if required
        return nil
      end
      unless (min..max).includes?(value.size)
        raise ApiError.new(400, "Invalid params", field, "#{field} must be #{min}-#{max} characters")
      end
      value
    end

    private def visibility(params) : String?
      value = params["visibility"]?.try(&.as_s?)
      return nil unless value
      raise ApiError.new(400, "Invalid params", "visibility", "visibility is invalid") unless VISIBILITIES.includes?(value)
      value
    end

    private def load_store : Store
      if (path = @data_file) && File.exists?(path)
        Store.from_json(File.read(path))
      else
        Store.new
      end
    end

    private def persist
      return unless path = @data_file
      tmp = "#{path}.tmp"
      File.write(tmp, @store.to_json)
      File.rename(tmp, path)
    end

    # The event journal sits beside the data file.
    private def journal_path : String?
      @data_file.try { |path| "#{path}.events" }
    end

    # Read the journal into the store. Events from an older store file
    # that held them come first; a damaged line is skipped.
    private def load_journal : Nil
      path = journal_path
      if path && File.exists?(path)
        File.each_line(path) do |line|
          next if line.blank?
          @journal_lines += 1
          event = Event.from_json(line) rescue next
          @store.events << event
        end
      end
      @store.events.sort_by!(&.id)
      @store.events.uniq!(&.id)
      @store.events.shift(@store.events.size - EVENT_LIMIT) if @store.events.size > EVENT_LIMIT
      last = @store.events.last?.try(&.id) || 0_i64
      @store.next_event_id = Math.max(@store.next_event_id, last + 1)
      # An older store file carried the events itself: move them over.
      rewrite_journal if path && @journal_lines != @store.events.size
    end

    # Add one event to the journal: one line, however many events exist.
    # The file is cut back to the kept events when it has grown to twice
    # their limit.
    private def journal(event : Event) : Nil
      path = journal_path || return
      if @journal_lines >= EVENT_LIMIT * 2
        rewrite_journal
      else
        File.open(path, "a") { |file| file.puts event.to_json }
        @journal_lines += 1
      end
    end

    private def rewrite_journal : Nil
      path = journal_path || return
      tmp = "#{path}.tmp"
      File.open(tmp, "w") { |file| @store.events.each { |event| file.puts event.to_json } }
      File.rename(tmp, path)
      @journal_lines = @store.events.size
      # Keep the next id with the store, for a journal that ends up empty.
      persist
    end
  end
end
