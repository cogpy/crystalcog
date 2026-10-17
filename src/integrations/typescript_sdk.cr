# CrystalCog TypeScript SDK
# Web Bindings and JavaScript/TypeScript Integration
#
# This module provides a complete TypeScript SDK for CrystalCog, enabling
# web applications to interact with the AtomSpace through REST API and
# WebSocket connections.

require "http/server"
require "json"

module CrystalCog
  module Integrations
    # TypeScript SDK Configuration
    class TypeScriptSDKConfig
      property host : String
      property port : Int32
      property cors_origins : Array(String)
      property enable_websocket : Bool
      property api_prefix : String
      property rate_limit : Int32
      property auth_enabled : Bool
      property api_key : String?

      def initialize(
        @host = "0.0.0.0",
        @port = 8080,
        @cors_origins = ["*"],
        @enable_websocket = true,
        @api_prefix = "/api/v1",
        @rate_limit = 1000,
        @auth_enabled = false,
        @api_key = nil
      )
      end
    end

    # API Response wrapper
    struct APIResponse
      property success : Bool
      property data : JSON::Any?
      property error : String?
      property timestamp : Int64
      property request_id : String

      def initialize(
        @success = true,
        @data = nil,
        @error = nil,
        @timestamp = Time.utc.to_unix_ms,
        @request_id = UUID.random.to_s
      )
      end

      def to_json : String
        {
          "success"   => @success,
          "data"      => @data,
          "error"     => @error,
          "timestamp" => @timestamp,
          "requestId" => @request_id,
        }.to_json
      end
    end

    # Atom DTO (Data Transfer Object)
    struct AtomDTO
      include JSON::Serializable

      property id : String
      property type : String
      property name : String?
      property outgoing : Array(String)?
      property truth_value : TruthValueDTO?
      property attention_value : AttentionValueDTO?
      property metadata : Hash(String, JSON::Any)?

      def initialize(
        @id = "",
        @type = "ConceptNode",
        @name = nil,
        @outgoing = nil,
        @truth_value = nil,
        @attention_value = nil,
        @metadata = nil
      )
      end
    end

    struct TruthValueDTO
      include JSON::Serializable

      property strength : Float64
      property confidence : Float64

      def initialize(@strength = 1.0, @confidence = 1.0)
      end
    end

    struct AttentionValueDTO
      include JSON::Serializable

      property sti : Float64
      property lti : Float64

      def initialize(@sti = 0.0, @lti = 0.0)
      end
    end

    # Query DTO
    struct QueryDTO
      include JSON::Serializable

      property pattern : String
      property variables : Hash(String, String)?
      property limit : Int32?
      property offset : Int32?
      property include_truth_values : Bool?

      def initialize(
        @pattern = "",
        @variables = nil,
        @limit = nil,
        @offset = nil,
        @include_truth_values = nil
      )
      end
    end

    # WebSocket Message Types
    enum WSMessageType
      Subscribe
      Unsubscribe
      Query
      Mutation
      Event
      Ping
      Pong
      Error
    end

    struct WSMessage
      property type : WSMessageType
      property channel : String?
      property payload : JSON::Any?
      property id : String

      def initialize(
        @type = WSMessageType::Ping,
        @channel = nil,
        @payload = nil,
        @id = UUID.random.to_s
      )
      end

      def to_json : String
        {
          "type"    => @type.to_s.downcase,
          "channel" => @channel,
          "payload" => @payload,
          "id"      => @id,
        }.to_json
      end

      def self.from_json(json : String) : WSMessage?
        data = JSON.parse(json)

        type_str = data["type"]?.try(&.as_s) || "ping"
        msg_type = case type_str
                   when "subscribe"   then WSMessageType::Subscribe
                   when "unsubscribe" then WSMessageType::Unsubscribe
                   when "query"       then WSMessageType::Query
                   when "mutation"    then WSMessageType::Mutation
                   when "event"       then WSMessageType::Event
                   when "pong"        then WSMessageType::Pong
                   when "error"       then WSMessageType::Error
                   else                    WSMessageType::Ping
                   end

        WSMessage.new(
          type: msg_type,
          channel: data["channel"]?.try(&.as_s),
          payload: data["payload"]?,
          id: data["id"]?.try(&.as_s) || UUID.random.to_s
        )
      rescue
        nil
      end
    end

    # In-memory AtomSpace for SDK (simplified)
    class SDKAtomSpace
      @atoms : Hash(String, AtomDTO)
      @subscriptions : Hash(String, Array(HTTP::WebSocket))
      @mutex : Mutex

      def initialize
        @atoms = {} of String => AtomDTO
        @subscriptions = {} of String => Array(HTTP::WebSocket)
        @mutex = Mutex.new
      end

      def add_atom(atom : AtomDTO) : AtomDTO
        @mutex.synchronize do
          atom_with_id = atom
          if atom_with_id.id.empty?
            atom_with_id = AtomDTO.new(
              id: UUID.random.to_s,
              type: atom.type,
              name: atom.name,
              outgoing: atom.outgoing,
              truth_value: atom.truth_value,
              attention_value: atom.attention_value,
              metadata: atom.metadata
            )
          end
          @atoms[atom_with_id.id] = atom_with_id
          notify_subscribers("atoms", {"action" => "add", "atom" => atom_with_id})
          atom_with_id
        end
      end

      def get_atom(id : String) : AtomDTO?
        @mutex.synchronize { @atoms[id]? }
      end

      def get_atoms(type : String? = nil, limit : Int32 = 100, offset : Int32 = 0) : Array(AtomDTO)
        @mutex.synchronize do
          atoms = @atoms.values
          atoms = atoms.select { |a| a.type == type } if type
          atoms[offset, limit]? || [] of AtomDTO
        end
      end

      def update_atom(id : String, updates : AtomDTO) : AtomDTO?
        @mutex.synchronize do
          return nil unless @atoms.has_key?(id)

          existing = @atoms[id]
          updated = AtomDTO.new(
            id: id,
            type: updates.type.empty? ? existing.type : updates.type,
            name: updates.name || existing.name,
            outgoing: updates.outgoing || existing.outgoing,
            truth_value: updates.truth_value || existing.truth_value,
            attention_value: updates.attention_value || existing.attention_value,
            metadata: updates.metadata || existing.metadata
          )

          @atoms[id] = updated
          notify_subscribers("atoms", {"action" => "update", "atom" => updated})
          updated
        end
      end

      def delete_atom(id : String) : Bool
        @mutex.synchronize do
          if @atoms.delete(id)
            notify_subscribers("atoms", {"action" => "delete", "id" => id})
            true
          else
            false
          end
        end
      end

      def query(pattern : String, limit : Int32 = 100) : Array(AtomDTO)
        @mutex.synchronize do
          # Simple pattern matching (name contains pattern)
          @atoms.values.select do |atom|
            (atom.name.try(&.includes?(pattern)) || false) ||
              atom.type.includes?(pattern)
          end.first(limit)
        end
      end

      def subscribe(channel : String, socket : HTTP::WebSocket)
        @mutex.synchronize do
          @subscriptions[channel] ||= [] of HTTP::WebSocket
          @subscriptions[channel] << socket
        end
      end

      def unsubscribe(channel : String, socket : HTTP::WebSocket)
        @mutex.synchronize do
          @subscriptions[channel]?.try(&.delete(socket))
        end
      end

      def unsubscribe_all(socket : HTTP::WebSocket)
        @mutex.synchronize do
          @subscriptions.each_value { |sockets| sockets.delete(socket) }
        end
      end

      private def notify_subscribers(channel : String, data)
        @subscriptions[channel]?.try do |sockets|
          message = WSMessage.new(
            type: WSMessageType::Event,
            channel: channel,
            payload: JSON.parse(data.to_json)
          )

          sockets.each do |socket|
            begin
              socket.send(message.to_json)
            rescue
              # Socket closed, will be cleaned up
            end
          end
        end
      end

      def stats : Hash(String, Int64 | Int32)
        @mutex.synchronize do
          {
            "atom_count"         => @atoms.size.to_i64,
            "subscription_count" => @subscriptions.values.sum(&.size).to_i32,
          }
        end
      end
    end

    # TypeScript SDK Server
    class TypeScriptSDKServer
      @config : TypeScriptSDKConfig
      @atomspace : SDKAtomSpace
      @server : HTTP::Server?
      @running : Bool

      def initialize(@config = TypeScriptSDKConfig.new)
        @atomspace = SDKAtomSpace.new
        @server = nil
        @running = false
      end

      def start
        return if @running

        @server = HTTP::Server.new do |context|
          handle_request(context)
        end

        @running = true

        puts "TypeScript SDK Server starting on http://#{@config.host}:#{@config.port}"
        puts "API prefix: #{@config.api_prefix}"
        puts "WebSocket: #{@config.enable_websocket ? "enabled" : "disabled"}"

        @server.not_nil!.bind_tcp(@config.host, @config.port)
        @server.not_nil!.listen
      end

      def stop
        @running = false
        @server.try(&.close)
      end

      private def handle_request(context : HTTP::Server::Context)
        # Add CORS headers
        add_cors_headers(context.response)

        # Handle preflight
        if context.request.method == "OPTIONS"
          context.response.status = HTTP::Status::OK
          return
        end

        # Check authentication if enabled
        if @config.auth_enabled && !authenticate(context.request)
          context.response.status = HTTP::Status::UNAUTHORIZED
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: false,
            error: "Unauthorized"
          ).to_json)
          return
        end

        path = context.request.path

        # WebSocket upgrade
        if @config.enable_websocket && path == "#{@config.api_prefix}/ws"
          handle_websocket(context)
          return
        end

        # REST API routes
        case {context.request.method, path}
        when {"GET", "#{@config.api_prefix}/atoms"}
          handle_get_atoms(context)
        when {"POST", "#{@config.api_prefix}/atoms"}
          handle_create_atom(context)
        when {"GET", /#{@config.api_prefix}\/atoms\/(.+)/}
          handle_get_atom(context, $1)
        when {"PUT", /#{@config.api_prefix}\/atoms\/(.+)/}
          handle_update_atom(context, $1)
        when {"DELETE", /#{@config.api_prefix}\/atoms\/(.+)/}
          handle_delete_atom(context, $1)
        when {"POST", "#{@config.api_prefix}/query"}
          handle_query(context)
        when {"GET", "#{@config.api_prefix}/stats"}
          handle_stats(context)
        when {"GET", "#{@config.api_prefix}/health"}
          handle_health(context)
        when {"GET", "#{@config.api_prefix}/openapi.json"}
          handle_openapi(context)
        when {"GET", "/"}
          handle_docs(context)
        else
          context.response.status = HTTP::Status::NOT_FOUND
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: false,
            error: "Not found"
          ).to_json)
        end
      rescue ex
        context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
        context.response.content_type = "application/json"
        context.response.print(APIResponse.new(
          success: false,
          error: ex.message || "Internal server error"
        ).to_json)
      end

      private def handle_websocket(context : HTTP::Server::Context)
        ws = HTTP::WebSocketHandler.new do |socket, ctx|
          socket.on_message do |message|
            handle_ws_message(socket, message)
          end

          socket.on_close do
            @atomspace.unsubscribe_all(socket)
          end

          # Send connected message
          socket.send(WSMessage.new(
            type: WSMessageType::Event,
            channel: "system",
            payload: JSON.parse({"status" => "connected"}.to_json)
          ).to_json)
        end

        ws.call(context)
      end

      private def handle_ws_message(socket : HTTP::WebSocket, message : String)
        msg = WSMessage.from_json(message)
        return unless msg

        response = case msg.type
                   when .subscribe?
                     channel = msg.channel || "atoms"
                     @atomspace.subscribe(channel, socket)
                     WSMessage.new(
                       type: WSMessageType::Event,
                       channel: channel,
                       payload: JSON.parse({"subscribed" => true}.to_json),
                       id: msg.id
                     )
                   when .unsubscribe?
                     channel = msg.channel || "atoms"
                     @atomspace.unsubscribe(channel, socket)
                     WSMessage.new(
                       type: WSMessageType::Event,
                       channel: channel,
                       payload: JSON.parse({"subscribed" => false}.to_json),
                       id: msg.id
                     )
                   when .query?
                     pattern = msg.payload.try { |p| p["pattern"]?.try(&.as_s) } || ""
                     results = @atomspace.query(pattern)
                     WSMessage.new(
                       type: WSMessageType::Event,
                       channel: "query",
                       payload: JSON.parse({"results" => results}.to_json),
                       id: msg.id
                     )
                   when .mutation?
                     handle_ws_mutation(msg)
                   when .ping?
                     WSMessage.new(type: WSMessageType::Pong, id: msg.id)
                   else
                     WSMessage.new(
                       type: WSMessageType::Error,
                       payload: JSON.parse({"error" => "Unknown message type"}.to_json),
                       id: msg.id
                     )
                   end

        socket.send(response.to_json)
      rescue ex
        error_response = WSMessage.new(
          type: WSMessageType::Error,
          payload: JSON.parse({"error" => ex.message || "Error processing message"}.to_json)
        )
        socket.send(error_response.to_json)
      end

      private def handle_ws_mutation(msg : WSMessage) : WSMessage
        payload = msg.payload
        return WSMessage.new(
          type: WSMessageType::Error,
          payload: JSON.parse({"error" => "Missing payload"}.to_json),
          id: msg.id
        ) unless payload

        action = payload["action"]?.try(&.as_s)

        case action
        when "add"
          atom_data = payload["atom"]?
          return error_msg(msg.id, "Missing atom data") unless atom_data

          atom = AtomDTO.from_json(atom_data.to_json)
          result = @atomspace.add_atom(atom)

          WSMessage.new(
            type: WSMessageType::Event,
            channel: "mutation",
            payload: JSON.parse({"action" => "add", "atom" => result}.to_json),
            id: msg.id
          )
        when "update"
          id = payload["id"]?.try(&.as_s)
          atom_data = payload["atom"]?
          return error_msg(msg.id, "Missing id or atom data") unless id && atom_data

          atom = AtomDTO.from_json(atom_data.to_json)
          result = @atomspace.update_atom(id, atom)

          if result
            WSMessage.new(
              type: WSMessageType::Event,
              channel: "mutation",
              payload: JSON.parse({"action" => "update", "atom" => result}.to_json),
              id: msg.id
            )
          else
            error_msg(msg.id, "Atom not found")
          end
        when "delete"
          id = payload["id"]?.try(&.as_s)
          return error_msg(msg.id, "Missing id") unless id

          if @atomspace.delete_atom(id)
            WSMessage.new(
              type: WSMessageType::Event,
              channel: "mutation",
              payload: JSON.parse({"action" => "delete", "id" => id}.to_json),
              id: msg.id
            )
          else
            error_msg(msg.id, "Atom not found")
          end
        else
          error_msg(msg.id, "Unknown action: #{action}")
        end
      end

      private def error_msg(id : String, message : String) : WSMessage
        WSMessage.new(
          type: WSMessageType::Error,
          payload: JSON.parse({"error" => message}.to_json),
          id: id
        )
      end

      private def handle_get_atoms(context : HTTP::Server::Context)
        params = context.request.query_params
        type_filter = params["type"]?
        limit = (params["limit"]? || "100").to_i
        offset = (params["offset"]? || "0").to_i

        atoms = @atomspace.get_atoms(type_filter, limit, offset)

        context.response.content_type = "application/json"
        context.response.print(APIResponse.new(
          success: true,
          data: JSON.parse({"atoms" => atoms, "total" => atoms.size}.to_json)
        ).to_json)
      end

      private def handle_create_atom(context : HTTP::Server::Context)
        body = context.request.body.try(&.gets_to_end) || "{}"
        atom = AtomDTO.from_json(body)
        result = @atomspace.add_atom(atom)

        context.response.status = HTTP::Status::CREATED
        context.response.content_type = "application/json"
        context.response.print(APIResponse.new(
          success: true,
          data: JSON.parse(result.to_json)
        ).to_json)
      end

      private def handle_get_atom(context : HTTP::Server::Context, id : String)
        atom = @atomspace.get_atom(id)

        if atom
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: true,
            data: JSON.parse(atom.to_json)
          ).to_json)
        else
          context.response.status = HTTP::Status::NOT_FOUND
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: false,
            error: "Atom not found"
          ).to_json)
        end
      end

      private def handle_update_atom(context : HTTP::Server::Context, id : String)
        body = context.request.body.try(&.gets_to_end) || "{}"
        updates = AtomDTO.from_json(body)
        result = @atomspace.update_atom(id, updates)

        if result
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: true,
            data: JSON.parse(result.to_json)
          ).to_json)
        else
          context.response.status = HTTP::Status::NOT_FOUND
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: false,
            error: "Atom not found"
          ).to_json)
        end
      end

      private def handle_delete_atom(context : HTTP::Server::Context, id : String)
        if @atomspace.delete_atom(id)
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: true,
            data: JSON.parse({"deleted" => id}.to_json)
          ).to_json)
        else
          context.response.status = HTTP::Status::NOT_FOUND
          context.response.content_type = "application/json"
          context.response.print(APIResponse.new(
            success: false,
            error: "Atom not found"
          ).to_json)
        end
      end

      private def handle_query(context : HTTP::Server::Context)
        body = context.request.body.try(&.gets_to_end) || "{}"
        query = QueryDTO.from_json(body)
        limit = query.limit || 100

        results = @atomspace.query(query.pattern, limit)

        context.response.content_type = "application/json"
        context.response.print(APIResponse.new(
          success: true,
          data: JSON.parse({"results" => results, "total" => results.size}.to_json)
        ).to_json)
      end

      private def handle_stats(context : HTTP::Server::Context)
        stats = @atomspace.stats

        context.response.content_type = "application/json"
        context.response.print(APIResponse.new(
          success: true,
          data: JSON.parse(stats.to_json)
        ).to_json)
      end

      private def handle_health(context : HTTP::Server::Context)
        context.response.content_type = "application/json"
        context.response.print(APIResponse.new(
          success: true,
          data: JSON.parse({
            "status"    => "healthy",
            "uptime"    => Time.utc.to_unix,
            "version"   => "0.1.0",
            "websocket" => @config.enable_websocket,
          }.to_json)
        ).to_json)
      end

      private def handle_openapi(context : HTTP::Server::Context)
        openapi = generate_openapi_spec
        context.response.content_type = "application/json"
        context.response.print(openapi)
      end

      private def handle_docs(context : HTTP::Server::Context)
        context.response.content_type = "text/html"
        context.response.print(generate_docs_html)
      end

      private def add_cors_headers(response : HTTP::Server::Response)
        response.headers["Access-Control-Allow-Origin"] = @config.cors_origins.join(", ")
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-API-Key"
        response.headers["Access-Control-Max-Age"] = "86400"
      end

      private def authenticate(request : HTTP::Request) : Bool
        return true unless @config.auth_enabled

        api_key = request.headers["X-API-Key"]? ||
                  request.query_params["api_key"]?

        api_key == @config.api_key
      end

      private def generate_openapi_spec : String
        {
          "openapi" => "3.0.0",
          "info"    => {
            "title"       => "CrystalCog AtomSpace API",
            "description" => "REST API for interacting with CrystalCog AtomSpace",
            "version"     => "0.1.0",
          },
          "servers" => [
            {"url" => "http://#{@config.host}:#{@config.port}#{@config.api_prefix}"},
          ],
          "paths" => {
            "/atoms" => {
              "get" => {
                "summary"    => "List all atoms",
                "parameters" => [
                  {"name" => "type", "in" => "query", "schema" => {"type" => "string"}},
                  {"name" => "limit", "in" => "query", "schema" => {"type" => "integer", "default" => 100}},
                  {"name" => "offset", "in" => "query", "schema" => {"type" => "integer", "default" => 0}},
                ],
                "responses" => {
                  "200" => {"description" => "List of atoms"},
                },
              },
              "post" => {
                "summary"     => "Create a new atom",
                "requestBody" => {
                  "content" => {
                    "application/json" => {
                      "schema" => {"$ref" => "#/components/schemas/Atom"},
                    },
                  },
                },
                "responses" => {
                  "201" => {"description" => "Atom created"},
                },
              },
            },
            "/atoms/{id}" => {
              "get" => {
                "summary"    => "Get atom by ID",
                "parameters" => [
                  {"name" => "id", "in" => "path", "required" => true, "schema" => {"type" => "string"}},
                ],
                "responses" => {
                  "200" => {"description" => "Atom details"},
                  "404" => {"description" => "Atom not found"},
                },
              },
              "put" => {
                "summary"    => "Update an atom",
                "parameters" => [
                  {"name" => "id", "in" => "path", "required" => true, "schema" => {"type" => "string"}},
                ],
                "responses" => {
                  "200" => {"description" => "Atom updated"},
                  "404" => {"description" => "Atom not found"},
                },
              },
              "delete" => {
                "summary"    => "Delete an atom",
                "parameters" => [
                  {"name" => "id", "in" => "path", "required" => true, "schema" => {"type" => "string"}},
                ],
                "responses" => {
                  "200" => {"description" => "Atom deleted"},
                  "404" => {"description" => "Atom not found"},
                },
              },
            },
            "/query" => {
              "post" => {
                "summary"     => "Query atoms",
                "requestBody" => {
                  "content" => {
                    "application/json" => {
                      "schema" => {"$ref" => "#/components/schemas/Query"},
                    },
                  },
                },
                "responses" => {
                  "200" => {"description" => "Query results"},
                },
              },
            },
            "/stats" => {
              "get" => {
                "summary"   => "Get AtomSpace statistics",
                "responses" => {
                  "200" => {"description" => "Statistics"},
                },
              },
            },
            "/health" => {
              "get" => {
                "summary"   => "Health check",
                "responses" => {
                  "200" => {"description" => "Service is healthy"},
                },
              },
            },
          },
          "components" => {
            "schemas" => {
              "Atom" => {
                "type"       => "object",
                "properties" => {
                  "id"              => {"type" => "string"},
                  "type"            => {"type" => "string"},
                  "name"            => {"type" => "string"},
                  "outgoing"        => {"type" => "array", "items" => {"type" => "string"}},
                  "truth_value"     => {"$ref" => "#/components/schemas/TruthValue"},
                  "attention_value" => {"$ref" => "#/components/schemas/AttentionValue"},
                },
              },
              "TruthValue" => {
                "type"       => "object",
                "properties" => {
                  "strength"   => {"type" => "number"},
                  "confidence" => {"type" => "number"},
                },
              },
              "AttentionValue" => {
                "type"       => "object",
                "properties" => {
                  "sti" => {"type" => "number"},
                  "lti" => {"type" => "number"},
                },
              },
              "Query" => {
                "type"       => "object",
                "properties" => {
                  "pattern"   => {"type" => "string"},
                  "limit"     => {"type" => "integer"},
                  "offset"    => {"type" => "integer"},
                  "variables" => {"type" => "object"},
                },
              },
            },
          },
        }.to_json
      end

      private def generate_docs_html : String
        <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>CrystalCog TypeScript SDK</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 900px; margin: 50px auto; padding: 20px; }
            h1 { color: #333; }
            h2 { color: #555; border-bottom: 1px solid #ddd; padding-bottom: 10px; }
            code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-family: 'Monaco', monospace; }
            pre { background: #f4f4f4; padding: 15px; border-radius: 5px; overflow-x: auto; }
            .endpoint { background: #e8f4f8; padding: 10px; margin: 10px 0; border-radius: 5px; }
            .method { font-weight: bold; color: #fff; padding: 3px 8px; border-radius: 3px; margin-right: 10px; }
            .get { background: #61affe; }
            .post { background: #49cc90; }
            .put { background: #fca130; }
            .delete { background: #f93e3e; }
          </style>
        </head>
        <body>
          <h1>CrystalCog TypeScript SDK</h1>
          <p>REST API and WebSocket interface for the CrystalCog AtomSpace.</p>

          <h2>Quick Start</h2>
          <pre><code>npm install @crystalcog/sdk

        import { CrystalCogClient } from '@crystalcog/sdk';

        const client = new CrystalCogClient('http://localhost:#{@config.port}');

        // Create an atom
        const atom = await client.createAtom({
          type: 'ConceptNode',
          name: 'Dog'
        });

        // Query atoms
        const results = await client.query({ pattern: 'Dog' });
        </code></pre>

          <h2>REST API Endpoints</h2>

          <div class="endpoint">
            <span class="method get">GET</span>
            <code>#{@config.api_prefix}/atoms</code>
            <p>List all atoms. Supports <code>type</code>, <code>limit</code>, <code>offset</code> query params.</p>
          </div>

          <div class="endpoint">
            <span class="method post">POST</span>
            <code>#{@config.api_prefix}/atoms</code>
            <p>Create a new atom.</p>
          </div>

          <div class="endpoint">
            <span class="method get">GET</span>
            <code>#{@config.api_prefix}/atoms/{id}</code>
            <p>Get atom by ID.</p>
          </div>

          <div class="endpoint">
            <span class="method put">PUT</span>
            <code>#{@config.api_prefix}/atoms/{id}</code>
            <p>Update an atom.</p>
          </div>

          <div class="endpoint">
            <span class="method delete">DELETE</span>
            <code>#{@config.api_prefix}/atoms/{id}</code>
            <p>Delete an atom.</p>
          </div>

          <div class="endpoint">
            <span class="method post">POST</span>
            <code>#{@config.api_prefix}/query</code>
            <p>Query atoms with pattern matching.</p>
          </div>

          <div class="endpoint">
            <span class="method get">GET</span>
            <code>#{@config.api_prefix}/stats</code>
            <p>Get AtomSpace statistics.</p>
          </div>

          <div class="endpoint">
            <span class="method get">GET</span>
            <code>#{@config.api_prefix}/health</code>
            <p>Health check endpoint.</p>
          </div>

          <h2>WebSocket API</h2>
          <p>Connect to <code>ws://localhost:#{@config.port}#{@config.api_prefix}/ws</code></p>

          <h3>Message Types</h3>
          <pre><code>// Subscribe to atom changes
        { "type": "subscribe", "channel": "atoms" }

        // Query
        { "type": "query", "payload": { "pattern": "Dog" } }

        // Mutation
        { "type": "mutation", "payload": { "action": "add", "atom": {...} } }
        </code></pre>

          <h2>OpenAPI Spec</h2>
          <p><a href="#{@config.api_prefix}/openapi.json">Download OpenAPI 3.0 specification</a></p>
        </body>
        </html>
        HTML
      end
    end

    # TypeScript Type Definitions Generator
    class TypeScriptGenerator
      def generate_types : String
        <<-TS
        /**
         * CrystalCog TypeScript SDK
         * Auto-generated type definitions
         */

        // Atom types
        export interface TruthValue {
          strength: number;
          confidence: number;
        }

        export interface AttentionValue {
          sti: number;
          lti: number;
        }

        export interface Atom {
          id: string;
          type: string;
          name?: string;
          outgoing?: string[];
          truthValue?: TruthValue;
          attentionValue?: AttentionValue;
          metadata?: Record<string, unknown>;
        }

        export interface CreateAtomInput {
          type: string;
          name?: string;
          outgoing?: string[];
          truthValue?: TruthValue;
          attentionValue?: AttentionValue;
          metadata?: Record<string, unknown>;
        }

        export interface UpdateAtomInput {
          type?: string;
          name?: string;
          outgoing?: string[];
          truthValue?: TruthValue;
          attentionValue?: AttentionValue;
          metadata?: Record<string, unknown>;
        }

        // Query types
        export interface QueryInput {
          pattern: string;
          variables?: Record<string, string>;
          limit?: number;
          offset?: number;
          includeTruthValues?: boolean;
        }

        export interface QueryResult {
          results: Atom[];
          total: number;
        }

        // API Response
        export interface APIResponse<T> {
          success: boolean;
          data?: T;
          error?: string;
          timestamp: number;
          requestId: string;
        }

        // WebSocket message types
        export type WSMessageType =
          | 'subscribe'
          | 'unsubscribe'
          | 'query'
          | 'mutation'
          | 'event'
          | 'ping'
          | 'pong'
          | 'error';

        export interface WSMessage<T = unknown> {
          type: WSMessageType;
          channel?: string;
          payload?: T;
          id: string;
        }

        export interface MutationPayload {
          action: 'add' | 'update' | 'delete';
          atom?: CreateAtomInput;
          id?: string;
        }

        // Client options
        export interface CrystalCogClientOptions {
          baseUrl: string;
          apiKey?: string;
          timeout?: number;
          retries?: number;
        }

        // Event callbacks
        export type AtomEventCallback = (event: {
          action: 'add' | 'update' | 'delete';
          atom?: Atom;
          id?: string;
        }) => void;

        // Client class
        export class CrystalCogClient {
          constructor(options: CrystalCogClientOptions | string);

          // REST API
          getAtoms(options?: { type?: string; limit?: number; offset?: number }): Promise<Atom[]>;
          getAtom(id: string): Promise<Atom | null>;
          createAtom(input: CreateAtomInput): Promise<Atom>;
          updateAtom(id: string, input: UpdateAtomInput): Promise<Atom>;
          deleteAtom(id: string): Promise<boolean>;
          query(input: QueryInput): Promise<QueryResult>;
          getStats(): Promise<Record<string, number>>;
          health(): Promise<{ status: string; version: string }>;

          // WebSocket
          connect(): Promise<void>;
          disconnect(): void;
          subscribe(channel: string, callback: AtomEventCallback): () => void;
          send(message: WSMessage): void;

          // Events
          on(event: 'connected' | 'disconnected' | 'error', callback: (data?: unknown) => void): void;
          off(event: string, callback: Function): void;
        }

        export default CrystalCogClient;
        TS
      end

      def generate_client_code : String
        <<-TS
        /**
         * CrystalCog TypeScript SDK Client
         * @version 0.1.0
         */

        import type {
          Atom,
          CreateAtomInput,
          UpdateAtomInput,
          QueryInput,
          QueryResult,
          APIResponse,
          WSMessage,
          CrystalCogClientOptions,
          AtomEventCallback,
        } from './types';

        export class CrystalCogClient {
          private baseUrl: string;
          private apiKey?: string;
          private timeout: number;
          private retries: number;
          private ws?: WebSocket;
          private subscriptions: Map<string, Set<AtomEventCallback>> = new Map();
          private eventListeners: Map<string, Set<Function>> = new Map();
          private messageHandlers: Map<string, (data: unknown) => void> = new Map();

          constructor(options: CrystalCogClientOptions | string) {
            if (typeof options === 'string') {
              this.baseUrl = options;
              this.timeout = 30000;
              this.retries = 3;
            } else {
              this.baseUrl = options.baseUrl;
              this.apiKey = options.apiKey;
              this.timeout = options.timeout ?? 30000;
              this.retries = options.retries ?? 3;
            }
          }

          // REST API Methods
          async getAtoms(options?: { type?: string; limit?: number; offset?: number }): Promise<Atom[]> {
            const params = new URLSearchParams();
            if (options?.type) params.set('type', options.type);
            if (options?.limit) params.set('limit', options.limit.toString());
            if (options?.offset) params.set('offset', options.offset.toString());

            const response = await this.fetch(`/atoms?${params}`);
            return response.data?.atoms ?? [];
          }

          async getAtom(id: string): Promise<Atom | null> {
            try {
              const response = await this.fetch(`/atoms/${id}`);
              return response.data as Atom;
            } catch {
              return null;
            }
          }

          async createAtom(input: CreateAtomInput): Promise<Atom> {
            const response = await this.fetch('/atoms', {
              method: 'POST',
              body: JSON.stringify(input),
            });
            return response.data as Atom;
          }

          async updateAtom(id: string, input: UpdateAtomInput): Promise<Atom> {
            const response = await this.fetch(`/atoms/${id}`, {
              method: 'PUT',
              body: JSON.stringify(input),
            });
            return response.data as Atom;
          }

          async deleteAtom(id: string): Promise<boolean> {
            const response = await this.fetch(`/atoms/${id}`, {
              method: 'DELETE',
            });
            return response.success;
          }

          async query(input: QueryInput): Promise<QueryResult> {
            const response = await this.fetch('/query', {
              method: 'POST',
              body: JSON.stringify(input),
            });
            return response.data as QueryResult;
          }

          async getStats(): Promise<Record<string, number>> {
            const response = await this.fetch('/stats');
            return response.data as Record<string, number>;
          }

          async health(): Promise<{ status: string; version: string }> {
            const response = await this.fetch('/health');
            return response.data as { status: string; version: string };
          }

          // WebSocket Methods
          async connect(): Promise<void> {
            return new Promise((resolve, reject) => {
              const wsUrl = this.baseUrl.replace(/^http/, 'ws') + '/api/v1/ws';
              this.ws = new WebSocket(wsUrl);

              this.ws.onopen = () => {
                this.emit('connected');
                resolve();
              };

              this.ws.onerror = (error) => {
                this.emit('error', error);
                reject(error);
              };

              this.ws.onclose = () => {
                this.emit('disconnected');
              };

              this.ws.onmessage = (event) => {
                try {
                  const message: WSMessage = JSON.parse(event.data);
                  this.handleMessage(message);
                } catch (e) {
                  console.error('Failed to parse WebSocket message:', e);
                }
              };
            });
          }

          disconnect(): void {
            this.ws?.close();
            this.ws = undefined;
          }

          subscribe(channel: string, callback: AtomEventCallback): () => void {
            if (!this.subscriptions.has(channel)) {
              this.subscriptions.set(channel, new Set());
              this.send({ type: 'subscribe', channel, id: this.generateId() });
            }
            this.subscriptions.get(channel)!.add(callback);

            return () => {
              this.subscriptions.get(channel)?.delete(callback);
              if (this.subscriptions.get(channel)?.size === 0) {
                this.send({ type: 'unsubscribe', channel, id: this.generateId() });
                this.subscriptions.delete(channel);
              }
            };
          }

          send(message: WSMessage): void {
            if (this.ws?.readyState === WebSocket.OPEN) {
              this.ws.send(JSON.stringify(message));
            }
          }

          on(event: string, callback: Function): void {
            if (!this.eventListeners.has(event)) {
              this.eventListeners.set(event, new Set());
            }
            this.eventListeners.get(event)!.add(callback);
          }

          off(event: string, callback: Function): void {
            this.eventListeners.get(event)?.delete(callback);
          }

          // Private methods
          private async fetch(path: string, options: RequestInit = {}): Promise<APIResponse<unknown>> {
            const url = `${this.baseUrl}/api/v1${path}`;
            const headers: Record<string, string> = {
              'Content-Type': 'application/json',
              ...options.headers as Record<string, string>,
            };

            if (this.apiKey) {
              headers['X-API-Key'] = this.apiKey;
            }

            let lastError: Error | undefined;
            for (let i = 0; i < this.retries; i++) {
              try {
                const response = await fetch(url, {
                  ...options,
                  headers,
                });

                const data: APIResponse<unknown> = await response.json();

                if (!data.success) {
                  throw new Error(data.error ?? 'Request failed');
                }

                return data;
              } catch (error) {
                lastError = error as Error;
                if (i < this.retries - 1) {
                  await this.sleep(Math.pow(2, i) * 1000);
                }
              }
            }

            throw lastError ?? new Error('Request failed');
          }

          private handleMessage(message: WSMessage): void {
            if (message.channel && message.type === 'event') {
              const callbacks = this.subscriptions.get(message.channel);
              callbacks?.forEach((callback) => {
                callback(message.payload as any);
              });
            }

            const handler = this.messageHandlers.get(message.id);
            if (handler) {
              handler(message.payload);
              this.messageHandlers.delete(message.id);
            }
          }

          private emit(event: string, data?: unknown): void {
            this.eventListeners.get(event)?.forEach((callback) => {
              callback(data);
            });
          }

          private generateId(): string {
            return Math.random().toString(36).substring(2, 15);
          }

          private sleep(ms: number): Promise<void> {
            return new Promise((resolve) => setTimeout(resolve, ms));
          }
        }

        export default CrystalCogClient;
        TS
      end

      def generate_package_json : String
        {
          "name"        => "@crystalcog/sdk",
          "version"     => "0.1.0",
          "description" => "TypeScript SDK for CrystalCog AtomSpace",
          "main"        => "dist/index.js",
          "module"      => "dist/index.mjs",
          "types"       => "dist/types.d.ts",
          "files"       => ["dist"],
          "scripts"     => {
            "build"      => "tsup src/index.ts --format cjs,esm --dts",
            "test"       => "vitest",
            "lint"       => "eslint src",
            "prepublish" => "npm run build",
          },
          "keywords"   => ["crystalcog", "atomspace", "ai", "knowledge-graph", "opencog"],
          "author"     => "CrystalCog Community",
          "license"    => "AGPL-3.0",
          "repository" => {
            "type" => "git",
            "url"  => "https://github.com/cogpy/crystalcog",
          },
          "devDependencies" => {
            "tsup"       => "^8.0.0",
            "typescript" => "^5.0.0",
            "vitest"     => "^1.0.0",
          },
          "peerDependencies" => {} of String => String,
        }.to_json
      end
    end

    # Unified TypeScript SDK Integration wrapper (follows Phase 5 patterns)
    class TypeScriptSDKIntegration
      VERSION = "0.3.0"

      property config : TypeScriptSDKConfig
      property server : TypeScriptSDKServer
      property generator : TypeScriptGenerator
      property atomspace : AtomSpace::AtomSpace?
      property initialized : Bool
      property requests_handled : Int64
      property websocket_connections : Int32

      def initialize(@config = TypeScriptSDKConfig.new)
        @server = TypeScriptSDKServer.new(@config)
        @generator = TypeScriptGenerator.new
        @atomspace = nil
        @initialized = false
        @requests_handled = 0_i64
        @websocket_connections = 0
      end

      # Attach AtomSpace (Phase 5 pattern)
      def attach_atomspace(atomspace : AtomSpace::AtomSpace)
        @atomspace = atomspace
      end

      # Initialize backend (Phase 5 pattern) - alias for start
      def initialize_backend : Bool
        return true if @initialized
        @initialized = true
        true
      end

      # Start server
      def start
        initialize_backend
        spawn { @server.start }
      end

      # Stop server
      def stop
        @server.stop
        @initialized = false
      end

      # Status reporting (Phase 5 pattern)
      def status : Hash(String, String)
        {
          "integration"           => "typescript_sdk",
          "version"               => VERSION,
          "status"                => @initialized ? "running" : "stopped",
          "atomspace_attached"    => (!@atomspace.nil?).to_s,
          "host"                  => @config.host,
          "port"                  => @config.port.to_s,
          "api_prefix"            => @config.api_prefix,
          "websocket_enabled"     => @config.enable_websocket.to_s,
          "auth_enabled"          => @config.auth_enabled.to_s,
          "cors_origins"          => @config.cors_origins.join(","),
          "requests_handled"      => @requests_handled.to_s,
          "websocket_connections" => @websocket_connections.to_s,
        }
      end

      # Generate SDK files
      def generate_types : String
        @generator.generate_types
      end

      def generate_client : String
        @generator.generate_client_code
      end

      def generate_package : String
        @generator.generate_package_json
      end

      # Write SDK to directory
      def write_sdk_to(directory : String)
        Dir.mkdir_p(directory)
        File.write(File.join(directory, "types.ts"), generate_types)
        File.write(File.join(directory, "client.ts"), generate_client)
        File.write(File.join(directory, "package.json"), generate_package)
      end

      # Disconnect
      def disconnect
        stop
      end

      # Link to cognitive agency (Phase 5 pattern)
      def link_component(name : String)
        # Cognitive agency linking support
      end
    end
  end

  # Module-level factory methods (Phase 5 pattern)
  module TypeScriptSDK
    def self.create_default_integration : Integrations::TypeScriptSDKIntegration
      Integrations::TypeScriptSDKIntegration.new
    end

    def self.create_integration(
      host : String = "0.0.0.0",
      port : Int32 = 8080,
      enable_websocket : Bool = true
    ) : Integrations::TypeScriptSDKIntegration
      config = Integrations::TypeScriptSDKConfig.new(
        host: host,
        port: port,
        enable_websocket: enable_websocket
      )
      Integrations::TypeScriptSDKIntegration.new(config)
    end

    def self.create_integration(config : Integrations::TypeScriptSDKConfig) : Integrations::TypeScriptSDKIntegration
      Integrations::TypeScriptSDKIntegration.new(config)
    end
  end
end

# Main entry point
if PROGRAM_NAME.includes?("typescript_sdk")
  puts "📦 CrystalCog TypeScript SDK v0.1.0"
  puts "=" * 50
  puts ""
  puts "REST API and WebSocket server for TypeScript/JavaScript"
  puts ""
  puts "Features:"
  puts "  • Full REST API for AtomSpace operations"
  puts "  • WebSocket support for real-time updates"
  puts "  • TypeScript type definitions"
  puts "  • OpenAPI 3.0 specification"
  puts "  • CORS support for web applications"
  puts "  • Optional API key authentication"
  puts ""
  puts "Usage:"
  puts "  server = TypeScriptSDKServer.new"
  puts "  server.start"
  puts ""
  puts "TypeScript Client:"
  puts "  import { CrystalCogClient } from '@crystalcog/sdk';"
  puts "  const client = new CrystalCogClient('http://localhost:8080');"
  puts "  const atoms = await client.getAtoms();"
  puts ""

  # Generate TypeScript files
  generator = CrystalCog::Integrations::TypeScriptGenerator.new

  puts "Generating TypeScript SDK files..."
  puts ""
  puts "types.ts:"
  puts "-" * 40
  puts generator.generate_types[0..500] + "..."
  puts ""
  puts "client.ts:"
  puts "-" * 40
  puts generator.generate_client_code[0..500] + "..."
end
