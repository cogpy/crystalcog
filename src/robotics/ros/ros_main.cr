# ROS Integration Main Module for CrystalCog
# Provides unified interface for ROS1/ROS2 communication

require "./ros_bridge"
require "./messages"

# The messages are defined in CrystalCog::Robotics::ROS namespace
# The bridge is defined in Robotics::ROS namespace  
# We need to unify them

module CrystalCog::Robotics::ROS
  # Main ROS interface class that provides a unified interface
  class ROSInterface
    getter bridge : ::Robotics::ROS::ROSBridge
    getter node_name : String

    def initialize(@node_name : String, config : ::Robotics::ROS::BridgeConfig = ::Robotics::ROS::BridgeConfig.new)
      @bridge = ::Robotics::ROS::ROSBridge.new(config)
    end

    def connect : Bool
      @bridge.connect
    end

    def disconnect
      @bridge.disconnect
    end

    def connected? : Bool
      @bridge.connected?
    end

    # Convenience methods for common operations
    def publish(topic : String, message)
      @bridge.publish(topic, message)
    end

    def subscribe(topic : String, msg_type : String? = nil, &callback : ::Robotics::ROS::MessageCallback)
      @bridge.subscribe(topic, msg_type, &callback)
    end

    def unsubscribe(topic : String)
      @bridge.unsubscribe(topic)
    end

    def call_service(service : String, request : Hash(String, JSON::Any::Type)? = nil, timeout : Time::Span = 30.seconds)
      @bridge.call_service(service, request, (timeout.total_milliseconds.to_i))
    end
  end

  # Also expose BridgeConfig in this namespace
  BridgeConfig = ::Robotics::ROS::BridgeConfig

  # Factory method
  def self.create_interface(node_name : String, host : String = "localhost", port : Int32 = 9090) : ROSInterface
    config = ::Robotics::ROS::BridgeConfig.new(host: host, port: port)
    ROSInterface.new(node_name, config)
  end
end
