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
