require "spec"
require "../../src/moses/moses_framework"

describe MOSES::Scoring do
  describe "scorer interface" do
    it "defines Scorer interface" do
      MOSES::Scorer.should be_truthy
    end

    it "defines TestScorer" do
      MOSES::TestScorer.should be_truthy
    end

    it "creates test scorer" do
      scorer = MOSES::TestScorer.new
      scorer.should_not be_nil
    end
  end

  describe "scoring functionality" do
    it "scores programs" do
      scorer = MOSES::TestScorer.new
      program = MOSES::Program.new("x")

      score = scorer.score(program)
      score.should be_a(Float64)
    end

    it "provides fitness evaluation" do
      scorer = MOSES::TestScorer.new

      # Should respond to fitness methods
      scorer.responds_to?(:evaluate).should be_true
    end
  end

  describe "scoring types" do
    it "supports regression scoring" do
      MOSES::RegressionScorer.should be_truthy
    end

    it "supports classification scoring" do
      MOSES::ClassificationScorer.should be_truthy
    end
  end
end
