# ROS Integration Main Module for CrystalCog
# Provides unified interface for ROS1/ROS2 communication

require "./ros_bridge"
require "./messages"

module CrystalCog::Robotics::ROS
  VERSION = "0.1.0"

  # Main ROS interface class
  class ROSInterface
    getter bridge : ROSBridge
    getter node_name : String

    def initialize(@node_name : String, config : BridgeConfig = BridgeConfig.new)
      @bridge = ROSBridge.new(config)
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
    def publish(topic : String, message : Message)
      @bridge.publish(topic, message.message_type, message)
    end

    def subscribe(topic : String, message_type : String, &callback : MessageCallback)
      @bridge.subscribe(topic, message_type, &callback)
    end

    def unsubscribe(topic : String)
      @bridge.unsubscribe(topic)
    end

    def call_service(service : String, request : Hash(String, JSON::Any), timeout : Time::Span = 30.seconds)
      @bridge.call_service(service, request, timeout)
    end

    # AtomSpace integration helpers
    def pose_to_atoms(pose : Pose, atomspace : AtomSpace, context : String = "robot") : Atom
      pos_node = atomspace.add_node(AtomType::ConceptNode, "#{context}_position")
      orient_node = atomspace.add_node(AtomType::ConceptNode, "#{context}_orientation")
      
      x_val = atomspace.add_node(AtomType::NumberNode, pose.position.x.to_s)
      y_val = atomspace.add_node(AtomType::NumberNode, pose.position.y.to_s)
      z_val = atomspace.add_node(AtomType::NumberNode, pose.position.z.to_s)
      
      atomspace.add_link(AtomType::ListLink, [pos_node, x_val, y_val, z_val])
    end

    def twist_to_atoms(twist : Twist, atomspace : AtomSpace, context : String = "robot") : Atom
      vel_node = atomspace.add_node(AtomType::ConceptNode, "#{context}_velocity")
      
      lin_x = atomspace.add_node(AtomType::NumberNode, twist.linear.x.to_s)
      lin_y = atomspace.add_node(AtomType::NumberNode, twist.linear.y.to_s)
      lin_z = atomspace.add_node(AtomType::NumberNode, twist.linear.z.to_s)
      
      atomspace.add_link(AtomType::ListLink, [vel_node, lin_x, lin_y, lin_z])
    end
  end

  # Factory method
  def self.create_interface(node_name : String, host : String = "localhost", port : Int32 = 9090) : ROSInterface
    config = BridgeConfig.new(host: host, port: port)
    ROSInterface.new(node_name, config)
  end
end
