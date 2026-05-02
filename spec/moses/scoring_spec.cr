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

describe Moses::BooleanTableScoring do
  describe "initialization" do
    it "creates with matching training and target data" do
      training = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
      target = [0.0, 1.0, 1.0, 0.0]
      scorer = Moses::BooleanTableScoring.new(training, target)
      scorer.should_not be_nil
    end

    it "raises on mismatched data sizes" do
      training = [[0.0, 0.0], [0.0, 1.0]]
      target = [0.0]
      expect_raises(Moses::ScoringException) do
        Moses::BooleanTableScoring.new(training, target)
      end
    end

    it "has correct problem type" do
      training = [[0.0]]
      target = [0.0]
      scorer = Moses::BooleanTableScoring.new(training, target)
      scorer.problem_type.should eq(Moses::ProblemType::BooleanClassification)
    end
  end

  describe "evaluate" do
    it "returns a CompositeScore" do
      training = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
      target = [0.0, 1.0, 1.0, 0.0]
      scorer = Moses::BooleanTableScoring.new(training, target)

      candidate = Moses::Candidate.new("$0 or $1")
      result = scorer.evaluate(candidate)

      result.should be_a(Moses::CompositeScore)
    end

    it "score is in range [-1, 0] for boolean problems" do
      training = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
      target = [0.0, 1.0, 1.0, 1.0]
      scorer = Moses::BooleanTableScoring.new(training, target)

      candidate = Moses::Candidate.new("$0 or $1")
      result = scorer.evaluate(candidate)

      result.score.should be >= -1.0
      result.score.should be <= 0.0
    end

    it "sets candidate score after calling score method" do
      training = [[0.0, 0.0], [1.0, 1.0]]
      target = [0.0, 1.0]
      scorer = Moses::BooleanTableScoring.new(training, target)

      candidate = Moses::Candidate.new("$0")
      scorer.score(candidate)

      candidate.scored?.should be_true
    end

    it "increments evaluations counter" do
      training = [[0.0, 0.0], [1.0, 1.0]]
      target = [0.0, 1.0]
      scorer = Moses::BooleanTableScoring.new(training, target)

      scorer.evaluations.should eq(0)
      scorer.score(Moses::Candidate.new("$0"))
      scorer.evaluations.should eq(1)
    end
  end
end

describe Moses::RegressionScoring do
  describe "initialization" do
    it "creates with matching training and target data" do
      training = [[0.0], [1.0], [2.0]]
      target = [0.0, 1.0, 4.0]
      scorer = Moses::RegressionScoring.new(training, target)
      scorer.should_not be_nil
    end

    it "raises on mismatched data sizes" do
      training = [[0.0], [1.0]]
      target = [0.0]
      expect_raises(Moses::ScoringException) do
        Moses::RegressionScoring.new(training, target)
      end
    end

    it "has correct problem type" do
      training = [[0.0]]
      target = [0.0]
      scorer = Moses::RegressionScoring.new(training, target)
      scorer.problem_type.should eq(Moses::ProblemType::Regression)
    end
  end

  describe "evaluate" do
    it "returns a CompositeScore" do
      training = [[1.0], [2.0], [3.0]]
      target = [1.0, 2.0, 3.0]
      scorer = Moses::RegressionScoring.new(training, target)

      candidate = Moses::Candidate.new("$0")
      result = scorer.evaluate(candidate)

      result.should be_a(Moses::CompositeScore)
    end

    it "perfect predictor has score near 0 (MSE=0)" do
      training = [[1.0], [2.0], [3.0]]
      target = [1.0, 2.0, 3.0]
      scorer = Moses::RegressionScoring.new(training, target)

      candidate = Moses::Candidate.new("$0")
      result = scorer.evaluate(candidate)

      # -MSE where MSE=0 -> score = 0.0
      result.score.should be_close(0.0, 0.001)
    end

    it "score is negative for non-perfect predictions" do
      training = [[1.0], [2.0], [3.0]]
      target = [10.0, 20.0, 30.0]
      scorer = Moses::RegressionScoring.new(training, target)

      candidate = Moses::Candidate.new("$0")
      result = scorer.evaluate(candidate)

      # MSE is high -> score is very negative
      result.score.should be < 0.0
    end

    it "increments evaluations counter" do
      training = [[1.0], [2.0]]
      target = [1.0, 2.0]
      scorer = Moses::RegressionScoring.new(training, target)

      scorer.evaluations.should eq(0)
      scorer.score(Moses::Candidate.new("$0"))
      scorer.evaluations.should eq(1)
    end
  end
end

describe Moses::ClusteringScoring do
  describe "initialization" do
    it "creates with training data" do
      training = [[1.0, 2.0], [1.1, 2.1], [5.0, 6.0]]
      scorer = Moses::ClusteringScoring.new(training)
      scorer.should_not be_nil
    end

    it "has correct problem type" do
      scorer = Moses::ClusteringScoring.new([[1.0, 2.0]])
      scorer.problem_type.should eq(Moses::ProblemType::Clustering)
    end
  end

  describe "evaluate" do
    it "returns a CompositeScore" do
      training = [[1.0, 2.0], [1.1, 2.1], [5.0, 6.0], [5.1, 6.1]]
      scorer = Moses::ClusteringScoring.new(training)

      candidate = Moses::Candidate.new("2")
      result = scorer.evaluate(candidate)

      result.should be_a(Moses::CompositeScore)
    end

    it "returns poor score for insufficient data" do
      training = [[1.0, 2.0]]
      scorer = Moses::ClusteringScoring.new(training)

      candidate = Moses::Candidate.new("2")
      result = scorer.evaluate(candidate)

      result.score.should be < 0.0
    end
  end
end
