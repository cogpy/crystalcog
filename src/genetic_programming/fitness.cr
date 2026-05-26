# Fitness Evaluation Framework for Genetic Programming
#
# This module provides fitness functions and evaluation mechanisms
# for assessing the quality of evolved programs.
#
# References:
# - MOSES scoring functions
# - OpenCog behavioral scoring

require "./program_tree"
require "../atomspace/atomspace_main"

module GeneticProgramming
  # Base fitness function interface
  abstract class FitnessFunction
    abstract def evaluate(program : Program) : Float64
    abstract def name : String

    # Batch evaluation for efficiency
    def evaluate_population(population : Array(Program))
      population.each do |program|
        program.fitness = evaluate(program)
      end
    end
  end

  # Supervised learning fitness - compares program outputs to expected values
  class SupervisedFitness < FitnessFunction
    getter inputs : Array(Array(Float64 | Bool))
    getter expected_outputs : Array(Float64 | Bool)
    property error_metric : Symbol

    def initialize(@inputs : Array(Array(Float64 | Bool)),
                   @expected_outputs : Array(Float64 | Bool),
                   @error_metric : Symbol = :mse)
      if @inputs.size != @expected_outputs.size
        raise GPException.new("Inputs and outputs must have same size")
      end
    end

    def name : String
      "SupervisedFitness"
    end

    def evaluate(program : Program) : Float64
      return Float64::MIN if @inputs.empty?

      errors = [] of Float64

      @inputs.each_with_index do |input, i|
        begin
          actual = program.evaluate(input)
          expected = @expected_outputs[i]

          error = compute_error(actual, expected)
          errors << error
        rescue ex
          # Program crashed - assign maximum error
          errors << Float64::MAX
        end
      end

      # Convert total error to fitness (higher is better)
      # Use negative error so that lower error = higher fitness
      total_error = aggregate_errors(errors)

      # Handle infinite or NaN values
      if total_error.infinite? || total_error.nan?
        Float64::MIN
      else
        -total_error
      end
    end

    private def compute_error(actual : Float64 | Bool, expected : Float64 | Bool) : Float64
      case {actual, expected}
      when {Float64, Float64}
        diff = actual.as(Float64) - expected.as(Float64)
        case @error_metric
        when :mse
          diff ** 2
        when :mae
          diff.abs
        when :rmse
          diff ** 2
        else
          diff ** 2
        end
      when {Bool, Bool}
        actual.as(Bool) == expected.as(Bool) ? 0.0 : 1.0
      else
        # Type mismatch
        1.0
      end
    end

    private def aggregate_errors(errors : Array(Float64)) : Float64
      return 0.0 if errors.empty?

      case @error_metric
      when :mse
        errors.sum / errors.size
      when :mae
        errors.sum / errors.size
      when :rmse
        Math.sqrt(errors.sum / errors.size)
      else
        errors.sum / errors.size
      end
    end
  end

  # Boolean classification fitness
  class BooleanFitness < FitnessFunction
    getter inputs : Array(Array(Bool))
    getter expected_outputs : Array(Bool)

    def initialize(@inputs : Array(Array(Bool)), @expected_outputs : Array(Bool))
      if @inputs.size != @expected_outputs.size
        raise GPException.new("Inputs and outputs must have same size")
      end
    end

    def name : String
      "BooleanFitness"
    end

    def evaluate(program : Program) : Float64
      return Float64::MIN if @inputs.empty?

      correct = 0
      total = @inputs.size

      @inputs.each_with_index do |input, i|
        begin
          # Convert Bool inputs to Float64 | Bool union
          input_values = input.map { |b| b.as(Float64 | Bool) }
          actual = program.evaluate(input_values)
          expected = @expected_outputs[i]

          if actual.is_a?(Bool) && actual == expected
            correct += 1
          elsif actual.is_a?(Float64)
            # Convert float to bool (> 0.5 = true)
            bool_result = actual > 0.5
            correct += 1 if bool_result == expected
          end
        rescue
          # Program crashed
        end
      end

      # Return accuracy as fitness
      correct.to_f / total
    end

    # Get confusion matrix
    def confusion_matrix(program : Program) : Hash(String, Int32)
      tp = 0 # True positives
      tn = 0 # True negatives
      fp = 0 # False positives
      fn = 0 # False negatives

      @inputs.each_with_index do |input, i|
        begin
          input_values = input.map { |b| b.as(Float64 | Bool) }
          actual = program.evaluate(input_values)
          expected = @expected_outputs[i]

          predicted = if actual.is_a?(Bool)
                        actual
                      else
                        actual.as(Float64) > 0.5
                      end

          if predicted && expected
            tp += 1
          elsif !predicted && !expected
            tn += 1
          elsif predicted && !expected
            fp += 1
          else
            fn += 1
          end
        rescue
          fn += 1 if @expected_outputs[i]
          fp += 1 unless @expected_outputs[i]
        end
      end

      {"tp" => tp, "tn" => tn, "fp" => fp, "fn" => fn}
    end

    # Calculate precision
    def precision(program : Program) : Float64
      cm = confusion_matrix(program)
      tp = cm["tp"]
      fp = cm["fp"]
      return 0.0 if tp + fp == 0
      tp.to_f / (tp + fp)
    end

    # Calculate recall
    def recall(program : Program) : Float64
      cm = confusion_matrix(program)
      tp = cm["tp"]
      fn = cm["fn"]
      return 0.0 if tp + fn == 0
      tp.to_f / (tp + fn)
    end

    # Calculate F1 score
    def f1_score(program : Program) : Float64
      p = precision(program)
      r = recall(program)
      return 0.0 if p + r == 0
      2 * (p * r) / (p + r)
    end
  end

  # Symbolic regression fitness
  class RegressionFitness < SupervisedFitness
    property target_expression : String?

    def initialize(inputs : Array(Array(Float64 | Bool)),
                   expected_outputs : Array(Float64 | Bool),
                   @target_expression : String? = nil)
      super(inputs, expected_outputs, :mse)
    end

    def name : String
      "RegressionFitness"
    end

    # Compute R² (coefficient of determination)
    def r_squared(program : Program) : Float64
      return 0.0 if @inputs.empty?

      predictions = [] of Float64
      actuals = [] of Float64

      @inputs.each_with_index do |input, i|
        begin
          pred = program.evaluate(input)
          if pred.is_a?(Float64)
            predictions << pred
            actuals << @expected_outputs[i].as(Float64)
          end
        rescue
          # Skip failed evaluations
        end
      end

      return 0.0 if predictions.empty?

      mean_actual = actuals.sum / actuals.size
      ss_tot = actuals.sum { |a| (a - mean_actual) ** 2 }
      ss_res = predictions.zip(actuals).sum { |p, a| (a - p) ** 2 }

      return 0.0 if ss_tot == 0
      1.0 - (ss_res / ss_tot)
    end
  end

  # Multi-objective fitness combining multiple criteria
  class MultiObjectiveFitness < FitnessFunction
    getter objectives : Array(FitnessFunction)
    getter weights : Array(Float64)

    def initialize(@objectives : Array(FitnessFunction), @weights : Array(Float64)? = nil)
      @weights = weights || Array.new(@objectives.size, 1.0 / @objectives.size)
      if @objectives.size != @weights.not_nil!.size
        raise GPException.new("Objectives and weights must have same size")
      end
    end

    def name : String
      "MultiObjectiveFitness"
    end

    def evaluate(program : Program) : Float64
      total = 0.0
      @objectives.each_with_index do |obj, i|
        fitness = obj.evaluate(program)
        total += fitness * @weights.not_nil![i]
      end
      total
    end

    # Get individual objective scores
    def evaluate_objectives(program : Program) : Array(Float64)
      @objectives.map { |obj| obj.evaluate(program) }
    end
  end

  # Complexity-aware fitness (includes parsimony pressure)
  class ComplexityPenalizedFitness < FitnessFunction
    getter base_fitness : FitnessFunction
    property parsimony_coefficient : Float64
    property size_limit : Int32
    property depth_limit : Int32

    def initialize(@base_fitness : FitnessFunction,
                   @parsimony_coefficient : Float64 = 0.001,
                   @size_limit : Int32 = 100,
                   @depth_limit : Int32 = 10)
    end

    def name : String
      "ComplexityPenalizedFitness"
    end

    def evaluate(program : Program) : Float64
      # Check hard limits
      if program.size > @size_limit || program.depth > @depth_limit
        return Float64::MIN
      end

      base_score = @base_fitness.evaluate(program)

      # Apply parsimony pressure
      base_score - @parsimony_coefficient * program.size
    end
  end

  # Behavioral fitness based on program execution traces
  class BehavioralFitness < FitnessFunction
    getter target_behavior : Array(Tuple(Array(Float64 | Bool), Float64 | Bool))
    property tolerance : Float64

    def initialize(@target_behavior : Array(Tuple(Array(Float64 | Bool), Float64 | Bool)),
                   @tolerance : Float64 = 0.01)
    end

    def name : String
      "BehavioralFitness"
    end

    def evaluate(program : Program) : Float64
      return Float64::MIN if @target_behavior.empty?

      matches = 0

      @target_behavior.each do |input, expected|
        begin
          actual = program.evaluate(input)

          if values_match?(actual, expected)
            matches += 1
          end
        rescue
          # Program failed
        end
      end

      matches.to_f / @target_behavior.size
    end

    private def values_match?(actual : Float64 | Bool, expected : Float64 | Bool) : Bool
      case {actual, expected}
      when {Bool, Bool}
        actual.as(Bool) == expected.as(Bool)
      when {Float64, Float64}
        (actual.as(Float64) - expected.as(Float64)).abs <= @tolerance
      else
        false
      end
    end
  end

  # AtomSpace-integrated fitness for knowledge-guided evolution
  class AtomSpaceFitness < FitnessFunction
    getter atomspace : AtomSpace::AtomSpace
    getter base_fitness : FitnessFunction
    property knowledge_bonus : Float64

    def initialize(@atomspace : AtomSpace::AtomSpace,
                   @base_fitness : FitnessFunction,
                   @knowledge_bonus : Float64 = 0.1)
    end

    def name : String
      "AtomSpaceFitness"
    end

    def evaluate(program : Program) : Float64
      base_score = @base_fitness.evaluate(program)

      # Bonus for using concepts from AtomSpace
      concept_bonus = calculate_concept_bonus(program)

      base_score + @knowledge_bonus * concept_bonus
    end

    private def calculate_concept_bonus(program : Program) : Float64
      # Count how many program nodes correspond to concepts in AtomSpace
      bonus = 0.0

      program.all_nodes.each do |node|
        # Check if node corresponds to a known concept
        node_name = node.to_s
        concepts = @atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)

        concepts.each do |concept|
          if concept.name.downcase.includes?(node_name.downcase)
            bonus += 0.1
          end
        end
      end

      bonus.clamp(0.0, 1.0)
    end
  end

  # Fitness statistics tracker
  class FitnessStats
    getter best_fitness : Float64
    getter worst_fitness : Float64
    getter average_fitness : Float64
    getter std_deviation : Float64
    getter generation : Int32

    def initialize(population : Array(Program), @generation : Int32)
      if population.empty?
        @best_fitness = 0.0
        @worst_fitness = 0.0
        @average_fitness = 0.0
        @std_deviation = 0.0
      else
        fitnesses = population.map(&.fitness)
        @best_fitness = fitnesses.max
        @worst_fitness = fitnesses.min
        @average_fitness = fitnesses.sum / fitnesses.size

        variance = fitnesses.sum { |f| (f - @average_fitness) ** 2 } / fitnesses.size
        @std_deviation = Math.sqrt(variance)
      end
    end

    def to_s : String
      "Gen #{@generation}: Best=#{@best_fitness.round(4)}, Avg=#{@average_fitness.round(4)}, " \
      "Worst=#{@worst_fitness.round(4)}, StdDev=#{@std_deviation.round(4)}"
    end
  end
end
