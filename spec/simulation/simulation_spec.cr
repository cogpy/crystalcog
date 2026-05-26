require "../spec_helper"
require "../../src/simulation/simulation_main"

describe Simulation do
  describe Simulation::Vector3 do
    it "creates a zero vector" do
      v = Simulation::Vector3.zero
      v.x.should eq(0.0)
      v.y.should eq(0.0)
      v.z.should eq(0.0)
    end

    it "creates a vector with components" do
      v = Simulation::Vector3.new(1.0, 2.0, 3.0)
      v.x.should eq(1.0)
      v.y.should eq(2.0)
      v.z.should eq(3.0)
    end

    it "adds two vectors" do
      v1 = Simulation::Vector3.new(1.0, 2.0, 3.0)
      v2 = Simulation::Vector3.new(4.0, 5.0, 6.0)
      result = v1 + v2
      result.x.should eq(5.0)
      result.y.should eq(7.0)
      result.z.should eq(9.0)
    end

    it "subtracts two vectors" do
      v1 = Simulation::Vector3.new(4.0, 5.0, 6.0)
      v2 = Simulation::Vector3.new(1.0, 2.0, 3.0)
      result = v1 - v2
      result.x.should eq(3.0)
      result.y.should eq(3.0)
      result.z.should eq(3.0)
    end

    it "multiplies vector by scalar" do
      v = Simulation::Vector3.new(1.0, 2.0, 3.0)
      result = v * 2.0
      result.x.should eq(2.0)
      result.y.should eq(4.0)
      result.z.should eq(6.0)
    end

    it "calculates magnitude" do
      v = Simulation::Vector3.new(3.0, 4.0, 0.0)
      v.magnitude.should eq(5.0)
    end

    it "normalizes vector" do
      v = Simulation::Vector3.new(3.0, 0.0, 0.0)
      normalized = v.normalized
      normalized.x.should eq(1.0)
      normalized.magnitude.should be_close(1.0, 0.0001)
    end

    it "calculates distance" do
      v1 = Simulation::Vector3.new(0.0, 0.0, 0.0)
      v2 = Simulation::Vector3.new(3.0, 4.0, 0.0)
      v1.distance_to(v2).should eq(5.0)
    end

    it "calculates dot product" do
      v1 = Simulation::Vector3.new(1.0, 0.0, 0.0)
      v2 = Simulation::Vector3.new(0.0, 1.0, 0.0)
      v1.dot(v2).should eq(0.0)
    end

    it "calculates cross product" do
      v1 = Simulation::Vector3.new(1.0, 0.0, 0.0)
      v2 = Simulation::Vector3.new(0.0, 1.0, 0.0)
      cross = v1.cross(v2)
      cross.z.should eq(1.0)
    end
  end

  describe Simulation::Quaternion do
    it "creates identity quaternion" do
      q = Simulation::Quaternion.identity
      q.w.should eq(1.0)
      q.x.should eq(0.0)
    end

    it "creates quaternion from euler angles" do
      q = Simulation::Quaternion.from_euler(0.0, 0.0, Math::PI/2)
      q.w.should be_close(0.7071, 0.001)
      q.z.should be_close(0.7071, 0.001)
    end

    it "rotates a vector" do
      q = Simulation::Quaternion.from_axis_angle(Simulation::Vector3.up, Math::PI/2)
      v = Simulation::Vector3.new(1.0, 0.0, 0.0)
      rotated = q.rotate(v)
      rotated.x.should be_close(0.0, 0.001)
      rotated.z.should be_close(-1.0, 0.001)
    end
  end

  describe Simulation::Transform do
    it "creates identity transform" do
      t = Simulation::Transform.identity
      t.position.should eq(Simulation::Vector3.zero)
    end

    it "translates position" do
      t = Simulation::Transform.new
      t.translate(Simulation::Vector3.new(1.0, 2.0, 3.0))
      t.position.x.should eq(1.0)
      t.position.y.should eq(2.0)
    end
  end

  describe Simulation::TimeManager do
    it "initializes with zero time" do
      tm = Simulation::TimeManager.new
      tm.current_time.should eq(0.0)
    end

    it "advances time" do
      tm = Simulation::TimeManager.new
      tm.advance(0.1)
      tm.current_time.should eq(0.1)
    end

    it "pauses and resumes" do
      tm = Simulation::TimeManager.new
      tm.advance(0.1)
      tm.pause
      tm.advance(0.1)
      tm.current_time.should eq(0.1)  # Should not advance while paused
      tm.resume
      tm.advance(0.1)
      tm.current_time.should eq(0.2)
    end

    it "applies time scale" do
      tm = Simulation::TimeManager.new
      tm.max_delta_time = 1.0  # Allow larger time steps for this test
      tm.set_time_scale(2.0)
      tm.advance(0.1)
      tm.current_time.should eq(0.2)
    end

    it "formats time correctly" do
      tm = Simulation::TimeManager.new
      tm.max_delta_time = 100.0  # Allow large time steps for this test
      tm.advance(65.5)
      tm.format_time.should eq("01:05.50")
    end
  end

  describe Simulation::LocalEnvironment do
    it "creates environment with name" do
      env = Simulation::LocalEnvironment.new("test_world")
      env.name.should eq("test_world")
    end

    it "steps simulation" do
      env = Simulation::LocalEnvironment.new
      env.step(0.1)
      env.current_time.should eq(0.1)
    end

    it "adds and removes agents" do
      env = Simulation::LocalEnvironment.new
      agent = Simulation::Agent.new("robot1")
      env.add_agent(agent)
      env.agents.size.should eq(1)
      env.remove_agent(agent).should be_true
      env.agents.size.should eq(0)
    end
  end

  describe Simulation::Agent do
    it "creates agent with name" do
      agent = Simulation::Agent.new("test_agent")
      agent.name.should eq("test_agent")
      agent.state.should eq(Simulation::AgentState::Idle)
    end

    it "sets and clears goals" do
      agent = Simulation::Agent.new("test_agent")
      agent.set_goal(Simulation::Vector3.new(10.0, 0.0, 0.0))
      agent.current_goal.should_not be_nil
      agent.state.should eq(Simulation::AgentState::Moving)
      agent.clear_goal
      agent.current_goal.should be_nil
      agent.state.should eq(Simulation::AgentState::Idle)
    end

    it "moves towards goal" do
      env = Simulation::LocalEnvironment.new
      agent = Simulation::Agent.new("test_agent", env)
      env.add_agent(agent)  # Must add agent to environment
      agent.max_speed = 1.0
      agent.set_goal(Simulation::Vector3.new(1.0, 0.0, 0.0))
      
      10.times { env.step(0.1) }
      
      # Should have moved towards goal
      agent.position.x.should be > 0.0
    end

    it "adds sensors" do
      agent = Simulation::Agent.new("test_agent")
      sensor = Simulation::PositionSensor.new
      agent.add_sensor(sensor)
      agent.sensors.size.should eq(1)
    end

    it "adds actuators" do
      agent = Simulation::Agent.new("test_agent")
      actuator = Simulation::MovementActuator.new
      agent.add_actuator(actuator)
      agent.actuators.size.should eq(1)
    end

    it "converts to atomspace" do
      agent = Simulation::Agent.new("test_agent")
      agent.position = Simulation::Vector3.new(1.0, 2.0, 3.0)
      
      atomspace = AtomSpace::AtomSpace.new
      node = agent.to_atomspace(atomspace)
      
      node.should be_a(AtomSpace::Atom)
      atomspace.size.should be > 0
    end
  end

  describe Simulation::PositionSensor do
    it "reads agent position" do
      agent = Simulation::Agent.new("test_agent")
      agent.position = Simulation::Vector3.new(1.0, 2.0, 3.0)
      
      sensor = Simulation::PositionSensor.new
      agent.add_sensor(sensor)
      sensor.update(0.1)
      
      value = sensor.value.as(Array(Float64))
      value[0].should eq(1.0)
      value[1].should eq(2.0)
      value[2].should eq(3.0)
    end
  end

  describe Simulation::VelocitySensor do
    it "reads agent velocity" do
      agent = Simulation::Agent.new("test_agent")
      agent.velocity = Simulation::Vector3.new(3.0, 4.0, 0.0)
      
      sensor = Simulation::VelocitySensor.new
      agent.add_sensor(sensor)
      sensor.update(0.1)
      
      sensor.value.as(Float64).should eq(5.0)
    end
  end

  describe Simulation::RangeSensor do
    it "detects entities in range" do
      env = Simulation::LocalEnvironment.new
      
      agent = Simulation::Agent.new("sensor_agent", env)
      agent.position = Simulation::Vector3.zero
      env.add_agent(agent)
      
      target = Simulation::Agent.new("target", env)
      target.position = Simulation::Vector3.new(5.0, 0.0, 0.0)
      env.add_agent(target)
      
      sensor = Simulation::RangeSensor.new(range: 10.0)
      agent.add_sensor(sensor)
      sensor.update(0.1)
      
      sensor.value.as(Float64).should be < 10.0
    end
  end

  describe Simulation::MovementActuator do
    it "can execute movement actions" do
      actuator = Simulation::MovementActuator.new
      actuator.can_execute?("move_forward").should be_true
      actuator.can_execute?("stop").should be_true
      actuator.can_execute?("fly").should be_false
    end

    it "executes move_forward" do
      agent = Simulation::Agent.new("test_agent")
      actuator = Simulation::MovementActuator.new(max_speed: 5.0)
      agent.add_actuator(actuator)
      
      actuator.execute("move_forward", {} of String => Float64)
      agent.velocity.magnitude.should eq(5.0)
    end

    it "executes stop" do
      agent = Simulation::Agent.new("test_agent")
      agent.velocity = Simulation::Vector3.new(5.0, 0.0, 0.0)
      actuator = Simulation::MovementActuator.new
      agent.add_actuator(actuator)
      
      actuator.execute("stop", {} of String => Float64)
      agent.velocity.magnitude.should eq(0.0)
    end
  end

  describe Simulation::RotationActuator do
    it "can execute rotation actions" do
      actuator = Simulation::RotationActuator.new
      actuator.can_execute?("turn_left").should be_true
      actuator.can_execute?("look_at").should be_true
    end
  end

  describe Simulation::PhysicsBody do
    it "creates with default values" do
      body = Simulation::PhysicsBody.new
      body.position.should eq(Simulation::Vector3.zero)
      body.mass.should eq(1.0)
    end

    it "applies force" do
      body = Simulation::PhysicsBody.new
      body.add_force(Simulation::Vector3.new(10.0, 0.0, 0.0))
      body.integrate(0.1, Simulation::Vector3.zero)
      body.velocity.x.should be > 0.0
    end

    it "applies gravity" do
      body = Simulation::PhysicsBody.new
      gravity = Simulation::Vector3.new(0.0, -9.81, 0.0)
      body.integrate(0.1, gravity)
      body.velocity.y.should be < 0.0
    end

    it "applies impulse" do
      body = Simulation::PhysicsBody.new
      body.add_impulse(Simulation::Vector3.new(5.0, 0.0, 0.0))
      body.velocity.x.should eq(5.0)
    end
  end

  describe Simulation::SphereCollider do
    it "detects point inside" do
      collider = Simulation::SphereCollider.new(radius: 1.0)
      collider.contains_point?(Simulation::Vector3.new(0.5, 0.0, 0.0)).should be_true
      collider.contains_point?(Simulation::Vector3.new(2.0, 0.0, 0.0)).should be_false
    end

    it "detects sphere intersection" do
      c1 = Simulation::SphereCollider.new(radius: 1.0, center: Simulation::Vector3.zero)
      c2 = Simulation::SphereCollider.new(radius: 1.0, center: Simulation::Vector3.new(1.5, 0.0, 0.0))
      c1.intersects?(c2).should be_true
      
      c3 = Simulation::SphereCollider.new(radius: 1.0, center: Simulation::Vector3.new(5.0, 0.0, 0.0))
      c1.intersects?(c3).should be_false
    end
  end

  describe Simulation::BoxCollider do
    it "detects point inside" do
      collider = Simulation::BoxCollider.new(size: Simulation::Vector3.one)
      collider.contains_point?(Simulation::Vector3.zero).should be_true
      collider.contains_point?(Simulation::Vector3.new(2.0, 0.0, 0.0)).should be_false
    end
  end

  describe Simulation::AgentGroup do
    it "manages group of agents" do
      group = Simulation::AgentGroup.new("team")
      
      agent1 = Simulation::Agent.new("agent1")
      agent2 = Simulation::Agent.new("agent2")
      
      group.add(agent1)
      group.add(agent2)
      
      group.size.should eq(2)
    end

    it "calculates center of mass" do
      group = Simulation::AgentGroup.new("team")
      
      agent1 = Simulation::Agent.new("agent1")
      agent1.position = Simulation::Vector3.new(-1.0, 0.0, 0.0)
      
      agent2 = Simulation::Agent.new("agent2")
      agent2.position = Simulation::Vector3.new(1.0, 0.0, 0.0)
      
      group.add(agent1)
      group.add(agent2)
      
      center = group.center_of_mass
      center.x.should eq(0.0)
    end
  end

  describe Simulation::UnityBridge do
    it "creates unity bridge" do
      bridge = Simulation::UnityBridge.new("localhost", 8080)
      bridge.name.should eq("unity")
      bridge.connected?.should be_false
    end
  end

  describe Simulation::GazeboBridge do
    it "creates gazebo bridge" do
      bridge = Simulation::GazeboBridge.new
      bridge.name.should eq("gazebo")
      bridge.connected?.should be_false
    end
  end

  describe "Simulation module functions" do
    it "creates local environment" do
      env = Simulation.create_local_environment("test")
      env.should be_a(Simulation::LocalEnvironment)
      env.name.should eq("test")
    end

    it "creates agent" do
      env = Simulation.create_local_environment
      agent = Simulation.create_agent("robot", env, Simulation::Vector3.new(1.0, 2.0, 3.0))
      agent.name.should eq("robot")
      agent.position.x.should eq(1.0)
    end

    it "runs simulation" do
      env = Simulation.create_local_environment
      agent = Simulation.create_agent("robot", env)
      env.add_agent(agent)
      
      Simulation.run(env, 1.0, 0.1)
      env.current_time.should be_close(1.0, 0.01)
    end

    it "exports state to atomspace" do
      env = Simulation.create_local_environment("world")
      agent = Simulation.create_agent("robot", env)
      env.add_agent(agent)
      
      atomspace = AtomSpace::AtomSpace.new
      node = Simulation.state_to_atomspace(env, atomspace)
      
      atomspace.size.should be > 0
    end
  end
end
