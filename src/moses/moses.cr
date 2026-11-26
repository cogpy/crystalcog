# MOSES (Meta-Optimizing Semantic Evolutionary Search) module
# Crystal implementation of the MOSES evolutionary program learning system
#
# MOSES is an evolutionary program learner that uses genetic programming
# techniques to evolve programs that fit given datasets or solve problems.

require "../cogutil/cogutil"
require "../atomspace/atomspace_core"
require "./types"
require "./scoring"
require "./representation"
require "./deme"
require "./metapopulation"
require "./optimization"

module Moses
  VERSION = "0.1.0"

  # Initialize the MOSES subsystem
  def self.initialize
    CogUtil::Logger.info("MOSES #{VERSION} initializing")

    # Initialize dependencies
    CogUtil.initialize
    AtomSpace.initialize

    CogUtil::Logger.info("MOSES #{VERSION} initialized")
  end

  # Main MOSES evolutionary search function
  # This is the primary entry point for running MOSES optimization
  def self.run_moses(params : MosesParams) : MosesResult
    CogUtil::Logger.info("Starting MOSES evolutionary search")

    # Create metapopulation and scoring function
    metapop = MetaPopulation.new(params)
    scoring_func = create_scoring_function(params)

    # Run the main evolutionary loop
    best_candidates = metapop.run(scoring_func, params.max_evals)

    # Return results
    MosesResult.new(
      candidates: best_candidates,
      evaluations: metapop.total_evals,
      generations: metapop.generations
    )
  end

  # Create a scoring function based on the problem type
  private def self.create_scoring_function(params : MosesParams) : ScoringFunction
    case params.problem_type
    when ProblemType::BooleanClassification
      target_data = params.target_data || (raise Moses::MosesException.new("Boolean classification requires target data"))
      BooleanTableScoring.new(params.training_data, target_data)
    when ProblemType::Regression
      target_data = params.target_data || (raise Moses::MosesException.new("Regression requires target data"))
      RegressionScoring.new(params.training_data, target_data)
    when ProblemType::Clustering
      ClusteringScoring.new(params.training_data)
    else
      raise Moses::MosesException.new("Unsupported problem type: #{params.problem_type}")
    end
  end

  # Exception classes for MOSES
  class MosesException < CogUtil::OpenCogException
  end

  class EvolutionException < MosesException
  end

  class ScoringException < MosesException
  end

  class RepresentationException < MosesException
  end
end
