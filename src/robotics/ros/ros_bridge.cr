# ROS (Robot Operating System) Bridge for CrystalCog
#
# This module provides connectivity between CrystalCog's AtomSpace and ROS,
# enabling integration with robotic systems, sensors, and actuators via
# the ROS middleware.
#
# Note: This is a Crystal-native implementation using TCP/UDP sockets
# to communicate with rosbridge_server or direct ROS2 DDS.

require "../../cogutil/cogutil"
require "../spatial_reasoning"

module Robotics
  module ROS
    VERSION = "0.1.0"

    class ROSException < Exception
    end

    class ConnectionError < ROSException
    end

    class MessageError < ROSException
    end

    class ServiceError < ROSException
    end

    # ROS communication protocol types
    enum Protocol
      ROS1_XML_RPC  # ROS1 via rosbridge (websocket/TCP)
      ROS2_DDS      # ROS2 via DDS (UDP multicast)
      Rosbridge     # ROSBridge JSON protocol (works with both ROS1/ROS2)
    end

    # Connection state for ROS bridge
    enum ConnectionState
      Disconnected
      Connecting
      Connected
      Reconnecting
      Error
    end

    # Quality of Service settings for ROS2
    struct QoSProfile
      getter reliability : Symbol      # :reliable or :best_effort
      getter durability : Symbol        # :volatile or :transient_local
      getter history : Symbol           # :keep_last or :keep_all
      getter depth : Int32              # History depth
      getter deadline_ms : Int32        # Deadline in milliseconds (0 = infinite)
      getter lifespan_ms : Int32        # Lifespan in milliseconds (0 = infinite)

      def initialize(
        @reliability : Symbol = :reliable,
        @durability : Symbol = :volatile,
        @history : Symbol = :keep_last,
        @depth : Int32 = 10,
        @deadline_ms : Int32 = 0,
        @lifespan_ms : Int32 = 0
      )
      end

      # Predefined profiles
      def self.default : QoSProfile
        QoSProfile.new
      end

      def self.sensor_data : QoSProfile
        QoSProfile.new(
          reliability: :best_effort,
          durability: :volatile,
          depth: 5
        )
      end

      def self.services : QoSProfile
        QoSProfile.new(
          reliability: :reliable,
          durability: :volatile,
          depth: 10
        )
      end

      def self.parameters : QoSProfile
        QoSProfile.new(
          reliability: :reliable,
          durability: :transient_local,
          depth: 1000
        )
      end
    end

    # Configuration for ROS bridge connection
    struct BridgeConfig
      getter protocol : Protocol
      getter host : String
      getter port : Int32
      getter namespace : String
      getter node_name : String
      getter reconnect_attempts : Int32
      getter reconnect_delay_ms : Int32
      getter message_timeout_ms : Int32

      def initialize(
        @protocol : Protocol = Protocol::Rosbridge,
        @host : String = "localhost",
        @port : Int32 = 9090,
        @namespace : String = "/crystalcog",
        @node_name : String = "crystalcog_node",
        @reconnect_attempts : Int32 = 5,
        @reconnect_delay_ms : Int32 = 1000,
        @message_timeout_ms : Int32 = 5000
      )
      end
    end

    # Statistics for the ROS connection
    class ConnectionStats
      property messages_sent : Int64 = 0_i64
      property messages_received : Int64 = 0_i64
      property bytes_sent : Int64 = 0_i64
      property bytes_received : Int64 = 0_i64
      property errors : Int32 = 0
      property reconnections : Int32 = 0
      property last_message_time : Time?
      property connected_since : Time?

      def reset
        @messages_sent = 0_i64
        @messages_received = 0_i64
        @bytes_sent = 0_i64
        @bytes_received = 0_i64
        @errors = 0
        @reconnections = 0
        @last_message_time = nil
      end

      def uptime : Time::Span?
        if connected = @connected_since
          Time.utc - connected
        end
      end

      def to_s(io : IO)
        io << "ROSConnectionStats("
        io << "sent=#{@messages_sent}, "
        io << "received=#{@messages_received}, "
        io << "errors=#{@errors}, "
        io << "uptime=#{uptime || "disconnected"})"
      end
    end

    # Callback type for received messages
    alias MessageCallback = Proc(String, JSON::Any, Nil)

    # Callback type for service responses
    alias ServiceCallback = Proc(JSON::Any?, ROSException?, Nil)

    # Main ROS Bridge class - handles connection and communication with ROS
    class ROSBridge
      getter config : BridgeConfig
      getter state : ConnectionState
      getter stats : ConnectionStats
      
      @socket : TCPSocket?
      @subscribers : Hash(String, Array(MessageCallback))
      @service_clients : Hash(String, ServiceCallback)
      @advertised_topics : Hash(String, String)  # topic => message_type
      @pending_ops : Hash(String, Channel(JSON::Any?))
      @message_id : Int32
      @running : Bool
      @reader_fiber : Fiber?
      @mutex : Mutex

      def initialize(@config : BridgeConfig = BridgeConfig.new)
        @state = ConnectionState::Disconnected
        @stats = ConnectionStats.new
        @socket = nil
        @subscribers = {} of String => Array(MessageCallback)
        @service_clients = {} of String => ServiceCallback
        @advertised_topics = {} of String => String
        @pending_ops = {} of String => Channel(JSON::Any?)
        @message_id = 0
        @running = false
        @reader_fiber = nil
        @mutex = Mutex.new
        CogUtil::Logger.info("ROSBridge initialized with #{@config.protocol} protocol")
      end

      # Connect to the ROS system
      def connect : Bool
        return true if @state == ConnectionState::Connected

        @state = ConnectionState::Connecting
        CogUtil::Logger.info("Connecting to ROS at #{@config.host}:#{@config.port}...")

        attempts = 0
        while attempts < @config.reconnect_attempts
          begin
            @socket = TCPSocket.new(@config.host, @config.port)
            @socket.not_nil!.read_timeout = @config.message_timeout_ms.milliseconds
            @socket.not_nil!.write_timeout = @config.message_timeout_ms.milliseconds
            
            @state = ConnectionState::Connected
            @stats.connected_since = Time.utc
            @running = true
            
            # Start message reader fiber
            start_reader
            
            # Advertise ourselves to rosbridge
            send_advertise_node
            
            CogUtil::Logger.info("Successfully connected to ROS")
            return true
          rescue ex
            attempts += 1
            CogUtil::Logger.warn("Connection attempt #{attempts} failed: #{ex.message}")
            sleep(@config.reconnect_delay_ms.milliseconds)
          end
        end

        @state = ConnectionState::Error
        @stats.errors += 1
        CogUtil::Logger.error("Failed to connect to ROS after #{attempts} attempts")
        false
      end

      # Disconnect from ROS
      def disconnect
        return if @state == ConnectionState::Disconnected

        @running = false
        
        # Unadvertise all topics
        @advertised_topics.each_key do |topic|
          send_unadvertise(topic)
        end
        @advertised_topics.clear
        
        # Unsubscribe from all topics
        @subscribers.each_key do |topic|
          send_unsubscribe(topic)
        end
        @subscribers.clear

        @socket.try(&.close)
        @socket = nil
        @state = ConnectionState::Disconnected
        CogUtil::Logger.info("Disconnected from ROS")
      end

      # Check if connected
      def connected? : Bool
        @state == ConnectionState::Connected && @socket != nil
      end

      # Advertise a topic for publishing
      def advertise(topic : String, msg_type : String, qos : QoSProfile = QoSProfile.default) : Bool
        return false unless connected?
        
        full_topic = namespaced_topic(topic)
        return true if @advertised_topics.has_key?(full_topic)

        msg = {
          "op" => "advertise",
          "topic" => full_topic,
          "type" => msg_type
        }
        
        if send_json(msg)
          @advertised_topics[full_topic] = msg_type
          CogUtil::Logger.debug("Advertised topic: #{full_topic} [#{msg_type}]")
          true
        else
          false
        end
      end

      # Unadvertise a topic
      def unadvertise(topic : String) : Bool
        full_topic = namespaced_topic(topic)
        return true unless @advertised_topics.has_key?(full_topic)

        if send_unadvertise(full_topic)
          @advertised_topics.delete(full_topic)
          true
        else
          false
        end
      end

      # Publish a message to a topic
      def publish(topic : String, message : Hash(String, JSON::Any::Type) | NamedTuple) : Bool
        return false unless connected?

        full_topic = namespaced_topic(topic)
        
        # Auto-advertise if needed
        unless @advertised_topics.has_key?(full_topic)
          CogUtil::Logger.warn("Publishing to unadvertised topic: #{full_topic}")
        end

        msg = {
          "op" => "publish",
          "topic" => full_topic,
          "msg" => message
        }

        if send_json(msg)
          @stats.messages_sent += 1
          true
        else
          false
        end
      end

      # Subscribe to a topic
      def subscribe(topic : String, msg_type : String? = nil, 
                    qos : QoSProfile = QoSProfile.default, 
                    &callback : MessageCallback) : Bool
        return false unless connected?

        full_topic = namespaced_topic(topic)
        
        @mutex.synchronize do
          @subscribers[full_topic] ||= [] of MessageCallback
          @subscribers[full_topic] << callback
        end

        # Only send subscribe if this is the first subscriber
        if @subscribers[full_topic].size == 1
          msg = {
            "op" => "subscribe",
            "topic" => full_topic
          }
          msg = msg.merge({"type" => msg_type}) if msg_type

          unless send_json(msg)
            @subscribers.delete(full_topic)
            return false
          end
          
          CogUtil::Logger.debug("Subscribed to topic: #{full_topic}")
        end

        true
      end

      # Unsubscribe from a topic
      def unsubscribe(topic : String) : Bool
        full_topic = namespaced_topic(topic)
        
        @mutex.synchronize do
          @subscribers.delete(full_topic)
        end
        
        send_unsubscribe(full_topic)
      end

      # Call a ROS service (synchronous)
      def call_service(service : String, args : Hash(String, JSON::Any::Type)? = nil, 
                       timeout_ms : Int32? = nil) : JSON::Any?
        return nil unless connected?

        timeout = (timeout_ms || @config.message_timeout_ms).milliseconds
        full_service = namespaced_topic(service)
        
        op_id = next_message_id
        response_channel = Channel(JSON::Any?).new(1)
        
        @mutex.synchronize do
          @pending_ops[op_id] = response_channel
        end

        msg = {
          "op" => "call_service",
          "service" => full_service,
          "id" => op_id
        }
        msg = msg.merge({"args" => args}) if args

        unless send_json(msg)
          @pending_ops.delete(op_id)
          return nil
        end

        # Wait for response with timeout
        select
        when response = response_channel.receive
          @pending_ops.delete(op_id)
          response
        when timeout(timeout)
          @pending_ops.delete(op_id)
          raise ServiceError.new("Service call to #{full_service} timed out")
        end
      end

      # Call a ROS service (asynchronous)
      def call_service_async(service : String, args : Hash(String, JSON::Any::Type)? = nil,
                             &callback : ServiceCallback)
        spawn do
          begin
            result = call_service(service, args)
            callback.call(result, nil)
          rescue ex : ROSException
            callback.call(nil, ex)
          end
        end
      end

      # Get list of available topics
      def get_topics : Array(NamedTuple(name: String, type: String))?
        return nil unless connected?

        response = call_service("/rosapi/topics")
        return nil unless response

        topics = response["topics"]?.try(&.as_a?)
        types = response["types"]?.try(&.as_a?)
        
        return nil unless topics && types

        result = [] of NamedTuple(name: String, type: String)
        topics.each_with_index do |topic, i|
          result << {name: topic.as_s, type: types[i].as_s}
        end
        result
      end

      # Get list of available services
      def get_services : Array(String)?
        return nil unless connected?

        response = call_service("/rosapi/services")
        return nil unless response

        response["services"]?.try(&.as_a?.try(&.map(&.as_s)))
      end

      # Get list of active nodes
      def get_nodes : Array(String)?
        return nil unless connected?

        response = call_service("/rosapi/nodes")
        return nil unless response

        response["nodes"]?.try(&.as_a?.try(&.map(&.as_s)))
      end

      # Get parameter value
      def get_param(name : String) : JSON::Any?
        return nil unless connected?

        response = call_service("/rosapi/get_param", {"name" => name})
        response.try(&.["value"]?)
      end

      # Set parameter value
      def set_param(name : String, value : JSON::Any::Type) : Bool
        return false unless connected?

        response = call_service("/rosapi/set_param", {
          "name" => name,
          "value" => JSON.parse(value.to_json).raw
        })
        response != nil
      end

      private def namespaced_topic(topic : String) : String
        return topic if topic.starts_with?("/")
        "#{@config.namespace}/#{topic}".gsub("//", "/")
      end

      private def next_message_id : String
        @message_id += 1
        "crystalcog_#{@message_id}"
      end

      private def send_json(data) : Bool
        return false unless socket = @socket
        
        json_str = data.to_json + "\n"
        begin
          socket.write(json_str.to_slice)
          socket.flush
          @stats.bytes_sent += json_str.bytesize
          true
        rescue ex
          CogUtil::Logger.error("Failed to send message: #{ex.message}")
          @stats.errors += 1
          handle_disconnection
          false
        end
      end

      private def send_advertise_node
        # Rosbridge doesn't require explicit node advertisement,
        # but we can set up the namespace
        msg = {
          "op" => "set_level",
          "level" => "warning"  # Reduce rosbridge logging
        }
        send_json(msg)
      end

      private def send_unadvertise(topic : String) : Bool
        msg = {
          "op" => "unadvertise",
          "topic" => topic
        }
        send_json(msg)
      end

      private def send_unsubscribe(topic : String) : Bool
        msg = {
          "op" => "unsubscribe",
          "topic" => topic
        }
        send_json(msg)
      end

      private def start_reader
        @reader_fiber = spawn do
          buffer = String::Builder.new
          
          while @running && (socket = @socket)
            begin
              # Read data from socket
              bytes = Bytes.new(4096)
              read_count = socket.read(bytes)
              
              if read_count == 0
                # Connection closed
                handle_disconnection
                break
              end

              @stats.bytes_received += read_count
              buffer << String.new(bytes[0, read_count])

              # Process complete JSON messages (newline delimited)
              while (newline_idx = buffer.to_s.index('\n'))
                json_str = buffer.to_s[0, newline_idx]
                remaining = buffer.to_s[(newline_idx + 1)..]
                buffer = String::Builder.new
                buffer << remaining

                process_message(json_str) unless json_str.empty?
              end

            rescue IO::TimeoutError
              # Read timeout, continue loop
            rescue ex
              CogUtil::Logger.error("Reader error: #{ex.message}")
              @stats.errors += 1
              handle_disconnection
              break
            end
          end
        end
      end

      private def process_message(json_str : String)
        begin
          data = JSON.parse(json_str)
          op = data["op"]?.try(&.as_s?)
          
          case op
          when "publish"
            # Incoming message on subscribed topic
            topic = data["topic"]?.try(&.as_s)
            msg = data["msg"]?
            if topic && msg
              @stats.messages_received += 1
              @stats.last_message_time = Time.utc
              dispatch_message(topic, msg)
            end
            
          when "service_response"
            # Response to a service call
            id = data["id"]?.try(&.as_s)
            values = data["values"]?
            if id && (channel = @pending_ops[id]?)
              channel.send(values)
            end
            
          when "status"
            # Status message from rosbridge
            level = data["level"]?.try(&.as_s)
            message = data["msg"]?.try(&.as_s)
            CogUtil::Logger.debug("ROS status [#{level}]: #{message}")
            
          else
            CogUtil::Logger.debug("Unknown ROS message op: #{op}")
          end
          
        rescue ex
          CogUtil::Logger.error("Failed to parse ROS message: #{ex.message}")
          @stats.errors += 1
        end
      end

      private def dispatch_message(topic : String, msg : JSON::Any)
        callbacks = @mutex.synchronize { @subscribers[topic]?.try(&.dup) }
        return unless callbacks

        callbacks.each do |callback|
          spawn do
            begin
              callback.call(topic, msg)
            rescue ex
              CogUtil::Logger.error("Callback error for #{topic}: #{ex.message}")
            end
          end
        end
      end

      private def handle_disconnection
        return if @state == ConnectionState::Disconnected
        
        @state = ConnectionState::Reconnecting
        @socket.try(&.close)
        @socket = nil
        @stats.reconnections += 1
        
        CogUtil::Logger.warn("ROS connection lost, attempting reconnection...")
        
        spawn do
          sleep(@config.reconnect_delay_ms.milliseconds)
          connect if @running
        end
      end
    end

    # Singleton access to the global ROS bridge
    class_getter bridge : ROSBridge { ROSBridge.new }

    def self.configure(config : BridgeConfig)
      @@bridge = ROSBridge.new(config)
    end

    def self.connect : Bool
      bridge.connect
    end

    def self.disconnect
      bridge.disconnect
    end

    def self.connected? : Bool
      bridge.connected?
    end
  end
end
