# Program Synthesis Engine for Genetic Programming
#
# This module implements program synthesis from input/output examples
# and specifications, combining genetic programming with constraint solving.
#
# References:
# - Inductive Program Synthesis
# - MOSES program learning
# - OpenCog MOSES integration

require "./program_tree"
require "./operators"
require "./fitness"
require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module GeneticProgramming
  # Problem specification for synthesis
  struct SynthesisSpec
    property input_types : Array(ReturnType)
    property output_type : ReturnType
    property examples : Array(Tuple(Array(Float64 | Bool), Float64 | Bool))
    property constraints : Array(String)
    property target_complexity : Int32?

    def initialize(
      @input_types : Array(ReturnType) = [] of ReturnType,
      @output_type : ReturnType = ReturnType::Any,
      @examples : Array(Tuple(Array(Float64 | Bool), Float64 | Bool)) = [] of Tuple(Array(Float64 | Bool), Float64 | Bool),
      @constraints : Array(String) = [] of String,
      @target_complexity : Int32? = nil
    )
    end

    # Validate the specification
    def valid? : Bool
      return false if @examples.empty?
      @examples.all? { |input, _| input.size == @input_types.size }
    end
  end

  # Synthesis result
  class SynthesisResult
    getter program : Program?
    getter fitness : Float64
    getter generations : Int32
    getter evaluations : Int32
    getter success : Bool
    getter error_message : String?

    def initialize(@program : Program? = nil,
                   @fitness : Float64 = Float64::MIN,
                   @generations : Int32 = 0,
                   @evaluations : Int32 = 0,
                   @success : Bool = false,
                   @error_message : String? = nil)
    end
  end

  # Main program synthesis engine
  class ProgramSynthesizer
    getter config : GPConfig
    getter function_set : FunctionSet?
    property fitness_function : FitnessFunction?
    property population : Array(Program)
    getter best_program : Program?
    property generation : Int32
    getter evaluations : Int32
    getter atomspace : AtomSpace::AtomSpace?

    # Genetic operators
    protected getter generator : TreeGenerator?
    @crossover : Crossover?
    @mutation : Mutation?
    @selection : Selection?

    def initialize(@config : GPConfig = GPConfig.new)
      @population = [] of Program
      @generation = 0
      @evaluations = 0
      @best_program = nil
      @function_set = nil
    end

    # Setup for boolean synthesis
    def setup_boolean(num_variables : Int32)
      @function_set = FunctionSet.new(num_variables)
        .add_boolean_functions
        .add_comparison_functions

      setup_operators
      self
    end

    # Setup for symbolic regression
    def setup_regression(num_variables : Int32)
      @function_set = FunctionSet.new(num_variables)
        .add_arithmetic_functions
        .add_math_functions
        .add_comparison_functions
        .add_control_flow

      setup_operators
      self
    end

    # Setup for general purpose synthesis
    def setup_general(num_variables : Int32)
      @function_set = FunctionSet.new(num_variables)
        .add_boolean_functions
        .add_arithmetic_functions
        .add_comparison_functions
        .add_math_functions
        .add_control_flow

      setup_operators
      self
    end

    # Manual function set configuration
    def configure_function_set(function_set : FunctionSet)
      @function_set = function_set
      setup_operators
      self
    end

    # Connect to AtomSpace for knowledge-guided synthesis
    def connect_atomspace(atomspace : AtomSpace::AtomSpace)
      @atomspace = atomspace
      self
    end

    private def setup_operators
      fs = @function_set.not_nil!
      @generator = TreeGenerator.new(fs, @config.max_depth)
      @crossover = Crossover.new(@config.max_depth, @config.max_size)
      @mutation = Mutation.new(fs, @config.max_depth, @config.max_size)
      @selection = Selection.new(@config.tournament_size)
    end

    # Synthesize program from examples
    def synthesize(spec : SynthesisSpec) : SynthesisResult
      unless spec.valid?
        return SynthesisResult.new(error_message: "Invalid specification")
      end

      # Setup if not already configured
      if @function_set.nil?
        setup_general(spec.input_types.size)
      end

      # Create fitness function from examples
      inputs = spec.examples.map { |e| e[0] }
      outputs = spec.examples.map { |e| e[1] }

      base_fitness = if spec.output_type.boolean?
                       bool_inputs = inputs.map { |arr| arr.map { |v| v.as(Bool) rescue (v.as(Float64) > 0.5) } }
                       bool_outputs = outputs.map { |v| v.as(Bool) rescue (v.as(Float64) > 0.5) }
                       BooleanFitness.new(bool_inputs, bool_outputs)
                     else
                       SupervisedFitness.new(inputs, outputs)
                     end

      # Apply complexity penalty if target complexity specified
      @fitness_function = if tc = spec.target_complexity
                            ComplexityPenalizedFitness.new(
                              base_fitness,
                              @config.parsimony_coefficient,
                              tc * 2,
                              @config.max_depth
                            )
                          else
                            base_fitness
                          end

      # Run evolution
      run_evolution
    end

    # Synthesize program from input/output pairs directly
    def synthesize_from_examples(inputs : Array(Array(Float64)),
                                 outputs : Array(Float64),
                                 problem_type : Symbol = :regression) : SynthesisResult
      if inputs.empty? || inputs.size != outputs.size
        return SynthesisResult.new(error_message: "Invalid input/output data")
      end

      num_vars = inputs.first.size

      case problem_type
      when :regression
        setup_regression(num_vars)
      when :boolean
        setup_boolean(num_vars)
      else
        setup_general(num_vars)
      end

      # Convert to union type
      input_unions = inputs.map { |arr| arr.map { |v| v.as(Float64 | Bool) } }
      output_unions = outputs.map { |v| v.as(Float64 | Bool) }

      @fitness_function = SupervisedFitness.new(input_unions, output_unions)

      run_evolution
    end

    # Run the evolutionary process
    private def run_evolution : SynthesisResult
      @generation = 0
      @evaluations = 0

      # Initialize population
      initialize_population

      # Evaluate initial population
      evaluate_population

      # Track best
      update_best

      CogUtil::Logger.info("GP: Starting evolution with population size #{@config.population_size}")

      # Main evolutionary loop
      while @generation < @config.max_generations
        @generation += 1

        # Check for perfect solution
        if @best_program && @best_program.not_nil!.fitness >= 1.0 - 1e-10
          CogUtil::Logger.info("GP: Perfect solution found at generation #{@generation}")
          break
        end

        # Evolve next generation
        evolve_generation

        # Evaluate new population
        evaluate_population

        # Update best
        update_best

        # Log progress
        if @generation % 10 == 0 || @generation == 1
          stats = FitnessStats.new(@population, @generation)
          CogUtil::Logger.debug("GP: #{stats}")
        end
      end

      # Return result
      if bp = @best_program
        SynthesisResult.new(
          program: bp,
          fitness: bp.fitness,
          generations: @generation,
          evaluations: @evaluations,
          success: bp.fitness >= 0.99
        )
      else
        SynthesisResult.new(
          generations: @generation,
          evaluations: @evaluations,
          error_message: "Evolution failed to find a solution"
        )
      end
    end

    private def initialize_population
      generator = @generator.not_nil!
      @population = generator.generate_population(@config.population_size)
    end

    private def evaluate_population
      fitness_func = @fitness_function.not_nil!

      @population.each do |program|
        program.fitness = fitness_func.evaluate(program)
        @evaluations += 1
      end
    end

    private def update_best
      current_best = @population.max_by(&.fitness)

      if @best_program.nil? || current_best.fitness > @best_program.not_nil!.fitness
        @best_program = current_best.clone
        @best_program.not_nil!.generation = @generation
      end
    end

    private def evolve_generation
      selection = @selection.not_nil!
      crossover = @crossover.not_nil!
      mutation = @mutation.not_nil!

      new_population = [] of Program

      # Elitism - keep best individuals
      elite = selection.select_elite(@population, @config.elitism_count)
      new_population.concat(elite)

      # Fill rest of population
      while new_population.size < @config.population_size
        op = Random.rand

        if op < @config.crossover_rate
          # Crossover
          parent1 = selection.tournament_select(@population)
          parent2 = selection.tournament_select(@population)
          child1, child2 = crossover.subtree_crossover(parent1, parent2)

          new_population << child1 if new_population.size < @config.population_size
          new_population << child2 if new_population.size < @config.population_size

        elsif op < @config.crossover_rate + @config.mutation_rate
          # Mutation
          parent = selection.tournament_select(@population)
          child = mutation.mutate(parent)
          new_population << child

        else
          # Reproduction (copy)
          parent = selection.tournament_select(@population)
          new_population << parent.clone
        end
      end

      @population = new_population
    end

    # Public method to run a single evolution step (for co-evolution)
    def step_evolution
      evolve_generation
      evaluate_population
      update_best
    end

    # Initialize population from generator
    def init_population
      if gen = @generator
        @population = gen.generate_population(@config.population_size)
      end
    end

    # Get current population statistics
    def stats : FitnessStats
      FitnessStats.new(@population, @generation)
    end

    # Get diversity metrics
    def diversity : Float64
      Diversity.structural_diversity(@population)
    end

    # Export best program to AtomSpace
    def export_to_atomspace : AtomSpace::Atom?
      if bp = @best_program
        atomspace_instance = @atomspace || AtomSpace::AtomSpace.new
        bp.to_atomspace(atomspace_instance)
      end
    end
  end

  # Specialized synthesizer for boolean functions
  class BooleanSynthesizer < ProgramSynthesizer
    def initialize(num_variables : Int32, config : GPConfig = GPConfig.new)
      super(config)
      setup_boolean(num_variables)
    end

    # Synthesize from truth table
    def synthesize_from_truth_table(truth_table : Hash(Array(Bool), Bool)) : SynthesisResult
      inputs = truth_table.keys.map { |k| k.map { |b| b.as(Bool) } }
      outputs = truth_table.values

      @fitness_function = BooleanFitness.new(inputs, outputs)
      run_evolution
    end
  end

  # Specialized synthesizer for symbolic regression
  class SymbolicRegressionSynthesizer < ProgramSynthesizer
    def initialize(num_variables : Int32, config : GPConfig = GPConfig.new)
      super(config)
      setup_regression(num_variables)
    end

    # Synthesize from data points
    def synthesize_from_data(x_data : Array(Array(Float64)),
                             y_data : Array(Float64)) : SynthesisResult
      if x_data.empty? || x_data.size != y_data.size
        return SynthesisResult.new(error_message: "Invalid data")
      end

      inputs = x_data.map { |arr| arr.map { |v| v.as(Float64 | Bool) } }
      outputs = y_data.map { |v| v.as(Float64 | Bool) }

      @fitness_function = RegressionFitness.new(inputs, outputs)
      run_evolution
    end

    # Get R² of best program
    def r_squared : Float64
      if bp = @best_program
        ff = @fitness_function
        if ff.is_a?(RegressionFitness)
          ff.r_squared(bp)
        else
          0.0
        end
      else
        0.0
      end
    end
  end

  # Co-evolutionary synthesis with multiple populations
  class CoevolutionarySynthesizer
    getter synthesizers : Array(ProgramSynthesizer)
    getter best_overall : Program?

    def initialize(num_populations : Int32 = 4, config : GPConfig = GPConfig.new)
      @synthesizers = Array.new(num_populations) { ProgramSynthesizer.new(config) }
      @best_overall = nil
    end

    # Run co-evolution with migration
    def synthesize(spec : SynthesisSpec, migration_interval : Int32 = 10) : SynthesisResult
      # Setup all synthesizers
      @synthesizers.each do |s|
        s.setup_general(spec.input_types.size)
      end

      # Create fitness function
      inputs = spec.examples.map { |e| e[0] }
      outputs = spec.examples.map { |e| e[1] }
      fitness = SupervisedFitness.new(inputs, outputs)

      # Initialize populations
      @synthesizers.each do |s|
        s.init_population
        s.fitness_function = fitness
      end

      # Co-evolve
      @synthesizers.first.config.max_generations.times do |gen|
        # Evolve each population
        @synthesizers.each do |s|
          s.generation = gen
          s.step_evolution
        end

        # Migration
        if gen > 0 && gen % migration_interval == 0
          migrate
        end

        # Track overall best
        update_overall_best

        # Check for solution
        if @best_overall && @best_overall.not_nil!.fitness >= 0.99
          break
        end
      end

      if bp = @best_overall
        SynthesisResult.new(
          program: bp,
          fitness: bp.fitness,
          generations: @synthesizers.first.generation,
          evaluations: @synthesizers.sum(&.evaluations),
          success: bp.fitness >= 0.99
        )
      else
        SynthesisResult.new(error_message: "Co-evolution failed")
      end
    end

    private def migrate
      # Ring migration - send best from each to next
      bests = @synthesizers.map { |s| s.population.max_by(&.fitness).clone }

      @synthesizers.each_with_index do |s, i|
        # Replace worst with immigrant from previous population
        worst_idx = s.population.index(s.population.min_by(&.fitness))
        if worst_idx
          prev_idx = (i - 1) % @synthesizers.size
          s.population[worst_idx] = bests[prev_idx]
        end
      end
    end

    private def update_overall_best
      all_bests = @synthesizers.compact_map(&.best_program)
      return if all_bests.empty?

      current_best = all_bests.max_by(&.fitness)
      if @best_overall.nil? || current_best.fitness > @best_overall.not_nil!.fitness
        @best_overall = current_best.clone
      end
    end
  end
end
