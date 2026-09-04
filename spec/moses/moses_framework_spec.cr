require "spec"
require "../../src/moses/moses_framework"

describe MOSES do
  describe "framework" do
    it "reports framework info" do
      info = MOSES.info
      info["language"].should eq("Crystal")
      info["version"].should eq(Moses::VERSION)
    end

    it "creates an optimizer with default parameters" do
      optimizer = MOSES.create_optimizer
      optimizer.should be_a(MOSES::Optimizer)
    end

    it "builds boolean classification params" do
      params = MOSES.boolean_params(
        [[0.0, 0.0], [1.0, 1.0]],
        [0.0, 1.0],
        max_evals: 100
      )
      params.problem_type.should eq(Moses::ProblemType::BooleanClassification)
      params.max_evals.should eq(100)
    end

    it "builds regression params" do
      params = MOSES.regression_params(
        [[0.0], [1.0]],
        [0.0, 2.0],
        max_evals: 50
      )
      params.problem_type.should eq(Moses::ProblemType::Regression)
      params.max_evals.should eq(50)
    end

    it "creates a scoring function for boolean classification" do
      scorer = MOSES.create_scorer(
        Moses::ProblemType::BooleanClassification,
        [[0.0, 0.0], [1.0, 1.0]],
        [0.0, 1.0]
      )
      scorer.should be_a(Moses::ScoringFunction)
    end
  end

  describe "test compatibility classes" do
    it "supports genetic operations on programs" do
      p1 = MOSES::Program.new("a")
      p2 = MOSES::Program.new("b")
      child = MOSES::GeneticOperations.crossover(p1, p2)
      child.expression.should eq("a_b")

      mutant = MOSES::GeneticOperations.mutate(p1)
      mutant.expression.should eq("a_mut")
    end

    it "selects the fittest individual via tournament" do
      pop = MOSES::Population.new
      pop.add(MOSES::Individual.new(MOSES::Program.new("p1"), 0.5))
      pop.add(MOSES::Individual.new(MOSES::Program.new("p2"), 0.9))
      pop.size.should eq(2)

      winner = MOSES::Selection.tournament(pop, 2)
      winner.fitness.should eq(0.9)
    end
  end
end
