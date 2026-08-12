# Main Learning module loader for CrystalCog

require "./concept_learning"
require "./generalization"
require "./advanced_learning"

module Learning
  VERSION = "0.1.0"

  # Initialize Learning subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Learning subsystem...")
    CogUtil::Logger.info("Learning subsystem initialized successfully")
  end

  # Convenience constructors for advanced learners
  def self.supervised_learner : Advanced::SupervisedLearner
    Advanced::SupervisedLearner.new
  end

  def self.reinforcement_learner(lr : Float64 = 0.1, discount : Float64 = 0.9, epsilon : Float64 = 0.1) : Advanced::ReinforcementLearner
    Advanced::ReinforcementLearner.new(lr, discount, epsilon)
  end

  def self.online_learner(window_size : Int32 = 100) : Advanced::OnlineLearner
    Advanced::OnlineLearner.new(window_size)
  end

  def self.curriculum_learner : Advanced::CurriculumLearner
    Advanced::CurriculumLearner.new
  end
end
