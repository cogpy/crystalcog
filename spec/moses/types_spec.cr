require "spec"
require "../../src/moses/moses_framework"

describe MOSES::Types do
  describe "basic types" do
    it "defines Program type" do
      MOSES::Program.should be_truthy
    end

    it "defines Individual type" do
      MOSES::Individual.should be_truthy
    end

    it "defines Population type" do
      MOSES::Population.should be_truthy
    end

    it "creates program" do
      program = MOSES::Program.new("x")
      program.should_not be_nil
      program.expression.should eq("x")
    end

    it "creates individual" do
      program = MOSES::Program.new("x")
      individual = MOSES::Individual.new(program, 0.5)

      individual.should_not be_nil
      individual.program.should eq(program)
      individual.fitness.should eq(0.5)
    end
  end

  describe "population operations" do
    it "creates population" do
      population = MOSES::Population.new
      population.should_not be_nil
      population.individuals.should be_empty
    end

    it "adds individuals to population" do
      population = MOSES::Population.new
      program = MOSES::Program.new("x")
      individual = MOSES::Individual.new(program, 0.5)

      population.add(individual)
      population.size.should eq(1)
      population.individuals.first.should eq(individual)
    end
  end
end

describe Moses::CompositeScore do
  describe "creation" do
    it "creates with score and complexity" do
      cs = Moses::CompositeScore.new(-0.5, 3)
      cs.score.should eq(-0.5)
      cs.complexity.should eq(3)
      cs.penalized_score.should eq(-0.5)
    end

    it "applies complexity and uniformity penalties" do
      cs = Moses::CompositeScore.new(-0.5, 3, 0.1, 0.05)
      cs.penalized_score.should be_close(-0.65, 0.001)
    end

    it "converts to string" do
      cs = Moses::CompositeScore.new(-0.5, 3)
      result = cs.to_s
      result.should contain("CompositeScore")
      result.should contain("score=")
    end
  end

  describe "comparison" do
    it "compares by penalized_score" do
      cs1 = Moses::CompositeScore.new(-0.3, 2)
      cs2 = Moses::CompositeScore.new(-0.7, 2)

      (cs1 > cs2).should be_true
      (cs2 < cs1).should be_true
    end

    it "equal penalized scores compare as equal" do
      cs1 = Moses::CompositeScore.new(-0.5, 2)
      cs2 = Moses::CompositeScore.new(-0.5, 5)

      (cs1 <=> cs2).should eq(0)
    end
  end
end

describe Moses::TerminationCriteria do
  describe "should_terminate?" do
    it "terminates when max_evals reached" do
      tc = Moses::TerminationCriteria.new(100, 50)
      tc.should_terminate?(100, 0, -1.0, 0).should be_true
      tc.should_terminate?(99, 0, -1.0, 0).should be_false
    end

    it "terminates when max_gens reached" do
      tc = Moses::TerminationCriteria.new(1000, 50)
      tc.should_terminate?(0, 50, -1.0, 0).should be_true
      tc.should_terminate?(0, 49, -1.0, 0).should be_false
    end

    it "terminates when target_score reached" do
      tc = Moses::TerminationCriteria.new(1000, 100, 0.0)
      tc.should_terminate?(0, 0, 0.0, 0).should be_true
      tc.should_terminate?(0, 0, -0.1, 0).should be_false
    end

    it "terminates when stagnation limit reached" do
      tc = Moses::TerminationCriteria.new(1000, 100, nil, 10)
      tc.should_terminate?(0, 0, -1.0, 10).should be_true
      tc.should_terminate?(0, 0, -1.0, 9).should be_false
    end

    it "does not terminate before any criteria met" do
      tc = Moses::TerminationCriteria.new(100, 50)
      tc.should_terminate?(0, 0, -1.0, 0).should be_false
    end
  end
end

describe Moses::Program do
  describe "creation" do
    it "creates program from expression string" do
      prog = Moses::Program.new("$0 and $1")
      prog.expression.should eq("$0 and $1")
    end

    it "extracts variables from expression" do
      prog = Moses::Program.new("$0 and $1")
      prog.variables.should contain("$0")
      prog.variables.should contain("$1")
    end

    it "calculates complexity from expression" do
      prog = Moses::Program.new("$0")
      simple_complexity = prog.complexity

      prog2 = Moses::Program.new("$0 and $1 and $2")
      prog2.complexity.should be >= simple_complexity
    end

    it "executes boolean expression" do
      prog = Moses::Program.new("$0")
      result = prog.execute([1.0], Moses::ProblemType::BooleanClassification)
      result.should be_a(Bool)
    end

    it "executes regression expression" do
      prog = Moses::Program.new("$0")
      result = prog.execute([3.14], Moses::ProblemType::Regression)
      result.should be_a(Float64)
      result.as(Float64).should be_close(3.14, 0.001)
    end
  end
