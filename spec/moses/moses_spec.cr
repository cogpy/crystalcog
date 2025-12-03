require "spec"
require "../../src/moses/moses_framework"

describe MOSES::Optimizer do
  describe "initialization" do
    it "creates MOSES optimizer" do
      optimizer = MOSES::Optimizer.new
      optimizer.should_not be_nil
    end

    it "has default parameters" do
      optimizer = MOSES::Optimizer.new
      optimizer.max_evals.should eq(10000)
      optimizer.population_size.should eq(1000)
    end
  end

  describe "optimization" do
    it "performs optimization" do
      optimizer = MOSES::Optimizer.new

      # Simple test function
      scorer = MOSES::TestScorer.new

      result = optimizer.optimize(scorer)
      result.should_not be_nil
    end
  end
end

describe MOSES::TestScorer do
  describe "scoring" do
    it "provides score function" do
      scorer = MOSES::TestScorer.new

      # Test with simple program
      program = MOSES::Program.new("x")
      score = scorer.score(program)

      score.should be_a(Float64)
    end
  end
end
