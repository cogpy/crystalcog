# Main Multi-Agent module loader for CrystalCog

require "./communication"
require "./coordination"

module MultiAgent
  VERSION = "0.1.0"

  # Initialize Multi-Agent subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing MultiAgent subsystem...")
    CogUtil::Logger.info("MultiAgent subsystem initialized successfully")
  end
end
