require "spec"
require "../../src/moses/moses_framework"

describe MOSES::Deme do
  describe "initialization" do
    it "creates deme" do
      deme = MOSES::Deme.new
      deme.should_not be_nil
    end

    it "has default parameters" do
      deme = MOSES::Deme.new
      deme.max_size.should eq(100)
      deme.population.should be_empty
    end

    it "creates deme with custom size" do
      deme = MOSES::Deme.new(50)
      deme.max_size.should eq(50)
    end
  end

  describe "population management" do
    it "adds individuals to deme" do
      deme = MOSES::Deme.new
      program = MOSES::Program.new("x")
      individual = MOSES::Individual.new(program, 0.5)

      deme.add_individual(individual)
      deme.population.size.should eq(1)
      deme.population.first.should eq(individual)
    end

    it "respects size limits" do
      deme = MOSES::Deme.new(2)

      3.times do |i|
        program = MOSES::Program.new("x#{i}")
        individual = MOSES::Individual.new(program, i.to_f)
        deme.add_individual(individual)
      end

      # Should not exceed max size
      deme.population.size.should be <= 2
    end
  end

  describe "deme operations" do
    it "selects best individuals" do
      deme = MOSES::Deme.new

      # Add individuals with different fitness
      (1..5).each do |i|
        program = MOSES::Program.new("x#{i}")
        individual = MOSES::Individual.new(program, i.to_f)
        deme.add_individual(individual)
      end

      best = deme.select_best(2)
      best.size.should eq(2)
      best.first.fitness.should be >= best.last.fitness
    end

    it "evolves population" do
      deme = MOSES::Deme.new
      program = MOSES::Program.new("x")
      individual = MOSES::Individual.new(program, 0.5)
      deme.add_individual(individual)

      # Should be able to evolve
      deme.evolve_generation
      # Should not crash
    end
  end
end
