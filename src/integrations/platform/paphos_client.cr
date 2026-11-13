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
