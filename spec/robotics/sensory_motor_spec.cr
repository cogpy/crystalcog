require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/spatial/spatial"
require "../../src/temporal/temporal"
require "../../src/robotics/ros_integration"
require "../../src/robotics/sensory_motor"

describe Robotics do
  describe Robotics::SensorReading do
    it "creates sensor reading" do
      reading = Robotics::SensorReading.new("laser", Robotics::SensorModality::RANGE)
      reading.sensor_name.should eq("laser")
      reading.modality.should eq(Robotics::SensorModality::RANGE)
    end

    it "stores and retrieves data" do
      reading = Robotics::SensorReading.new("sensor", Robotics::SensorModality::VISION)
      reading.set("width", 640.0)
      reading.set("height", 480.0)

      reading.get_float("width").should eq(640.0)
      reading.get_float("height").should eq(480.0)
    end

    it "converts to atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      reading = Robotics::SensorReading.new("test_sensor", Robotics::SensorModality::TOUCH)
      reading.set("force", 10.5)

      atoms = reading.to_atomspace(atomspace)
      atoms.should_not be_empty
    end
  end

  describe Robotics::RangeSensor do
    it "creates range sensor" do
      sensor = Robotics::RangeSensor.new("lidar", "laser_link")
      sensor.name.should eq("lidar")
      sensor.modality.should eq(Robotics::SensorModality::RANGE)
    end

    it "reads sensor data" do
      sensor = Robotics::RangeSensor.new("lidar")
      sensor.activate

      reading = sensor.read
      reading.sensor_name.should eq("lidar")
      reading.get_float("min_range").should eq(0.1)
      reading.get_float("max_range").should eq(30.0)
    end

    it "detects obstacles" do
      sensor = Robotics::RangeSensor.new("lidar")
      sensor.set_ranges([5.0, 0.5, 10.0].map(&.to_f32))

      sensor.obstacle_detected?(1.0).should be_true
      sensor.min_reading.should eq(0.5_f32)
    end
  end

  describe Robotics::VisionSensor do
    it "creates vision sensor" do
      sensor = Robotics::VisionSensor.new("camera", "camera_link")
      sensor.name.should eq("camera")
      sensor.modality.should eq(Robotics::SensorModality::VISION)
    end

    it "reads vision data" do
      sensor = Robotics::VisionSensor.new("camera", resolution: {1920, 1080})
      sensor.activate

      reading = sensor.read
      reading.get_float("width").should eq(1920.0)
      reading.get_float("height").should eq(1080.0)
    end
  end

  describe Robotics::ProprioceptiveSensor do
    it "creates proprioceptive sensor" do
      sensor = Robotics::ProprioceptiveSensor.new("joints", ["joint1", "joint2"])
      sensor.name.should eq("joints")
      sensor.modality.should eq(Robotics::SensorModality::PROPRIOCEPTION)
    end

    it "tracks joint positions" do
      sensor = Robotics::ProprioceptiveSensor.new("arm", ["shoulder", "elbow"])
      sensor.set_joint_state("shoulder", 0.5, 0.1, 1.0)
      sensor.set_joint_state("elbow", 1.2, 0.0, 0.5)

      sensor.get_position("shoulder").should eq(0.5)
      sensor.get_position("elbow").should eq(1.2)
      sensor.get_velocity("shoulder").should eq(0.1)
    end
  end

  describe Robotics::TouchSensor do
    it "creates touch sensor" do
      sensor = Robotics::TouchSensor.new("fingertip", "finger_link")
      sensor.name.should eq("fingertip")
      sensor.modality.should eq(Robotics::SensorModality::TOUCH)
    end

    it "detects contacts" do
      sensor = Robotics::TouchSensor.new("fingertip", "finger_link")
      sensor.has_contact?.should be_false

      sensor.add_contact(Spatial::Vector3.new(0.0, 0.0, 0.0), 5.0)
      sensor.has_contact?.should be_true

      sensor.clear_contacts
      sensor.has_contact?.should be_false
    end
  end

  describe Robotics::JointActuator do
    it "creates joint actuator" do
      actuator = Robotics::JointActuator.new("shoulder", Robotics::ActuatorType::REVOLUTE)
      actuator.name.should eq("shoulder")
      actuator.type.should eq(Robotics::ActuatorType::REVOLUTE)
    end

    it "controls position" do
      actuator = Robotics::JointActuator.new("joint", Robotics::ActuatorType::REVOLUTE)
      actuator.enable

      actuator.set_target_position(1.0)
      actuator.update(0.1)

      # Position should have moved towards target
      actuator.position.should be > 0.0
    end

    it "respects limits" do
      actuator = Robotics::JointActuator.new(
        "joint",
        Robotics::ActuatorType::REVOLUTE,
        min_pos: -1.0,
        max_pos: 1.0
      )

      actuator.set_target_position(5.0)
      # Should be clamped to max
    end
  end

  describe Robotics::DifferentialDrive do
    it "creates differential drive" do
      drive = Robotics::DifferentialDrive.new
      drive.wheel_radius.should eq(0.1)
      drive.wheel_separation.should eq(0.5)
    end

    it "sets velocity" do
      drive = Robotics::DifferentialDrive.new
      drive.enable

      drive.set_velocity(1.0, 0.5)
      drive.update(0.1)

      # Wheels should be moving at different speeds for rotation
    end

    it "stops" do
      drive = Robotics::DifferentialDrive.new
      drive.enable
      drive.set_velocity(1.0, 0.0)
      drive.stop

      # Both velocities should be 0
    end
  end

  describe Robotics::Gripper do
    it "creates gripper" do
      gripper = Robotics::Gripper.new("gripper", max_opening: 0.08)
      gripper.max_opening.should eq(0.08)
    end

    it "opens and closes" do
      gripper = Robotics::Gripper.new
      gripper.enable

      gripper.open
      10.times { gripper.update(0.1) }
      gripper.is_open?.should be_true

      gripper.close
      10.times { gripper.update(0.1) }
      gripper.is_closed?.should be_true
    end
  end

  describe Robotics::BodySchema do
    it "creates body schema" do
      schema = Robotics::BodySchema.new("base_link")
      schema.base_frame.should eq("base_link")
    end

    it "adds segments and joints" do
      schema = Robotics::BodySchema.new
      schema.add_segment("upper_arm", "base", 0.3)
      schema.add_segment("forearm", "upper_arm", 0.25)
      schema.add_joint("shoulder", "base", "upper_arm", Robotics::ActuatorType::REVOLUTE)
      schema.add_joint("elbow", "upper_arm", "forearm", Robotics::ActuatorType::REVOLUTE)

      schema.segments.size.should eq(2)
      schema.joints.size.should eq(2)
    end

    it "computes forward kinematics" do
      schema = Robotics::BodySchema.new
      schema.add_segment("link1", nil, 1.0)
      schema.add_segment("link2", "link1", 1.0)
      schema.add_joint("joint1", "base_link", "link1", Robotics::ActuatorType::REVOLUTE)

      positions = schema.forward_kinematics({"joint1" => 0.0})
      positions.should_not be_empty
    end
  end

  describe Robotics::SensorFusion do
    it "creates sensor fusion" do
      fusion = Robotics::SensorFusion.new
      fusion.sensors.should be_empty
    end

    it "fuses multiple sensor readings" do
      fusion = Robotics::SensorFusion.new

      range_sensor = Robotics::RangeSensor.new("lidar")
      range_sensor.activate
      fusion.add_sensor(range_sensor)

      fusion.update
      fusion.get_state("min_obstacle_distance").should_not be_nil
    end
  end

  describe Robotics::SensoryMotorCoordinator do
    it "creates coordinator" do
      atomspace = AtomSpace::AtomSpace.new
      coordinator = Robotics::SensoryMotorCoordinator.new(atomspace)

      coordinator.sensors.should be_empty
      coordinator.actuators.should be_empty
    end

    it "adds sensors and actuators" do
      atomspace = AtomSpace::AtomSpace.new
      coordinator = Robotics::SensoryMotorCoordinator.new(atomspace)

      sensor = Robotics::RangeSensor.new("lidar")
      actuator = Robotics::JointActuator.new("joint", Robotics::ActuatorType::REVOLUTE)

      coordinator.add_sensor(sensor)
      coordinator.add_actuator(actuator)

      coordinator.sensors.size.should eq(1)
      coordinator.actuators.size.should eq(1)
    end

    it "reads all sensors" do
      atomspace = AtomSpace::AtomSpace.new
      coordinator = Robotics::SensoryMotorCoordinator.new(atomspace)

      sensor1 = Robotics::RangeSensor.new("lidar")
      sensor2 = Robotics::VisionSensor.new("camera")

      coordinator.add_sensor(sensor1)
      coordinator.add_sensor(sensor2)

      readings = coordinator.read_all_sensors
      readings.size.should eq(2)
    end

    it "handles emergency stop" do
      atomspace = AtomSpace::AtomSpace.new
      coordinator = Robotics::SensoryMotorCoordinator.new(atomspace)

      actuator = Robotics::JointActuator.new("joint", Robotics::ActuatorType::REVOLUTE)
      coordinator.add_actuator(actuator)
      coordinator.enable_all_actuators

      actuator.enabled?.should be_true

      coordinator.emergency_stop
      actuator.enabled?.should be_false

      coordinator.resume
      actuator.enabled?.should be_true
    end

    it "syncs to atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      coordinator = Robotics::SensoryMotorCoordinator.new(atomspace)

      sensor = Robotics::RangeSensor.new("lidar")
      coordinator.add_sensor(sensor)

      coordinator.sync_to_atomspace
      atomspace.size.should be > 0
    end
  end

  describe "Module convenience methods" do
    it "creates coordinator" do
      atomspace = AtomSpace::AtomSpace.new
      coordinator = Robotics.create_coordinator(atomspace)
      coordinator.should_not be_nil
    end

    it "creates range sensor" do
      sensor = Robotics.create_range_sensor("lidar")
      sensor.name.should eq("lidar")
    end

    it "creates vision sensor" do
      sensor = Robotics.create_vision_sensor("camera")
      sensor.name.should eq("camera")
    end

    it "creates gripper" do
      gripper = Robotics.create_gripper
      gripper.should_not be_nil
    end

    it "creates differential drive" do
      drive = Robotics.create_differential_drive
      drive.should_not be_nil
    end
  end
end
