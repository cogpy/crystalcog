# Main Learning module loader for CrystalCog

require "./concept_learning"
require "./generalization"

module Learning
  VERSION = "0.1.0"

  # Initialize Learning subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Learning subsystem...")
    CogUtil::Logger.info("Learning subsystem initialized successfully")
  end
end
