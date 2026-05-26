# Genetic Programming Main Module
#
# This module provides the main interface for the Genetic Programming
# subsystem in CrystalCog, integrating with AtomSpace and other
# cognitive components.
#
# Features:
# - Program tree representation using AST nodes
# - Genetic operators: crossover, mutation, selection
# - Multiple fitness evaluation strategies
# - Program synthesis from examples
# - AtomSpace integration for knowledge-guided evolution
# - MOSES-compatible interface

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./program_tree"
require "./operators"
require "./fitness"
require "./synthesis"

module GeneticProgramming
  VERSION = "0.1.0"

  # Initialize the Genetic Programming subsystem
  def self.initialize
    CogUtil::Logger.info("GeneticProgramming #{VERSION} initializing")
    CogUtil.initialize
    AtomSpace.initialize
    CogUtil::Logger.info("GeneticProgramming #{VERSION} initialized")
  end

  # Quick synthesis API - synthesize a boolean function from examples
  def self.synthesize_boolean(inputs : Array(Array(Bool)),
                               outputs : Array(Bool),
                               config : GPConfig = GPConfig.new) : SynthesisResult
    if inputs.empty?
      return SynthesisResult.new(error_message: "No input examples provided")
    end

    num_vars = inputs.first.size
    synth = BooleanSynthesizer.new(num_vars, config)
    synth.synthesize_from_truth_table(
      inputs.zip(outputs).to_h
    )
  end

  # Quick synthesis API - synthesize a regression function from data
  def self.synthesize_regression(x_data : Array(Array(Float64)),
                                  y_data : Array(Float64),
                                  config : GPConfig = GPConfig.new) : SynthesisResult
    if x_data.empty?
      return SynthesisResult.new(error_message: "No data points provided")
    end

    num_vars = x_data.first.size
    synth = SymbolicRegressionSynthesizer.new(num_vars, config)
    synth.synthesize_from_data(x_data, y_data)
  end

  # Quick synthesis API - general purpose synthesis from specification
  def self.synthesize(spec : SynthesisSpec,
                       config : GPConfig = GPConfig.new) : SynthesisResult
    synth = ProgramSynthesizer.new(config)
    synth.synthesize(spec)
  end

  # Create a default configuration optimized for quick results
  def self.quick_config : GPConfig
    GPConfig.new(
      population_size: 50,
      max_generations: 20,
      max_depth: 5,
      max_size: 50,
      tournament_size: 3,
      crossover_rate: 0.9,
      mutation_rate: 0.1,
      elitism_count: 1
    )
  end

  # Create a configuration optimized for accuracy
  def self.accurate_config : GPConfig
    GPConfig.new(
      population_size: 200,
      max_generations: 100,
      max_depth: 8,
      max_size: 150,
      tournament_size: 7,
      crossover_rate: 0.8,
      mutation_rate: 0.15,
      elitism_count: 5,
      parsimony_coefficient: 0.0005
    )
  end

  # Create a configuration optimized for simplicity (smaller programs)
  def self.simple_config : GPConfig
    GPConfig.new(
      population_size: 100,
      max_generations: 50,
      max_depth: 4,
      max_size: 30,
      tournament_size: 5,
      crossover_rate: 0.7,
      mutation_rate: 0.2,
      elitism_count: 2,
      parsimony_coefficient: 0.01
    )
  end

  # Convenience method to create a function set for boolean problems
  def self.boolean_function_set(num_variables : Int32) : FunctionSet
    FunctionSet.new(num_variables)
      .add_boolean_functions
      .add_comparison_functions
  end

  # Convenience method to create a function set for regression problems
  def self.regression_function_set(num_variables : Int32) : FunctionSet
    FunctionSet.new(num_variables)
      .add_arithmetic_functions
      .add_math_functions
  end

  # Convenience method to create a full function set
  def self.full_function_set(num_variables : Int32) : FunctionSet
    FunctionSet.new(num_variables)
      .add_boolean_functions
      .add_arithmetic_functions
      .add_comparison_functions
      .add_math_functions
      .add_control_flow
  end

  # Integration with MOSES - convert GP result to MOSES-compatible format
  def self.to_moses_result(result : SynthesisResult) : Hash(String, String | Float64 | Int32 | Bool)
    {
      "success"     => result.success,
      "program"     => result.program.try(&.to_s) || "",
      "fitness"     => result.fitness,
      "generations" => result.generations,
      "evaluations" => result.evaluations,
      "error"       => result.error_message || "",
    }
  end

  # Store synthesis result in AtomSpace
  def self.store_result(result : SynthesisResult,
                         atomspace : AtomSpace::AtomSpace,
                         name : String = "synthesized_program") : AtomSpace::Atom?
    return nil unless result.success && result.program

    program = result.program.not_nil!

    # Create program concept
    program_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, name)

    # Store expression
    expr_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, program.to_s)
    expr_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "has_expression")
    expr_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [program_node, expr_node])
    atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [expr_pred, expr_list])

    # Store fitness
    fitness_node = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, result.fitness.to_s)
    fitness_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "has_fitness")
    fitness_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [program_node, fitness_node])
    atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [fitness_pred, fitness_list])

    # Store complexity
    complexity_node = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, program.size.to_s)
    complexity_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "has_complexity")
    complexity_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [program_node, complexity_node])
    atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [complexity_pred, complexity_list])

    # Store tree representation
    program.to_atomspace(atomspace)

    program_node
  end

  # Benchmark utilities
  module Benchmarks
    # Standard GP benchmarks

    # Even parity problem
    def self.even_parity(n : Int32) : Tuple(Array(Array(Bool)), Array(Bool))
      inputs = [] of Array(Bool)
      outputs = [] of Bool

      (0...(2 ** n)).each do |i|
        bits = (0...n).map { |j| ((i >> j) & 1) == 1 }
        inputs << bits
        outputs << (bits.count(true) % 2 == 0)
      end

      {inputs, outputs}
    end

    # Multiplexer problem (6-bit: 2 address + 4 data)
    def self.multiplexer_6 : Tuple(Array(Array(Bool)), Array(Bool))
      inputs = [] of Array(Bool)
      outputs = [] of Bool

      (0...64).each do |i|
        bits = (0...6).map { |j| ((i >> j) & 1) == 1 }
        # First 2 bits are address, last 4 are data
        addr = (bits[0] ? 1 : 0) + (bits[1] ? 2 : 0)
        data = bits[2 + addr]
        inputs << bits
        outputs << data
      end

      {inputs, outputs}
    end

    # Symbolic regression: x^2 + x + 1
    def self.polynomial_regression(n_samples : Int32 = 20) : Tuple(Array(Array(Float64)), Array(Float64))
      inputs = [] of Array(Float64)
      outputs = [] of Float64

      n_samples.times do
        x = Random.rand(-10.0..10.0)
        inputs << [x]
        outputs << (x ** 2 + x + 1)
      end

      {inputs, outputs}
    end

    # Symbolic regression: sin(x)
    def self.sine_regression(n_samples : Int32 = 50) : Tuple(Array(Array(Float64)), Array(Float64))
      inputs = [] of Array(Float64)
      outputs = [] of Float64

      n_samples.times do |i|
        x = -Math::PI + (2 * Math::PI * i / n_samples)
        inputs << [x]
        outputs << Math.sin(x)
      end

      {inputs, outputs}
    end

    # Two-variable regression: x*y + x - y
    def self.two_var_regression(n_samples : Int32 = 50) : Tuple(Array(Array(Float64)), Array(Float64))
      inputs = [] of Array(Float64)
      outputs = [] of Float64

      n_samples.times do
        x = Random.rand(-5.0..5.0)
        y = Random.rand(-5.0..5.0)
        inputs << [x, y]
        outputs << (x * y + x - y)
      end

      {inputs, outputs}
    end
  end
