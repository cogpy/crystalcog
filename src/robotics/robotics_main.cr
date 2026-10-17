# Main Robotics module loader for CrystalCog

require "./spatial_reasoning"
require "./navigation"
require "./sensory_motor_control"
require "./goal_planning"
require "./ros_integration"

module Robotics
  # VERSION is defined in ros_integration.cr

  # Initialize Robotics subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Robotics subsystem...")
    CogUtil::Logger.info("Robotics subsystem initialized successfully")
  end
end
