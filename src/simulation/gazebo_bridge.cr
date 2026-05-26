# Gazebo/ROS Bridge for Simulation
#
# Provides integration with Gazebo robotics simulator through ROS.
# This enables CrystalCog agents to operate in physics-accurate robot simulations.

require "../robotics/ros/ros_main"
require "json"

module Simulation
  # Gazebo connection state
  enum GazeboConnectionState
    Disconnected
    Connecting
    Connected
    Error
  end

  # Gazebo model info
  struct GazeboModel
    property name : String
    property type : String
    property position : Vector3
    property rotation : Quaternion
    property scale : Vector3

    def initialize(
      @name : String,
      @type : String = "model",
      @position : Vector3 = Vector3.zero,
      @rotation : Quaternion = Quaternion.identity,
      @scale : Vector3 = Vector3.one
    )
    end
  end

  # Gazebo Bridge - connects to Gazebo via ROS
  class GazeboBridge < SimulationEnvironment
    getter ros_master_uri : String?
    getter state : GazeboConnectionState = GazeboConnectionState::Disconnected
    getter models : Array(GazeboModel)

    @ros_bridge : Robotics::ROS::ROSBridge?
    @model_states_topic : String = "/gazebo/model_states"
    @set_model_state_service : String = "/gazebo/set_model_state"
    @spawn_model_service : String = "/gazebo/spawn_urdf_model"
    @delete_model_service : String = "/gazebo/delete_model"

    def initialize(@ros_master_uri : String? = nil)
      super("gazebo")
      @models = [] of GazeboModel
    end

    # Connect to Gazebo via ROS
    def connect : Bool
      @state = GazeboConnectionState::Connecting

      begin
        # Configure ROS bridge
        config = Robotics::ROS::BridgeConfig.new(
          host: "localhost",
          port: 9090,
          namespace: "/gazebo_bridge"
        )

        @ros_bridge = Robotics::ROS::ROSBridge.new(config)

        if @ros_bridge.not_nil!.connect
          @state = GazeboConnectionState::Connected
          CogUtil::Logger.info("Connected to Gazebo via ROS")

          # Subscribe to model states
          subscribe_to_model_states

          true
        else
          @state = GazeboConnectionState::Error
          CogUtil::Logger.error("Failed to connect to ROS")
          false
        end
      rescue ex
        @state = GazeboConnectionState::Error
        CogUtil::Logger.error("Gazebo connection error: #{ex.message}")
        false
      end
    end

    # Disconnect from Gazebo
    def disconnect
      @ros_bridge.try(&.disconnect)
      @ros_bridge = nil
      @state = GazeboConnectionState::Disconnected
      CogUtil::Logger.info("Disconnected from Gazebo")
    end

    # Check if connected
    def connected? : Bool
      @state == GazeboConnectionState::Connected
    end

    # Step the simulation
    def step(dt : Float64)
      return unless connected?

      @time_manager.advance(dt)

      # Update local state from Gazebo
      sync_model_states

      # Update agents with current positions
      @agents.each do |agent|
        agent.update(dt) if agent.enabled

        # Push agent state back to Gazebo
        set_model_state(agent.name, agent.position, agent.rotation)
      end

      @objects.each do |obj|
        obj.update(dt) if obj.enabled
      end
    end

    # Spawn a model in Gazebo
    def spawn_model(
      name : String,
      model_xml : String,
      position : Vector3 = Vector3.zero,
      rotation : Quaternion = Quaternion.identity,
      reference_frame : String = "world"
    ) : Bool
      return false unless connected?

      bridge = @ros_bridge
      return false unless bridge

      args = {
        "model_name"      => name,
        "model_xml"       => model_xml,
        "robot_namespace" => "",
        "initial_pose"    => {
          "position"    => {"x" => position.x, "y" => position.y, "z" => position.z},
          "orientation" => {"x" => rotation.x, "y" => rotation.y, "z" => rotation.z, "w" => rotation.w},
        },
        "reference_frame" => reference_frame,
      }

      begin
        response = bridge.call_service(@spawn_model_service, args)
        if response
          success = response["success"]?.try(&.as_bool?)
          if success
            @models << GazeboModel.new(name, "spawned", position, rotation)
            CogUtil::Logger.info("Spawned model '#{name}' in Gazebo")
            true
          else
            CogUtil::Logger.error("Failed to spawn model: #{response["status_message"]?}")
            false
          end
        else
          false
        end
      rescue ex
        CogUtil::Logger.error("Spawn model error: #{ex.message}")
        false
      end
    end

    # Delete a model from Gazebo
    def delete_model(name : String) : Bool
      return false unless connected?

      bridge = @ros_bridge
      return false unless bridge

      args = {"model_name" => name}

      begin
        response = bridge.call_service(@delete_model_service, args)
        if response && response["success"]?.try(&.as_bool?)
          @models.reject! { |m| m.name == name }
          CogUtil::Logger.info("Deleted model '#{name}' from Gazebo")
          true
        else
          false
        end
      rescue
        false
      end
    end

    # Set model state in Gazebo
    def set_model_state(
      name : String,
      position : Vector3,
      rotation : Quaternion = Quaternion.identity,
      linear_velocity : Vector3 = Vector3.zero,
      angular_velocity : Vector3 = Vector3.zero
    ) : Bool
      return false unless connected?

      bridge = @ros_bridge
      return false unless bridge

      state = {
        "model_name" => name,
        "pose"       => {
          "position"    => {"x" => position.x, "y" => position.y, "z" => position.z},
          "orientation" => {"x" => rotation.x, "y" => rotation.y, "z" => rotation.z, "w" => rotation.w},
        },
        "twist" => {
          "linear"  => {"x" => linear_velocity.x, "y" => linear_velocity.y, "z" => linear_velocity.z},
          "angular" => {"x" => angular_velocity.x, "y" => angular_velocity.y, "z" => angular_velocity.z},
        },
        "reference_frame" => "world",
      }

      begin
        response = bridge.call_service(@set_model_state_service, {"model_state" => state})
        response != nil && response["success"]?.try(&.as_bool?) || false
      rescue
        false
      end
    end

    # Apply force to a model
    def apply_force(
      name : String,
      force : Vector3,
      torque : Vector3 = Vector3.zero,
      duration : Float64 = 0.0
    ) : Bool
      return false unless connected?

      bridge = @ros_bridge
      return false unless bridge

      wrench = {
        "body_name"      => name,
        "reference_frame" => "world",
        "wrench"          => {
          "force"  => {"x" => force.x, "y" => force.y, "z" => force.z},
          "torque" => {"x" => torque.x, "y" => torque.y, "z" => torque.z},
        },
        "start_time" => {"secs" => 0, "nsecs" => 0},
        "duration"   => {"secs" => duration.to_i, "nsecs" => ((duration % 1.0) * 1e9).to_i},
      }

      begin
        response = bridge.call_service("/gazebo/apply_body_wrench", wrench)
        response != nil
      rescue
        false
      end
    end

    # Pause Gazebo simulation
    def pause_gazebo : Bool
      return false unless connected?

      bridge = @ros_bridge
      return false unless bridge

      begin
        response = bridge.call_service("/gazebo/pause_physics")
        if response
          @time_manager.pause
          true
        else
          false
        end
      rescue
        false
      end
    end

    # Resume Gazebo simulation
    def resume_gazebo : Bool
      return false unless connected?

      bridge = @ros_bridge
      return false unless bridge

      begin
        response = bridge.call_service("/gazebo/unpause_physics")
        if response
          @time_manager.resume
          true
        else
          false
        end
      rescue
        false
      end
    end

    # Reset Gazebo simulation
    def reset_simulation : Bool
      return false unless connected?

      bridge = @ros_bridge
      return false unless bridge

      begin
        response = bridge.call_service("/gazebo/reset_simulation")
        if response
          @time_manager.reset
          true
        else
          false
        end
      rescue
        false
      end
    end

    # Get model state from Gazebo
    def get_model_state(name : String) : GazeboModel?
      @models.find { |m| m.name == name }
    end

    # List all models in Gazebo
    def list_models : Array(String)
      @models.map(&.name)
    end

    private def subscribe_to_model_states
      bridge = @ros_bridge
      return unless bridge

      bridge.subscribe(@model_states_topic, "gazebo_msgs/ModelStates") do |_topic, msg|
        process_model_states(msg)
      end
    end

    private def process_model_states(msg : JSON::Any)
      names = msg["name"]?.try(&.as_a?)
      poses = msg["pose"]?.try(&.as_a?)

      return unless names && poses

      @models.clear

      names.each_with_index do |name_any, i|
        name = name_any.as_s
        pose = poses[i]?
        next unless pose

        position = Vector3.zero
        rotation = Quaternion.identity

        if pos = pose["position"]?
          position = Vector3.new(
            pos["x"]?.try(&.as_f?) || 0.0,
            pos["y"]?.try(&.as_f?) || 0.0,
            pos["z"]?.try(&.as_f?) || 0.0
          )
        end

        if orient = pose["orientation"]?
          rotation = Quaternion.new(
            orient["x"]?.try(&.as_f?) || 0.0,
            orient["y"]?.try(&.as_f?) || 0.0,
            orient["z"]?.try(&.as_f?) || 0.0,
            orient["w"]?.try(&.as_f?) || 1.0
          )
        end

        @models << GazeboModel.new(name, "gazebo", position, rotation)
      end
    end

    private def sync_model_states
      # Update agent positions from Gazebo models
      @agents.each do |agent|
        if model = @models.find { |m| m.name == agent.name }
          agent.position = model.position
          agent.rotation = model.rotation
        end
      end
    end
  end

  # Gazebo sensor integration
  class GazeboSensorBridge
    getter bridge : GazeboBridge
    @subscriptions : Hash(String, String)

    def initialize(@bridge : GazeboBridge)
      @subscriptions = {} of String => String
    end

    # Subscribe to a Gazebo sensor topic
    def subscribe_sensor(topic : String, sensor_type : String, &callback : JSON::Any -> Nil)
      ros_bridge = @bridge.@ros_bridge
      return unless ros_bridge

      ros_bridge.subscribe(topic, sensor_type) do |_t, msg|
        callback.call(msg)
      end

      @subscriptions[topic] = sensor_type
      CogUtil::Logger.debug("Subscribed to Gazebo sensor: #{topic}")
    end

    # Unsubscribe from a sensor topic
    def unsubscribe_sensor(topic : String)
      ros_bridge = @bridge.@ros_bridge
      return unless ros_bridge

      ros_bridge.unsubscribe(topic)
      @subscriptions.delete(topic)
    end

    # Get laser scan data
    def get_laser_scan(topic : String) : Array(Float32)?
      # This would be populated by subscription callback
      nil
    end

    # Get camera image
    def get_camera_image(topic : String) : Bytes?
      # This would be populated by subscription callback
      nil
    end

    # Get IMU data
    def get_imu_data(topic : String) : NamedTuple(orientation: Quaternion, angular_velocity: Vector3, linear_acceleration: Vector3)?
      # This would be populated by subscription callback
      nil
    end
  end
end
