# Genetic Operators for Genetic Programming
#
# This module implements the core genetic operators used in evolutionary
# program synthesis: crossover, mutation, and selection.
#
# References:
# - A Field Guide to Genetic Programming (Poli, Langdon, McPhee)
# - MOSES integration for hybrid evolutionary search

require "./program_tree"

module GeneticProgramming
  # Configuration for genetic operators
  struct GPConfig
    property population_size : Int32
    property max_generations : Int32
    property max_depth : Int32
    property max_size : Int32
    property tournament_size : Int32
    property crossover_rate : Float64
    property mutation_rate : Float64
    property reproduction_rate : Float64
    property elitism_count : Int32
    property parsimony_coefficient : Float64

    def initialize(
      @population_size : Int32 = 100,
      @max_generations : Int32 = 50,
      @max_depth : Int32 = 6,
      @max_size : Int32 = 100,
      @tournament_size : Int32 = 5,
      @crossover_rate : Float64 = 0.8,
      @mutation_rate : Float64 = 0.1,
      @reproduction_rate : Float64 = 0.1,
      @elitism_count : Int32 = 2,
      @parsimony_coefficient : Float64 = 0.001
    )
    end
  end

  # Program tree generator for creating initial random programs
  class TreeGenerator
    getter function_set : FunctionSet
    getter max_depth : Int32

    def initialize(@function_set : FunctionSet, @max_depth : Int32 = 6)
    end

    # Generate a random program tree using the "grow" method
    # Trees can have varying shapes and depths
    def grow(current_depth : Int32 = 0) : ProgramNode
      # At max depth, only terminals are allowed
      if current_depth >= @max_depth
        return @function_set.random_terminal
      end

      # With some probability, choose terminal (to create shorter trees)
      if @function_set.functions.empty? || (current_depth > 0 && Random.rand < 0.3)
        return @function_set.random_terminal
      end

      # Choose a function and generate children
      node = @function_set.random_function
      arity = node.expected_arity
      arity = 2 if arity < 0 # Default for variable arity

      arity.times do
        child = grow(current_depth + 1)
        node.add_child(child)
      end

      node
    end

    # Generate a random program tree using the "full" method
    # All branches reach the maximum depth
    def full(current_depth : Int32 = 0) : ProgramNode
      if current_depth >= @max_depth || @function_set.functions.empty?
        return @function_set.random_terminal
      end

      # Always choose function until max depth
      node = @function_set.random_function
      arity = node.expected_arity
      arity = 2 if arity < 0

      arity.times do
        child = full(current_depth + 1)
        node.add_child(child)
      end

      node
    end

    # Generate using "ramped half-and-half" method
    # Half use grow, half use full, across different depth limits
    def ramped_half_and_half : ProgramNode
      if Random.rand < 0.5
        grow
      else
        full
      end
    end

    # Generate a complete program
    def generate_program : Program
      Program.new(ramped_half_and_half)
    end

    # Generate initial population
    def generate_population(size : Int32) : Array(Program)
      programs = [] of Program
      size.times do
        programs << generate_program
      end
      programs
    end
  end

  # Crossover operator
  class Crossover
    property max_depth : Int32
    property max_size : Int32

    def initialize(@max_depth : Int32 = 10, @max_size : Int32 = 100)
    end

    # Standard subtree crossover
    # Selects a random subtree from each parent and swaps them
    def subtree_crossover(parent1 : Program, parent2 : Program) : Tuple(Program, Program)
      # Clone parents
      child1 = parent1.clone
      child2 = parent2.clone

      # Select random crossover points
      nodes1 = child1.all_nodes
      nodes2 = child2.all_nodes

      return {child1, child2} if nodes1.empty? || nodes2.empty?

      point1 = nodes1.sample
      point2 = nodes2.sample

      # Swap subtrees
      subtree1 = point1.clone
      subtree2 = point2.clone

      child1.replace_subtree(point1, subtree2)
      child2.replace_subtree(point2, subtree1)

      # Check depth constraints
      if child1.depth > @max_depth || child1.size > @max_size
        child1 = parent1.clone
      end
      if child2.depth > @max_depth || child2.size > @max_size
        child2 = parent2.clone
      end

      {child1, child2}
    end

    # One-point crossover (at matching structural points)
    def one_point_crossover(parent1 : Program, parent2 : Program) : Tuple(Program, Program)
      # For simplicity, fall back to subtree crossover
      subtree_crossover(parent1, parent2)
    end

    # Context-preserving crossover
    # Tries to swap subtrees of the same type
    def context_preserving_crossover(parent1 : Program, parent2 : Program) : Tuple(Program, Program)
      child1 = parent1.clone
      child2 = parent2.clone

      nodes1 = child1.all_nodes
      nodes2 = child2.all_nodes

      # Group nodes by return type
      by_type1 = nodes1.group_by(&.return_type)
      by_type2 = nodes2.group_by(&.return_type)

      # Find common types
      common_types = by_type1.keys & by_type2.keys

      return {child1, child2} if common_types.empty?

      # Choose a common type
      target_type = common_types.sample

      points1 = by_type1[target_type]? || [] of ProgramNode
      points2 = by_type2[target_type]? || [] of ProgramNode

      return {child1, child2} if points1.empty? || points2.empty?

      point1 = points1.sample
      point2 = points2.sample

      subtree1 = point1.clone
      subtree2 = point2.clone

      child1.replace_subtree(point1, subtree2)
      child2.replace_subtree(point2, subtree1)

      # Validate constraints
      if child1.depth > @max_depth || child1.size > @max_size
        child1 = parent1.clone
      end
      if child2.depth > @max_depth || child2.size > @max_size
        child2 = parent2.clone
      end

      {child1, child2}
    end
  end

  # Mutation operator
  class Mutation
    getter function_set : FunctionSet
    property max_depth : Int32
    property max_size : Int32

    def initialize(@function_set : FunctionSet, @max_depth : Int32 = 10, @max_size : Int32 = 100)
    end

    # Subtree mutation: replace a random subtree with a new random tree
    def subtree_mutation(program : Program) : Program
      mutant = program.clone
      nodes = mutant.all_nodes

      return mutant if nodes.empty?

      # Select random point
      point = nodes.sample

      # Calculate remaining depth budget
      parent = mutant.find_parent(point)
      current_depth = 0
      temp = parent
      while temp
        current_depth += 1
        temp = mutant.find_parent(temp)
      end
      remaining_depth = @max_depth - current_depth

      # Generate new subtree
      generator = TreeGenerator.new(@function_set, remaining_depth.clamp(1, 4))
      new_subtree = generator.grow

      # Replace
      mutant.replace_subtree(point, new_subtree)

      # Validate
      if mutant.depth > @max_depth || mutant.size > @max_size
        return program.clone
      end

      mutant
    end

    # Point mutation: change a single node
    def point_mutation(program : Program) : Program
      mutant = program.clone
      nodes = mutant.all_nodes

      return mutant if nodes.empty?

      node = nodes.sample

      if node.terminal?
        # Mutate terminal
        if node.node_type.variable?
          # Change variable index
          new_index = Random.rand(@function_set.num_variables)
          node.variable_index = new_index
        else
          # Generate new random constant
          range = @function_set.constant_range
          node.value = Random.rand(range[1] - range[0]) + range[0]
        end
      else
        # Mutate function - change to another function with same arity
        current_arity = node.expected_arity
        same_arity = @function_set.functions.select do |f|
          ProgramNode.new(f).expected_arity == current_arity
        end

        if !same_arity.empty? && same_arity.size > 1
          # Remove current type
          same_arity = same_arity.reject { |f| f == node.node_type }
          if !same_arity.empty?
            new_node = ProgramNode.new(same_arity.sample, node.return_type)
            node.children.each { |c| new_node.add_child(c) }

            parent = mutant.find_parent(node)
            if parent
              idx = parent.children.index(node)
              if idx
                parent.replace_child(idx, new_node)
              end
            else
              # It's the root
              mutant = Program.new(new_node)
              new_node.children.clear
              node.children.each { |c| new_node.add_child(c) }
            end
          end
        end
      end

      mutant
    end

    # Hoist mutation: replace program with one of its subtrees
    def hoist_mutation(program : Program) : Program
      nodes = program.all_nodes.select(&.function?)

      return program.clone if nodes.empty?

      # Select a function node to hoist
      new_root = nodes.sample.clone
      Program.new(new_root)
    end

    # Shrink mutation: replace a subtree with a terminal
    def shrink_mutation(program : Program) : Program
      mutant = program.clone
      nodes = mutant.all_nodes.select(&.function?)

      return mutant if nodes.empty?

      # Select a function node to shrink
      point = nodes.sample
      new_terminal = @function_set.random_terminal

      mutant.replace_subtree(point, new_terminal)
      mutant
    end

    # Combined mutation - randomly choose mutation type
    def mutate(program : Program) : Program
      case Random.rand
      when 0.0..0.4
        subtree_mutation(program)
      when 0.4..0.7
        point_mutation(program)
      when 0.7..0.85
        hoist_mutation(program)
      else
        shrink_mutation(program)
      end
    end
  end

  # Selection operator
  class Selection
    property tournament_size : Int32

    def initialize(@tournament_size : Int32 = 5)
    end

    # Tournament selection
    def tournament_select(population : Array(Program)) : Program
      tournament = population.sample(@tournament_size)
      tournament.max_by(&.fitness)
    end

    # Fitness proportionate selection (roulette wheel)
    def roulette_select(population : Array(Program)) : Program
      total_fitness = population.sum(&.fitness)

      if total_fitness <= 0
        return population.sample
      end

      # Normalize fitness values
      target = Random.rand * total_fitness
      cumulative = 0.0

      population.each do |program|
        cumulative += program.fitness
        return program if cumulative >= target
      end

      population.last
    end

    # Rank-based selection
    def rank_select(population : Array(Program)) : Program
      # Sort by fitness (worst to best)
      sorted = population.sort_by(&.fitness)

      # Assign ranks (1 to N)
      total_ranks = (1..sorted.size).sum

      target = Random.rand * total_ranks
      cumulative = 0

      sorted.each_with_index do |program, i|
        cumulative += (i + 1)
        return program if cumulative >= target
      end

      sorted.last
    end

    # Select best individuals (for elitism)
    def select_elite(population : Array(Program), count : Int32) : Array(Program)
      population.sort_by { |p| -p.fitness }.first(count).map(&.clone)
    end

    # Select parents for reproduction
    def select_parents(population : Array(Program), count : Int32) : Array(Program)
      (0...count).map { tournament_select(population) }
    end
  end

  # Bloat control mechanisms
  module BloatControl
    # Apply parsimony pressure (penalize larger programs)
    def self.apply_parsimony(program : Program, raw_fitness : Float64, coefficient : Float64) : Float64
      raw_fitness - coefficient * program.size
    end

    # Dynamic depth limit
    def self.adjust_max_depth(population : Array(Program), base_depth : Int32) : Int32
      avg_depth = population.sum(&.depth) / population.size.to_f
      (base_depth + (avg_depth / 2).to_i).clamp(3, 15)
    end

    # Check if program violates constraints
    def self.exceeds_limits?(program : Program, max_depth : Int32, max_size : Int32) : Bool
      program.depth > max_depth || program.size > max_size
    end
  end

  # Population diversity measures
  module Diversity
    # Measure structural diversity based on tree shape
    def self.structural_diversity(population : Array(Program)) : Float64
      return 0.0 if population.empty?

      # Count unique tree sizes
      sizes = population.map(&.size).uniq
      sizes.size.to_f / population.size
    end

    # Measure behavioral diversity based on outputs
    def self.behavioral_diversity(population : Array(Program), test_cases : Array(Array(Float64 | Bool))) : Float64
      return 0.0 if population.empty? || test_cases.empty?

      outputs = population.map do |program|
        test_cases.map do |tc|
          begin
            program.evaluate(tc)
          rescue
            0.0
          end
        end
      end

      unique_outputs = outputs.uniq.size
      unique_outputs.to_f / population.size
    end

    # Calculate fitness sharing (to promote diversity)
    def self.apply_fitness_sharing(population : Array(Program), sigma : Float64 = 5.0)
      population.each do |prog1|
        niche_count = 0.0
        population.each do |prog2|
          distance = (prog1.size - prog2.size).abs.to_f
          if distance < sigma
            niche_count += 1.0 - (distance / sigma)
          end
        end
        prog1.fitness = prog1.fitness / niche_count if niche_count > 0
      end
    end
  end
end
