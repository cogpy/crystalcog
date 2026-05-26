# Unity3D Bridge for Simulation
#
# Provides integration with Unity3D game engine via REST/WebSocket API.
# This enables CrystalCog agents to operate in Unity-based virtual worlds.

require "http/client"
require "json"

module Simulation
  # Unity connection status
  enum UnityConnectionState
    Disconnected
    Connecting
    Connected
    Error
  end

  # Unity message types
  enum UnityMessageType
    Command       # Send command to Unity
    StateUpdate   # Receive state update from Unity
    Event         # Receive event notification
    Spawn         # Create entity in Unity
    Destroy       # Remove entity from Unity
    Query         # Query Unity state
    Response      # Response to query
  end

  # Unity Bridge - connects to Unity3D via HTTP/WebSocket
  class UnityBridge < SimulationEnvironment
    getter host : String
    getter port : Int32
    getter state : UnityConnectionState = UnityConnectionState::Disconnected

    @client : HTTP::Client?
    @websocket : HTTP::WebSocket?
    @use_websocket : Bool = false
    @message_queue : Array(JSON::Any)
    @pending_entities : Hash(String, Transform)

    def initialize(@host : String = "localhost", @port : Int32 = 8080)
      super("unity")
      @message_queue = [] of JSON::Any
      @pending_entities = {} of String => Transform
    end

    # Connect to Unity
    def connect : Bool
      @state = UnityConnectionState::Connecting

      begin
        @client = HTTP::Client.new(@host, @port)
        @client.not_nil!.connect_timeout = 5.seconds
        @client.not_nil!.read_timeout = 5.seconds

        # Test connection
        response = @client.not_nil!.get("/api/status")
        if response.status_code == 200
          @state = UnityConnectionState::Connected
          CogUtil::Logger.info("Connected to Unity at #{@host}:#{@port}")
          true
        else
          @state = UnityConnectionState::Error
          CogUtil::Logger.error("Unity connection failed: #{response.status_code}")
          false
        end
      rescue ex
        @state = UnityConnectionState::Error
        CogUtil::Logger.error("Unity connection error: #{ex.message}")
        false
      end
    end

    # Disconnect from Unity
    def disconnect
      @client.try(&.close)
      @client = nil
      @websocket.try(&.close)
      @websocket = nil
      @state = UnityConnectionState::Disconnected
      CogUtil::Logger.info("Disconnected from Unity")
    end

    # Check if connected
    def connected? : Bool
      @state == UnityConnectionState::Connected
    end

    # Step the simulation (sync state with Unity)
    def step(dt : Float64)
      return unless connected?

      @time_manager.advance(dt)

      # Send pending commands
      flush_commands

      # Request state update from Unity
      sync_state

      # Update local agents/objects
      @agents.each do |agent|
        agent.update(dt) if agent.enabled
      end

      @objects.each do |obj|
        obj.update(dt) if obj.enabled
      end
    end

    # Spawn an entity in Unity
    def spawn(name : String, prefab : String, position : Vector3, rotation : Quaternion = Quaternion.identity) : Bool
      return false unless connected?

      data = {
        "type"     => "spawn",
        "name"     => name,
        "prefab"   => prefab,
        "position" => {"x" => position.x, "y" => position.y, "z" => position.z},
        "rotation" => {"x" => rotation.x, "y" => rotation.y, "z" => rotation.z, "w" => rotation.w},
      }

      send_command(data)
    end

    # Destroy an entity in Unity
    def destroy(name : String) : Bool
      return false unless connected?

      data = {
        "type" => "destroy",
        "name" => name,
      }

      send_command(data)
    end

    # Set entity transform in Unity
    def set_transform(name : String, position : Vector3, rotation : Quaternion? = nil) : Bool
      return false unless connected?

      data = {
        "type"     => "transform",
        "name"     => name,
        "position" => {"x" => position.x, "y" => position.y, "z" => position.z},
      }

      if rot = rotation
        data = data.merge({"rotation" => {"x" => rot.x, "y" => rot.y, "z" => rot.z, "w" => rot.w}})
      end

      send_command(data)
    end

    # Send a custom command to Unity
    def send_custom_command(command : String, data : Hash(String, String | Float64 | Int32 | Bool)) : Bool
      return false unless connected?

      command_data = data.merge({"type" => command})
      send_command(command_data)
    end

    # Query entity state from Unity
    def query_entity(name : String) : Hash(String, JSON::Any)?
      return nil unless connected?

      begin
        response = @client.not_nil!.get("/api/entity/#{name}")
        if response.status_code == 200
          JSON.parse(response.body).as_h
        else
          nil
        end
      rescue
        nil
      end
    end

    # Query all entities from Unity
    def query_all_entities : Array(Hash(String, JSON::Any))
      return [] of Hash(String, JSON::Any) unless connected?

      begin
        response = @client.not_nil!.get("/api/entities")
        if response.status_code == 200
          JSON.parse(response.body).as_a.map(&.as_h)
        else
          [] of Hash(String, JSON::Any)
        end
      rescue
        [] of Hash(String, JSON::Any)
      end
    end

    # Get simulation time from Unity
    def get_unity_time : Float64?
      return nil unless connected?

      begin
        response = @client.not_nil!.get("/api/time")
        if response.status_code == 200
          JSON.parse(response.body)["time"]?.try(&.as_f?)
        else
          nil
        end
      rescue
        nil
      end
    end

    # Pause Unity simulation
    def pause_unity
      send_custom_command("pause", {} of String => String | Float64 | Int32 | Bool)
      @time_manager.pause
    end

    # Resume Unity simulation
    def resume_unity
      send_custom_command("resume", {} of String => String | Float64 | Int32 | Bool)
      @time_manager.resume
    end

    # Set time scale in Unity
    def set_unity_time_scale(scale : Float64)
      send_custom_command("timescale", {"scale" => scale})
      @time_manager.set_time_scale(scale)
    end

    private def send_command(data) : Bool
      begin
        json = data.to_json
        response = @client.not_nil!.post("/api/command", body: json, headers: HTTP::Headers{"Content-Type" => "application/json"})
        response.status_code == 200
      rescue ex
        CogUtil::Logger.error("Unity command failed: #{ex.message}")
        false
      end
    end

    private def flush_commands
      # Flush any queued commands
      while !@message_queue.empty?
        msg = @message_queue.shift
        send_command(msg.as_h)
      end
    end

    private def sync_state
      # Sync agent positions with Unity
      @agents.each do |agent|
        if entity_data = query_entity(agent.name)
          if pos = entity_data["position"]?
            agent.position = Vector3.new(
              pos["x"]?.try(&.as_f?) || 0.0,
              pos["y"]?.try(&.as_f?) || 0.0,
              pos["z"]?.try(&.as_f?) || 0.0
            )
          end
        end
      end
    end
  end

  # Unity event handler callback type
  alias UnityEventCallback = Proc(String, JSON::Any, Nil)

  # Unity event listener
  class UnityEventListener
    @callbacks : Hash(String, Array(UnityEventCallback))

    def initialize
      @callbacks = {} of String => Array(UnityEventCallback)
    end

    def on(event_type : String, &callback : UnityEventCallback)
      @callbacks[event_type] ||= [] of UnityEventCallback
      @callbacks[event_type] << callback
    end

    def emit(event_type : String, data : JSON::Any)
      if callbacks = @callbacks[event_type]?
        callbacks.each { |cb| cb.call(event_type, data) }
      end
    end

    def clear(event_type : String? = nil)
      if et = event_type
        @callbacks.delete(et)
      else
        @callbacks.clear
      end
    end
  end
end