end

describe Moses::Candidate do
  describe "creation" do
    it "creates from program string" do
      c = Moses::Candidate.new("$0 and $1")
      c.program.should eq("$0 and $1")
      c.scored?.should be_false
    end

    it "creates from Program object" do
      prog = Moses::Program.new("$0")
      c = Moses::Candidate.new(prog)
      c.program.should eq("$0")
    end

    it "starts with generation 0" do
      c = Moses::Candidate.new("$0")
      c.generation.should eq(0)
    end
  end

  describe "scoring" do
    it "is initially unscored" do
      c = Moses::Candidate.new("$0")
      c.scored?.should be_false
    end

    it "becomes scored after setting score" do
      c = Moses::Candidate.new("$0")
      c.score = Moses::CompositeScore.new(-0.5, 3)
      c.scored?.should be_true
    end
  end

  describe "complexity" do
    it "returns a positive complexity value" do
      c = Moses::Candidate.new("$0 and $1")
      c.complexity.should be > 0
    end
  end

  describe "execution" do
    it "executes boolean program" do
      c = Moses::Candidate.new("$0")
      result = c.execute([1.0], Moses::ProblemType::BooleanClassification)
      result.should be_a(Bool)
    end

    it "executes regression program" do
      c = Moses::Candidate.new("$0")
      result = c.execute([2.5], Moses::ProblemType::Regression)
      result.should be_a(Float64)
    end
  end

  describe "to_s" do
    it "includes program expression" do
      c = Moses::Candidate.new("$0")
      c.to_s.should contain("$0")
    end

    it "includes score when scored" do
      c = Moses::Candidate.new("$0")
      c.score = Moses::CompositeScore.new(-0.5, 3)
      c.to_s.should contain("score=")
    end
  end
end

describe Moses::ProgramNode do
  describe "VariableNode" do
    it "evaluates boolean correctly (>0.5 = true)" do
      vn = Moses::VariableNode.new(0)
      vn.evaluate_boolean([1.0]).should be_true
      vn.evaluate_boolean([0.0]).should be_false
    end

    it "evaluates numeric correctly" do
      vn = Moses::VariableNode.new(1)
      vn.evaluate_numeric([0.0, 3.14]).should eq(3.14)
    end

    it "returns default 0 for out-of-bounds index" do
      vn = Moses::VariableNode.new(5)
      vn.evaluate_numeric([1.0]).should eq(0.0)
    end

    it "reports correct complexity (1)" do
      vn = Moses::VariableNode.new(0)
      vn.complexity.should eq(1)
    end

    it "converts to string as $index" do
      vn = Moses::VariableNode.new(2)
      vn.to_s.should eq("$2")
    end
  end

  describe "ConstantNode" do
    it "evaluates boolean (value > 0.5 = true)" do
      cn = Moses::ConstantNode.new(1.0)
      cn.evaluate_boolean([] of Float64).should be_true

      cn2 = Moses::ConstantNode.new(0.3)
      cn2.evaluate_boolean([] of Float64).should be_false
    end

    it "evaluates numeric to its constant value" do
      cn = Moses::ConstantNode.new(42.0)
      cn.evaluate_numeric([] of Float64).should eq(42.0)
    end

    it "reports correct complexity (1)" do
      cn = Moses::ConstantNode.new(5.0)
      cn.complexity.should eq(1)
    end
  end

  describe "BinaryOpNode" do
    it "evaluates AND correctly" do
      left = Moses::VariableNode.new(0)
      right = Moses::VariableNode.new(1)
      op = Moses::BinaryOpNode.new("and", left, right)

      op.evaluate_boolean([1.0, 1.0]).should be_true
      op.evaluate_boolean([1.0, 0.0]).should be_false
    end

    it "evaluates OR correctly" do
      left = Moses::VariableNode.new(0)
      right = Moses::VariableNode.new(1)
      op = Moses::BinaryOpNode.new("or", left, right)

      op.evaluate_boolean([0.0, 1.0]).should be_true
      op.evaluate_boolean([0.0, 0.0]).should be_false
    end

    it "evaluates numeric addition correctly" do
      left = Moses::ConstantNode.new(2.0)
      right = Moses::ConstantNode.new(3.0)
      op = Moses::BinaryOpNode.new("+", left, right)

      op.evaluate_numeric([] of Float64).should eq(5.0)
    end

    it "evaluates numeric division with zero denominator returns 0" do
      left = Moses::ConstantNode.new(10.0)
      right = Moses::ConstantNode.new(0.0)
      op = Moses::BinaryOpNode.new("/", left, right)

      op.evaluate_numeric([] of Float64).should eq(0.0)
    end

    it "reports complexity as 1 + left + right" do
      left = Moses::VariableNode.new(0)
      right = Moses::VariableNode.new(1)
      op = Moses::BinaryOpNode.new("and", left, right)

      op.complexity.should eq(3)
    end
  end

  describe "UnaryOpNode" do
    it "evaluates NOT correctly" do
      operand = Moses::VariableNode.new(0)
      op = Moses::UnaryOpNode.new("not", operand)

      op.evaluate_boolean([1.0]).should be_false
      op.evaluate_boolean([0.0]).should be_true
    end

    it "evaluates numeric negation correctly" do
      operand = Moses::ConstantNode.new(5.0)
      op = Moses::UnaryOpNode.new("-", operand)

      op.evaluate_numeric([] of Float64).should eq(-5.0)
    end

    it "reports complexity as 1 + operand complexity" do
      operand = Moses::VariableNode.new(0)
      op = Moses::UnaryOpNode.new("not", operand)

      op.complexity.should eq(2)
    end
  end
