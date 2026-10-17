# Main Multi-Agent module loader for CrystalCog

require "./communication"
require "./coordination"
require "../multiagent/coordination"

module MultiAgent
  # VERSION is defined in ../multiagent/coordination.cr

  # Initialize Multi-Agent subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing MultiAgent subsystem...")
    CogUtil::Logger.info("MultiAgent subsystem initialized successfully")
  end
end
