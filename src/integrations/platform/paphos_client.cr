# HTTP client for the Paphos backend REST API (/api/v1). Works against both
# crystalcog's PaphosBackend::Server and the upstream 9cog/paphos-backend
# (messages endpoints exist only on the former).

require "http/client"
require "json"
require "uri"

module PaphosBackend
  class Client
    class Error < Exception
      getter status : Int32
      getter param : String?

      def initialize(@status : Int32, message : String, @param : String? = nil)
        super(message)
      end
    end

    property token : String?
    getter base_url : String

    # base_url includes the API prefix, e.g. "http://localhost:3000/api/v1".
    def initialize(base_url : String, @token : String? = nil, @timeout : Time::Span = 30.seconds)
      @base_url = base_url.rstrip('/')
    end

    def with_token(token : String) : Client
      Client.new(@base_url, token, @timeout)
    end

    def ping : Bool
      request("GET", "/", auth: false)
      true
    rescue Error | IO::Error | Socket::Error
      false
    end

    def register(email : String, password : String) : String
      json = request("POST", "/users/register", {"user" => {"email" => email, "password" => password,
                                                            "password_confirmation" => password}}, auth: false)
      @token = json["token"].as_s
    end

    def login(email : String, password : String) : String
      json = request("POST", "/users/login", {"user" => {"email" => email, "password" => password}}, auth: false)
      @token = json["token"].as_s
    end

    def characters : Array(JSON::Any)
      request("GET", "/characters")["characters"].as_a
    end

    def character(slug : String) : JSON::Any
      request("GET", "/characters/#{URI.encode_path_segment(slug)}")["character"]
    end

    def create_character(attrs : Hash(String, String | Bool | Nil)) : JSON::Any
      request("POST", "/characters", {"character" => attrs})["character"]
    end

    def update_character(slug : String, attrs : Hash(String, String | Bool | Nil)) : JSON::Any
      request("PATCH", "/characters/#{URI.encode_path_segment(slug)}", {"character" => attrs})["character"]
    end

    def delete_character(slug : String) : Nil
      request("DELETE", "/characters/#{URI.encode_path_segment(slug)}")
      nil
    end

    def chats : Array(JSON::Any)
      request("GET", "/chats")["chats"].as_a
    end

    def chat(id : String) : JSON::Any
      request("GET", "/chats/#{URI.encode_path_segment(id)}")["chat"]
    end

    def create_chat(character_slugs : Array(String), name : String? = nil) : JSON::Any
      body = {"chat" => {"character_slugs" => character_slugs, "name" => name}}
      request("POST", "/chats", body)["chat"]
    end

    def delete_chat(id : String) : Nil
      request("DELETE", "/chats/#{URI.encode_path_segment(id)}")
      nil
    end

    def messages(chat_id : String) : Array(JSON::Any)
      request("GET", "/chats/#{URI.encode_path_segment(chat_id)}/messages")["messages"].as_a
    end

    def post_message(chat_id : String, content : String, sender : String = "user",
                     character_slug : String? = nil) : JSON::Any
      body = {"message" => {"content" => content, "sender" => sender, "character_slug" => character_slug}}
      request("POST", "/chats/#{URI.encode_path_segment(chat_id)}/messages", body)["message"]
    end

    # Snapshots: named documents of string fields, owned by the caller.
    # `filter` keeps the snapshots whose data has the given field values.
    def snapshots(filter : Hash(String, String) = {} of String => String) : Array(JSON::Any)
      query = filter.empty? ? "" : "?" + URI::Params.encode(filter)
      request("GET", "/snapshots#{query}")["snapshots"].as_a
    end

    # A snapshot's data, or nil when there is none under `key`.
    def snapshot(key : String) : Hash(String, String)?
      request("GET", "/snapshots/#{URI.encode_path_segment(key)}")["snapshot"]["data"].as_h.transform_values(&.as_s)
    rescue ex : Error
      raise ex unless ex.status == 404
      nil
    end

    def put_snapshot(key : String, data : Hash(String, String)) : JSON::Any
      request("PUT", "/snapshots/#{URI.encode_path_segment(key)}", {"snapshot" => {"data" => data}})["snapshot"]
    end

    def delete_snapshot(key : String) : Nil
      request("DELETE", "/snapshots/#{URI.encode_path_segment(key)}")
      nil
    end

    # Publish an event to the caller's stream; returns the stored event.
    def publish_event(type : String, data : Hash(String, String) = {} of String => String,
                      source : String = "crystalcog") : JSON::Any
      request("POST", "/events", {"event" => {"type" => type, "source" => source, "data" => data}})["event"]
    end

    # The caller's events with an id above `after`, oldest first. `wait`
    # holds the request open until an event arrives or the time is up.
    def events(after : Int64 = 0_i64, types : Array(String)? = nil, limit : Int32? = nil,
               wait : Time::Span? = nil) : Array(JSON::Any)
      query = {"after" => after.to_s}
      types.try { |list| query["types"] = list.join(",") }
      limit.try { |count| query["limit"] = count.to_s }
      wait.try { |span| query["wait"] = span.total_seconds.to_s }
      request("GET", "/events?" + URI::Params.encode(query))["events"].as_a
    end

    # An open event stream, as `follow_events` returns it.
    class EventFollow
      getter? closed = false
      # Why the stream ended, when it was not closed from this side.
      getter error : Exception?

      def initialize(@http : HTTP::Client)
      end

      # Stop following. The block is not called again.
      def close : Nil
        return if @closed
        @closed = true
        @http.close
      end

      protected def ended(@error : Exception?) : Nil
        @closed = true
      end
    end

    # Follow the caller's events as the backend publishes them. The block
    # is called, in a fiber of its own, with each event after `after`, in
    # order. `close` the returned follow to stop. When the backend goes
    # away the follow closes by itself and its `error` says why.
    def follow_events(after : Int64 = 0_i64, types : Array(String)? = nil, &block : JSON::Any ->) : EventFollow
      token = @token || raise Error.new(401, "Not authenticated: call login or register first")
      query = {"after" => after.to_s}
      types.try { |list| query["types"] = list.join(",") }
      uri = URI.parse(@base_url + "/events/stream?" + URI::Params.encode(query))
      headers = HTTP::Headers{"Accept" => "text/event-stream", "Authorization" => "Bearer #{token}"}

      http = HTTP::Client.new(uri)
      http.connect_timeout = @timeout
      # The backend writes a keep-alive line when nothing happens, so a
      # long silence means the connection is dead.
      http.read_timeout = 2.minutes
      follow = EventFollow.new(http)
      opened = Channel(Exception?).new(1)

      spawn do
        answered = false
        begin
          http.get(uri.request_target, headers: headers) do |response|
            answered = true
            unless response.success?
              opened.send(Error.new(response.status_code, "event stream refused: HTTP #{response.status_code}"))
              next
            end
            opened.send(nil)
            read_event_stream(response.body_io, follow, &block)
          end
          follow.ended(nil) unless follow.closed?
        rescue ex
          opened.send(ex) unless answered
          follow.ended(ex) unless follow.closed?
        end
      end

      select
      when failure = opened.receive
        if failure
          follow.close
          raise failure.is_a?(Error) ? failure : Error.new(502, "event stream failed: #{failure.message}")
        end
      when timeout(@timeout)
        follow.close
        raise Error.new(504, "event stream did not open in time")
      end
      follow
    end

    # Read server-sent events: "data:" lines up to a blank line are one
    # event. "id:", "event:" and comment lines carry nothing the data lacks.
    private def read_event_stream(io : IO, follow : EventFollow, &block : JSON::Any ->) : Nil
      data = String::Builder.new
      has_data = false
      io.each_line do |line|
        break if follow.closed?
        if line.empty?
          if has_data
            block.call(JSON.parse(data.to_s))
            data = String::Builder.new
            has_data = false
          end
        elsif line.starts_with?("data:")
          data << '\n' if has_data
          data << line.lchop("data:").lchop(' ')
          has_data = true
        end
      end
    end

    # The service functions the backend offers: name and description.
    def actions : Array(JSON::Any)
      request("GET", "/actions")["actions"].as_a
    end

    # Run a service function and return its result fields. A refusal or an
    # unknown name raises `Error` (422 and 404).
    def call_action(name : String, args : Hash(String, String) = {} of String => String) : Hash(String, String)
      response = request("POST", "/actions/#{URI.encode_path_segment(name)}", {"action" => {"args" => args}})
      response["result"].as_h.transform_values(&.as_s)
    end

    private def request(method : String, path : String, body = nil, auth : Bool = true) : JSON::Any
      uri = URI.parse(@base_url + path)
      headers = HTTP::Headers{"Accept" => "application/json"}
      headers["Content-Type"] = "application/json" if body
      if auth
        token = @token || raise Error.new(401, "Not authenticated: call login or register first")
        headers["Authorization"] = "Bearer #{token}"
      end

      client = HTTP::Client.new(uri)
      client.connect_timeout = @timeout
      client.read_timeout = @timeout
      response = client.exec(method, uri.request_target, headers: headers, body: body.try(&.to_json))

      parsed = response.body.empty? ? JSON::Any.new(nil) : JSON.parse(response.body)
      unless response.success?
        err = parsed.as_h? || {} of String => JSON::Any
        message = err["details"]?.try(&.as_s?) || err["message"]?.try(&.as_s?) || "HTTP #{response.status_code}"
        raise Error.new(response.status_code, message, err["param"]?.try(&.as_s?))
      end
      parsed
    rescue ex : JSON::ParseException
      raise Error.new(502, "Invalid JSON from Paphos: #{ex.message}")
    ensure
      client.try(&.close)
    end
  end
end
