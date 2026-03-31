# Main Robotics module loader for CrystalCog

require "./spatial_reasoning"
require "./navigation"
require "./sensory_motor"
require "./goal_planning"

module Robotics
  VERSION = "0.1.0"

  # Initialize Robotics subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Robotics subsystem...")
    CogUtil::Logger.info("Robotics subsystem initialized successfully")
  end
end
