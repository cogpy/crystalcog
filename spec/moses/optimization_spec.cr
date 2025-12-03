require "spec"
require "../../src/moses/moses_framework"

describe MOSES::Optimization do
  describe "optimization algorithms" do
    it "defines optimization interface" do
      MOSES::Optimizer.should be_truthy
    end

    it "provides genetic operations" do
      MOSES::GeneticOperations.should be_truthy
    end

    it "provides selection methods" do
      MOSES::Selection.should be_truthy
    end
  end

  describe "genetic operations" do
    it "performs crossover" do
      parent1 = MOSES::Program.new("x")
      parent2 = MOSES::Program.new("y")

      child = MOSES::GeneticOperations.crossover(parent1, parent2)
      child.should be_a(MOSES::Program)
    end

    it "performs mutation" do
      program = MOSES::Program.new("x")

      mutated = MOSES::GeneticOperations.mutate(program)
      mutated.should be_a(MOSES::Program)
    end
  end

  describe "selection methods" do
    it "performs tournament selection" do
      population = MOSES::Population.new

      # Add some individuals
      3.times do |i|
        program = MOSES::Program.new("x#{i}")
        individual = MOSES::Individual.new(program, i.to_f)
        population.add(individual)
      end

      selected = MOSES::Selection.tournament(population, 2)
      selected.should be_a(MOSES::Individual)
    end
  end
end