end

describe Moses do
  describe "score_or_worst" do
    it "returns VERY_WORST_SCORE for unscored candidate" do
      c = Moses::Candidate.new("$0")
      Moses.score_or_worst(c).should eq(Moses::VERY_WORST_SCORE)
    end

    it "returns penalized_score for scored candidate" do
      c = Moses::Candidate.new("$0")
      c.score = Moses::CompositeScore.new(-0.5, 3)
      Moses.score_or_worst(c).should eq(-0.5)
    end

    it "normalizes NaN penalized_score to VERY_WORST_SCORE" do
      c = Moses::Candidate.new("$0")
      c.score = Moses::CompositeScore.new(Float64::NAN, 3)
      Moses.score_or_worst(c).should eq(Moses::VERY_WORST_SCORE)
    end
  end

  describe "compare_candidates" do
    it "returns negative when a < b" do
      a = Moses::Candidate.new("a")
      b = Moses::Candidate.new("b")
      b.score = Moses::CompositeScore.new(-0.3, 2)

      result = Moses.compare_candidates(a, b)
      result.should be < 0
    end

    it "returns positive when a > b" do
      a = Moses::Candidate.new("a")
      b = Moses::Candidate.new("b")
      a.score = Moses::CompositeScore.new(-0.3, 2)

      result = Moses.compare_candidates(a, b)
      result.should be > 0
    end

    it "returns 0 for two unscored candidates" do
      a = Moses::Candidate.new("a")
      b = Moses::Candidate.new("b")
      Moses.compare_candidates(a, b).should eq(0)
    end

    it "treats NaN-scored candidate as worst (transitively)" do
      nan_cand = Moses::Candidate.new("nan")
      nan_cand.score = Moses::CompositeScore.new(Float64::NAN, 2)

      good = Moses::Candidate.new("good")
      good.score = Moses::CompositeScore.new(-0.3, 2)

      unscored = Moses::Candidate.new("unscored")

      # NaN sorts as equal to unscored (both -> VERY_WORST_SCORE) and below good.
      Moses.compare_candidates(nan_cand, good).should be < 0
      Moses.compare_candidates(good, nan_cand).should be > 0
      Moses.compare_candidates(nan_cand, unscored).should eq(0)
    end

    it "is safe to use as a sort comparator with NaN scores" do
      a = Moses::Candidate.new("a")
      a.score = Moses::CompositeScore.new(-0.5, 2)
      b = Moses::Candidate.new("b")
      b.score = Moses::CompositeScore.new(Float64::NAN, 2)
      c = Moses::Candidate.new("c")
      c.score = Moses::CompositeScore.new(-0.1, 2)

      sorted = [a, b, c].sort { |x, y| Moses.compare_candidates(x, y) }
      sorted.last.program.should eq("c") # best score wins
      sorted.first.program.should eq("b") # NaN sorts as worst
    end
  end
end
