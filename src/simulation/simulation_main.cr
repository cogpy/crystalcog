# Simulation Module Main Entry Point
#
# This module provides the Virtual World / Simulation Integration for CrystalCog.
# It enables interaction with simulation environments like Unity3D, Gazebo, and custom simulators.
#
# Features:
# - Generic simulation environment interface
# - Unity3D integration via REST/WebSocket API
# - Gazebo/ROS simulation support
# - Physics state ↔ AtomSpace mapping
# - Agent embodiment abstractions
# - Virtual sensor and actuator interfaces
# - Simulation time management

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./environment"
require "./physics"
require "./agent"
require "./sensors"
require "./actuators"
require "./time_manager"
require "./unity_bridge"
require "./gazebo_bridge"

module Simulation
  VERSION = "0.1.0"

  # Module-level configuration
  class_property default_timestep : Float64 = 0.01
  class_property max_physics_substeps : Int32 = 10

  # Initialize the simulation subsystem
  def self.initialize
    CogUtil::Logger.info("Simulation #{VERSION} initializing")
    CogUtil.initialize
    AtomSpace.initialize
    CogUtil::Logger.info("Simulation #{VERSION} initialized")
  end

  # Factory methods for creating simulation environments

  # Create a local simulation environment (no external simulator)
  def self.create_local_environment(name : String = "local") : LocalEnvironment
    LocalEnvironment.new(name)
  end

  # Create a Unity bridge connection
  def self.create_unity_bridge(host : String = "localhost", port : Int32 = 8080) : UnityBridge
    UnityBridge.new(host, port)
  end

  # Create a Gazebo bridge connection
  def self.create_gazebo_bridge(ros_master_uri : String? = nil) : GazeboBridge
    GazeboBridge.new(ros_master_uri)
  end

  # Create an agent with default capabilities
  def self.create_agent(
    name : String,
    environment : SimulationEnvironment,
    position : Vector3 = Vector3.zero
  ) : Agent
    agent = Agent.new(name, environment)
    agent.position = position
    agent
  end

  # Convenience method to run a simulation step
  def self.step(environment : SimulationEnvironment, dt : Float64 = default_timestep)
    environment.step(dt)
  end

  # Run simulation for a specified duration
  def self.run(
    environment : SimulationEnvironment,
    duration : Float64,
    timestep : Float64 = default_timestep
  )
    steps = (duration / timestep).to_i
    steps.times do
      environment.step(timestep)
    end
  end

  # Utility to convert simulation state to AtomSpace representation
  def self.state_to_atomspace(
    environment : SimulationEnvironment,
    atomspace : AtomSpace::AtomSpace
  ) : AtomSpace::Atom
    # Create environment concept
    env_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "simulation:#{environment.name}")

    # Add time
    time_node = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, environment.time_manager.current_time.to_s)
    time_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "simulation_time")
    time_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [env_node, time_node])
    atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [time_pred, time_list])

    # Add each agent's state
    environment.agents.each do |agent|
      agent_node = agent.to_atomspace(atomspace)
      member_link = atomspace.add_link(AtomSpace::AtomType::MEMBER_LINK, [agent_node, env_node])
    end

    env_node
  end
end

# Main entry point for standalone execution
if PROGRAM_NAME.includes?("simulation")
  Simulation.initialize

  puts "=" * 60
  puts "CrystalCog Simulation Module v#{Simulation::VERSION}"
  puts "=" * 60

  # Demo: Create a local simulation
  puts "\n--- Local Simulation Demo ---"
  env = Simulation.create_local_environment("demo_world")

  # Add an agent
  agent = Simulation.create_agent("robot1", env, Simulation::Vector3.new(0.0, 0.0, 0.0))

  # Add basic sensors
  agent.add_sensor(Simulation::PositionSensor.new)
  agent.add_sensor(Simulation::OrientationSensor.new)
  agent.add_sensor(Simulation::RangeSensor.new(range: 10.0))

  # Run simulation
  puts "Running simulation..."
  10.times do |i|
    env.step(0.1)
    pos = agent.position
    puts "Step #{i + 1}: Agent at (#{pos.x.round(2)}, #{pos.y.round(2)}, #{pos.z.round(2)})"
  end

  # Export to AtomSpace
  atomspace = AtomSpace::AtomSpace.new
  Simulation.state_to_atomspace(env, atomspace)
  puts "\nAtomSpace now contains #{atomspace.size} atoms"

  puts "\n" + "=" * 60
  puts "Simulation module demonstration complete."
end