end

# Main entry point for standalone execution
if PROGRAM_NAME.includes?("genetic_programming")
  GeneticProgramming.initialize

  puts "=" * 60
  puts "CrystalCog Genetic Programming Module v#{GeneticProgramming::VERSION}"
  puts "=" * 60

  # Demo: Boolean synthesis (3-input XOR)
  puts "\n--- Boolean Synthesis Demo: 3-input XOR ---"
  inputs, outputs = GeneticProgramming::Benchmarks.even_parity(3)

  result = GeneticProgramming.synthesize_boolean(
    inputs, outputs,
    GeneticProgramming.quick_config
  )

  if result.success
    puts "✓ Found solution: #{result.program}"
    puts "  Fitness: #{result.fitness.round(4)}"
    puts "  Generations: #{result.generations}"
    puts "  Evaluations: #{result.evaluations}"
  else
    puts "✗ Synthesis failed: #{result.error_message}"
  end

  # Demo: Symbolic regression
  puts "\n--- Symbolic Regression Demo: f(x) = x² + x + 1 ---"
  x_data, y_data = GeneticProgramming::Benchmarks.polynomial_regression(20)

  result = GeneticProgramming.synthesize_regression(
    x_data, y_data,
    GeneticProgramming.quick_config
  )

  if result.success
    puts "✓ Found solution: #{result.program}"
    puts "  Fitness: #{result.fitness.round(4)}"
    puts "  Size: #{result.program.try(&.size)}"
  else
    puts "✗ Synthesis failed: #{result.error_message}"
  end

  puts "\n" + "=" * 60
  puts "Genetic Programming module demonstration complete."
end
