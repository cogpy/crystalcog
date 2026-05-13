# MOSES types and core data structures
# Crystal implementation of MOSES core types

module Moses
  # Basic score type - using Float64 for precision in Crystal
  alias Score = Float64

  # Special score values
  VERY_BEST_SCORE  = Float64::MAX
  VERY_WORST_SCORE = Float64::MIN
  EPSILON_SCORE    = Float64::EPSILON

  # Helper method to get score or worst score
  def self.score_or_worst(candidate : Candidate) : Score
    candidate.score.try(&.penalized_score) || VERY_WORST_SCORE
  end

  # Helper method to safely compare candidates by score
  def self.compare_candidates(a : Candidate, b : Candidate) : Int32
    score_a = score_or_worst(a)
    score_b = score_or_worst(b)
    score_a <=> score_b
  end

  # Complexity type for measuring program complexity
  alias Complexity = Int32

  # Composite score that includes fitness, complexity, and penalties
  struct CompositeScore
    include Comparable(CompositeScore)

    getter score : Score
    getter complexity : Complexity
    getter complexity_penalty : Score
    getter uniformity_penalty : Score
    getter penalized_score : Score

    def initialize(@score : Score, @complexity : Complexity,
                   @complexity_penalty : Score = 0.0, @uniformity_penalty : Score = 0.0)
      @penalized_score = @score - @complexity_penalty - @uniformity_penalty
    end

    # Comparison operator for scoring (higher is better)
    def <=>(other : CompositeScore)
      @penalized_score <=> other.penalized_score
    end

    def to_s(io)
      io << "CompositeScore(score=#{score}, complexity=#{complexity}, "
      io << "penalized=#{penalized_score})"
    end
  end

  # Problem types that MOSES can solve
  enum ProblemType
    BooleanClassification
    Regression
    Clustering
    PatternMining
    FeatureSelection
  end

  # Evolution parameters for MOSES
  struct MosesParams
    property problem_type : ProblemType
    property training_data : Array(Array(Float64))
    property target_data : Array(Float64)?
    property max_evals : Int32
    property max_gens : Int32
    property population_size : Int32
    property deme_size : Int32
    property complexity_penalty : Score
    property uniformity_penalty : Score
    property termination_criteria : TerminationCriteria

    def initialize(@problem_type : ProblemType, @training_data : Array(Array(Float64)),
                   @max_evals : Int32 = 10000, @max_gens : Int32 = 100,
                   @population_size : Int32 = 100, @deme_size : Int32 = 20,
                   @complexity_penalty : Score = 0.1, @uniformity_penalty : Score = 0.0,
                   @target_data : Array(Float64)? = nil)
      @termination_criteria = TerminationCriteria.new(max_evals, max_gens)
    end
  end

  # Termination criteria for evolutionary search
  struct TerminationCriteria
    property max_evals : Int32
    property max_gens : Int32
    property target_score : Score?
    property stagnation_limit : Int32

    def initialize(@max_evals : Int32, @max_gens : Int32,
                   @target_score : Score? = nil, @stagnation_limit : Int32 = 20)
    end

    def should_terminate?(evals : Int32, gens : Int32, best_score : Score,
                          stagnation_count : Int32) : Bool
      return true if evals >= max_evals
      return true if gens >= max_gens
      return true if target_score && best_score >= target_score.not_nil!
      return true if stagnation_count >= stagnation_limit
      false
    end
  end

  # Program representation using a structured approach
  # Supports both string-based and tree-based representations
  class Program
    property expression : String
    property parsed_tree : ProgramNode?
    property variables : Array(String)
    property constants : Array(Float64)

    def initialize(@expression : String)
      @parsed_tree = nil
      @variables = extract_variables(@expression)
      @constants = extract_constants(@expression)
    end

    # Create program from tree structure
    def initialize(@parsed_tree : ProgramNode)
      @expression = @parsed_tree.to_s
      @variables = @parsed_tree.variables
      @constants = @parsed_tree.constants
    end

    # Parse expression into tree if not already parsed
    def parse! : ProgramNode?
      return @parsed_tree if @parsed_tree

      begin
        @parsed_tree = ProgramParser.parse(@expression)
      rescue
        @parsed_tree = nil
      end

      @parsed_tree
    end

    # Get complexity of the program
    def complexity : Complexity
      if tree = @parsed_tree
        tree.complexity
      else
        # Fallback string-based complexity
        base = @expression.size
        operators = @expression.count(" and ") + @expression.count(" or ") +
                    @expression.count(" + ") + @expression.count(" - ") +
                    @expression.count(" * ") + @expression.count(" / ")
        parentheses = @expression.count("(") + @expression.count(")")
        base + operators * 2 + parentheses
      end
    end

    # Execute program with given inputs
    def execute(inputs : Array(Float64), problem_type : ProblemType) : Float64 | Bool
      case problem_type
      when ProblemType::BooleanClassification
        execute_boolean(inputs)
      when ProblemType::Regression
        execute_regression(inputs)
      else
        0.0
      end
    end

    private def execute_boolean(inputs : Array(Float64)) : Bool
      # Execute as boolean expression
      if tree = @parsed_tree
        tree.evaluate_boolean(inputs)
      else
        # Fallback to string evaluation
        ProgramExecutor.execute_boolean(@expression, inputs)
      end
    end

    private def execute_regression(inputs : Array(Float64)) : Float64
      # Execute as mathematical expression
      if tree = @parsed_tree
        tree.evaluate_numeric(inputs)
      else
        # Fallback to string evaluation
        ProgramExecutor.execute_numeric(@expression, inputs)
      end
    end

    private def extract_variables(expr : String) : Array(String)
      expr.scan(/\$\d+/).map(&.[0]).uniq
    end

    private def extract_constants(expr : String) : Array(Float64)
      expr.scan(/\b\d+\.?\d*\b/).map(&.[0].to_f?).compact
    end

    def to_s(io)
      io << @expression
    end
  end

  # Program tree node for structured representation
  abstract class ProgramNode
    abstract def to_s(io)
    abstract def complexity : Complexity
    abstract def variables : Array(String)
    abstract def constants : Array(Float64)
    abstract def evaluate_boolean(inputs : Array(Float64)) : Bool
    abstract def evaluate_numeric(inputs : Array(Float64)) : Float64
  end

  # Variable node (e.g., $0, $1)
  class VariableNode < ProgramNode
    property index : Int32

    def initialize(@index : Int32)
    end

    def to_s(io)
      io << "$#{@index}"
    end

    def complexity : Complexity
      1
    end

    def variables : Array(String)
      ["$#{@index}"]
    end

    def constants : Array(Float64)
      [] of Float64
    end

    def evaluate_boolean(inputs : Array(Float64)) : Bool
      value = inputs[@index]? || 0.0
      value > 0.5
    end

    def evaluate_numeric(inputs : Array(Float64)) : Float64
      inputs[@index]? || 0.0
    end
  end

  # Constant node
  class ConstantNode < ProgramNode
    property value : Float64

    def initialize(@value : Float64)
    end

    def to_s(io)
      io << @value.to_s
    end

    def complexity : Complexity
      1
    end

    def variables : Array(String)
      [] of String
    end

    def constants : Array(Float64)
      [@value]
    end

    def evaluate_boolean(inputs : Array(Float64)) : Bool
      @value > 0.5
    end

    def evaluate_numeric(inputs : Array(Float64)) : Float64
      @value
    end
  end

  # Binary operation node
  class BinaryOpNode < ProgramNode
    property operator : String
    property left : ProgramNode
    property right : ProgramNode

    def initialize(@operator : String, @left : ProgramNode, @right : ProgramNode)
    end

    def to_s(io)
      io << "("
      @left.to_s(io)
      io << " #{@operator} "
      @right.to_s(io)
      io << ")"
    end

    def complexity : Complexity
      1 + @left.complexity + @right.complexity
    end

    def variables : Array(String)
      (@left.variables + @right.variables).uniq
    end

    def constants : Array(Float64)
      @left.constants + @right.constants
    end

    def evaluate_boolean(inputs : Array(Float64)) : Bool
      left_val = @left.evaluate_boolean(inputs)
      right_val = @right.evaluate_boolean(inputs)

      case @operator
      when "and", "&", "&&"
        left_val && right_val
      when "or", "|", "||"
        left_val || right_val
      else
        left_val
      end
    end

    def evaluate_numeric(inputs : Array(Float64)) : Float64
      left_val = @left.evaluate_numeric(inputs)
      right_val = @right.evaluate_numeric(inputs)

      case @operator
      when "+"
        left_val + right_val
      when "-"
        left_val - right_val
      when "*"
        left_val * right_val
      when "/"
        right_val != 0.0 ? left_val / right_val : 0.0
      else
        left_val
      end
    end
  end

  # Unary operation node
  class UnaryOpNode < ProgramNode
    property operator : String
    property operand : ProgramNode

    def initialize(@operator : String, @operand : ProgramNode)
    end

    def to_s(io)
      io << "#{@operator}("
      @operand.to_s(io)
      io << ")"
    end

    def complexity : Complexity
      1 + @operand.complexity
    end

    def variables : Array(String)
      @operand.variables
    end

    def constants : Array(Float64)
      @operand.constants
    end

    def evaluate_boolean(inputs : Array(Float64)) : Bool
      operand_val = @operand.evaluate_boolean(inputs)

      case @operator
      when "not", "!"
        !operand_val
      else
        operand_val
      end
    end

    def evaluate_numeric(inputs : Array(Float64)) : Float64
      operand_val = @operand.evaluate_numeric(inputs)

      case @operator
      when "-"
        -operand_val
      when "abs"
        operand_val.abs
      else
        operand_val
      end
    end
  end

  # Results from MOSES evolution
  struct MosesResult
    property candidates : Array(Candidate)
    property evaluations : Int32
    property generations : Int32
    property best_score : CompositeScore?

    def initialize(@candidates : Array(Candidate), @evaluations : Int32, @generations : Int32)
      scores = candidates.compact_map(&.score)
      @best_score = scores.max? if !scores.empty?
    end

    def best_candidate : Candidate?
      return nil if candidates.empty?
      candidates.max_by? { |c| Moses.score_or_worst(c) }
    end
  end

  # Program candidate representation
  # Now uses structured Program representation while maintaining compatibility
  struct Candidate
    property program : String          # String representation for compatibility
    property parsed_program : Program? # Structured representation
    property score : CompositeScore?
    property generation : Int32
    property evaluations : Int32

    def initialize(@program : String, @generation : Int32 = 0, @evaluations : Int32 = 0)
      @score = nil
      @parsed_program = nil
    end

    def initialize(parsed_program : Program, @generation : Int32 = 0, @evaluations : Int32 = 0)
      @parsed_program = parsed_program
      @program = parsed_program.expression
      @score = nil
    end

    # Get structured program representation
    def get_program : Program
      return @parsed_program.not_nil! if @parsed_program

      @parsed_program = Program.new(@program)
      @parsed_program.not_nil!
    end

    # Execute the program with given inputs
    def execute(inputs : Array(Float64), problem_type : ProblemType) : Float64 | Bool
      get_program.execute(inputs, problem_type)
    end

    # Get program complexity
    def complexity : Complexity
      get_program.complexity
    end

    def scored?
      !@score.nil?
    end

    def to_s(io)
      io << "Candidate(#{program}"
      if scored?
        io << ", score=#{score}"
      end
      io << ")"
    end
  end

  # Simple program parser for converting strings to trees
  module ProgramParser
    def self.parse(expression : String) : ProgramNode?
      # Simple parser - in production this would be more sophisticated
      tokens = tokenize(expression)
      return nil if tokens.empty?

      begin
        parse_expression(tokens)
      rescue
        nil
      end
    end

    private def self.tokenize(expression : String) : Array(String)
      expression.downcase
        .gsub(/\s+/, " ")
        .gsub("(", " ( ")
        .gsub(")", " ) ")
        .split(/\s+/)
        .reject(&.empty?)
    end

    private def self.parse_expression(tokens : Array(String)) : ProgramNode?
      return nil if tokens.empty?

      # Simple expression parsing
      left = parse_term(tokens)
      return left unless left

      while !tokens.empty? && (tokens[0] == "and" || tokens[0] == "or" || tokens[0] == "+" || tokens[0] == "-")
        op = tokens.shift
        right = parse_term(tokens)
        return left unless right

        left = BinaryOpNode.new(op, left, right)
      end

      left
    end

    private def self.parse_term(tokens : Array(String)) : ProgramNode?
      return nil if tokens.empty?

      token = tokens[0]

      case token
      when "not", "!"
        tokens.shift
        operand = parse_term(tokens)
        return nil unless operand
        UnaryOpNode.new("not", operand)
      when "("
        tokens.shift # consume "("
        expr = parse_expression(tokens)
        tokens.shift if !tokens.empty? && tokens[0] == ")" # consume ")"
        expr
      else
        if token.starts_with?("$")
          tokens.shift
          index = token[1..].to_i? || 0
          VariableNode.new(index)
        elsif value = token.to_f?
          tokens.shift
          ConstantNode.new(value)
        else
          tokens.shift
          ConstantNode.new(0.0) # Default for unknown tokens
        end
      end
    end
  end

  # Program executor for string-based execution (fallback)
  module ProgramExecutor
    def self.execute_boolean(expression : String, inputs : Array(Float64)) : Bool
      # Substitute variables with boolean values
      expr = expression.dup
      inputs.each_with_index do |value, index|
        bool_val = value > 0.5 ? "true" : "false"
        expr = expr.gsub("$#{index}", bool_val)
      end

      # Simple boolean evaluation
      evaluate_boolean_string(expr)
    end

    def self.execute_numeric(expression : String, inputs : Array(Float64)) : Float64
      # Substitute variables with numeric values
      expr = expression.dup
      inputs.each_with_index do |value, index|
        expr = expr.gsub("$#{index}", value.to_s)
      end

      # Simple numeric evaluation
      evaluate_numeric_string(expr)
    end

    private def self.evaluate_boolean_string(expr : String) : Bool
      # Very simple boolean evaluation
      if expr.includes?("true") && !expr.includes?("false")
        true
      elsif expr.includes?("false") && !expr.includes?("true")
        false
      else
        false # Default for complex expressions
      end
    end

    private def self.evaluate_numeric_string(expr : String) : Float64
      # Try to parse as simple number
      expr.to_f? || 0.0
    end
  end
end
