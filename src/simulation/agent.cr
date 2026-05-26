# Agent Implementation for Simulation
#
# Provides the Agent class for representing intelligent agents in the simulation,
# including sensor and actuator management, perception, and action capabilities.

require "../atomspace/atomspace_main"

module Simulation
  # Agent state for behavior management
  enum AgentState
    Idle
    Active
    Moving
    Executing
    Waiting
    Disabled
  end

  # Agent capability flags
  @[Flags]
  enum AgentCapabilities
    Move
    Rotate
    Sense
    Communicate
    Manipulate
    Learn
  end

  # Base Agent class
  class Agent < Entity
    property velocity : Vector3 = Vector3.zero
    property max_speed : Float64 = 5.0
    property max_acceleration : Float64 = 10.0
    property state : AgentState = AgentState::Idle
    property capabilities : AgentCapabilities = AgentCapabilities::Move | AgentCapabilities::Sense

    getter sensors : Array(Sensor)
    getter actuators : Array(Actuator)
    getter perception_data : Hash(String, Float64 | Bool | Array(Float64))
    property environment : SimulationEnvironment?

    # Goal-related properties
    property current_goal : Vector3?
    property goal_threshold : Float64 = 0.5

    def initialize(name : String, @environment : SimulationEnvironment? = nil)
      super(name, EntityType::Agent)
      @sensors = [] of Sensor
      @actuators = [] of Actuator
      @perception_data = {} of String => Float64 | Bool | Array(Float64)
    end

    # Add a sensor to the agent
    def add_sensor(sensor : Sensor)
      sensor.agent = self
      @sensors << sensor
      CogUtil::Logger.debug("Agent '#{@name}' added sensor: #{sensor.name}")
    end

    # Remove a sensor
    def remove_sensor(sensor : Sensor) : Bool
      @sensors.delete(sensor) != nil
    end

    # Add an actuator to the agent
    def add_actuator(actuator : Actuator)
      actuator.agent = self
      @actuators << actuator
      CogUtil::Logger.debug("Agent '#{@name}' added actuator: #{actuator.name}")
    end

    # Remove an actuator
    def remove_actuator(actuator : Actuator) : Bool
      @actuators.delete(actuator) != nil
    end

    # Get a sensor by name
    def sensor(name : String) : Sensor?
      @sensors.find { |s| s.name == name }
    end

    # Get an actuator by name
    def actuator(name : String) : Actuator?
      @actuators.find { |a| a.name == name }
    end

    # Update method called each simulation step
    def update(dt : Float64)
      return unless @enabled

      # Update sensors
      @sensors.each do |sensor|
        sensor.update(dt) if sensor.enabled
        # Collect perception data
        @perception_data[sensor.name] = sensor.value
      end

      # Update actuators
      @actuators.each do |actuator|
        actuator.update(dt) if actuator.enabled
      end

      # Process movement towards goal if set
      if goal = @current_goal
        move_towards_goal(goal, dt)
      end

      # Apply velocity
      if @velocity.magnitude_squared > 0.0001
        @transform.position = @transform.position + @velocity * dt
      end
    end

    # Set movement goal
    def set_goal(target : Vector3)
      @current_goal = target
      @state = AgentState::Moving
    end

    # Clear current goal
    def clear_goal
      @current_goal = nil
      @velocity = Vector3.zero
      @state = AgentState::Idle
    end

    # Check if agent has reached its goal
    def at_goal? : Bool
      if goal = @current_goal
        position.distance_to(goal) <= @goal_threshold
      else
        true
      end
    end

    # Move towards the current goal
    private def move_towards_goal(goal : Vector3, dt : Float64)
      direction = goal - position
      distance = direction.magnitude

      if distance <= @goal_threshold
        # Reached goal
        @velocity = Vector3.zero
        @current_goal = nil
        @state = AgentState::Idle
        CogUtil::Logger.debug("Agent '#{@name}' reached goal")
        return
      end

      # Calculate desired velocity
      desired_velocity = direction.normalized * Math.min(@max_speed, distance / dt)

      # Apply acceleration limit
      velocity_change = desired_velocity - @velocity
      max_change = @max_acceleration * dt

      if velocity_change.magnitude > max_change
        velocity_change = velocity_change.normalized * max_change
      end

      @velocity = @velocity + velocity_change

      # Face movement direction
      if @velocity.magnitude_squared > 0.01
        @transform.look_at(position + @velocity)
      end
    end

    # Execute an action
    def execute_action(action_name : String, parameters : Hash(String, Float64) = {} of String => Float64) : Bool
      # Find actuator that can execute this action
      @actuators.each do |actuator|
        if actuator.can_execute?(action_name)
          @state = AgentState::Executing
          result = actuator.execute(action_name, parameters)
          @state = AgentState::Idle if result
          return result
        end
      end
      false
    end

    # Get sensor readings as a hash
    def get_sensor_readings : Hash(String, Float64 | Bool | Array(Float64))
      @perception_data.dup
    end

    # Stop all movement
    def stop
      @velocity = Vector3.zero
      @current_goal = nil
      @state = AgentState::Idle
    end

    # Convert to AtomSpace representation
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom
      agent_node = super(atomspace)

      # Add agent-specific information
      state_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, @state.to_s)
      state_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "agent_state")
      state_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [agent_node, state_node])
      atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [state_pred, state_list])

      # Add velocity
      vel_x = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, @velocity.x.to_s)
      vel_y = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, @velocity.y.to_s)
      vel_z = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, @velocity.z.to_s)
      vel_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "velocity")
      vel_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [agent_node, vel_x, vel_y, vel_z])
      atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [vel_pred, vel_list])

      # Add sensor data
      @perception_data.each do |sensor_name, value|
        sensor_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "sensor:#{sensor_name}")
        case value
        when Float64
          value_node = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, value.to_s)
        when Bool
          value_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, value.to_s)
        else
          value_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, value.to_s)
        end
        sense_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "senses")
        sense_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [agent_node, sensor_node, value_node])
        atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [sense_pred, sense_list])
      end

      agent_node
    end
  end

  # Group of agents that can coordinate
  class AgentGroup
    getter name : String
    getter agents : Array(Agent)

    def initialize(@name : String)
      @agents = [] of Agent
    end

    def add(agent : Agent)
      @agents << agent unless @agents.includes?(agent)
    end

    def remove(agent : Agent)
      @agents.delete(agent)
    end

    def size : Int32
      @agents.size
    end

    def center_of_mass : Vector3
      return Vector3.zero if @agents.empty?

      sum = Vector3.zero
      @agents.each { |a| sum = sum + a.position }
      sum / @agents.size.to_f64
    end

    def spread : Float64
      return 0.0 if @agents.size < 2
      center = center_of_mass
      @agents.sum { |a| a.position.distance_to(center) } / @agents.size.to_f64
    end

    # Move all agents to form around a point
    def form_around(point : Vector3, radius : Float64 = 2.0)
      return if @agents.empty?

      angle_step = 2 * Math::PI / @agents.size
      @agents.each_with_index do |agent, i|
        angle = angle_step * i
        offset = Vector3.new(Math.cos(angle) * radius, 0.0, Math.sin(angle) * radius)
        agent.set_goal(point + offset)
      end
    end

    # Have all agents stop
    def stop_all
      @agents.each(&.stop)
    end
  end
end
