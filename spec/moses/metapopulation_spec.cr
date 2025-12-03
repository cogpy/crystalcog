require "spec"
require "../../src/moses/moses_framework"

describe MOSES::Metapopulation do
  describe "initialization" do
    it "creates metapopulation" do
      metapop = MOSES::Metapopulation.new
      metapop.should_not be_nil
    end

    it "has default parameters" do
      metapop = MOSES::Metapopulation.new
      metapop.max_populations.should eq(10)
      metapop.populations.should be_empty
    end
  end

  describe "population management" do
    it "adds populations" do
      metapop = MOSES::Metapopulation.new
      population = MOSES::Population.new

      metapop.add_population(population)
      metapop.populations.size.should eq(1)
    end

    it "manages multiple populations" do
      metapop = MOSES::Metapopulation.new

      3.times do |i|
        population = MOSES::Population.new
        metapop.add_population(population)
      end

      metapop.populations.size.should eq(3)
    end
  end

  describe "evolution operations" do
    it "performs evolution step" do
      metapop = MOSES::Metapopulation.new
      population = MOSES::Population.new
      metapop.add_population(population)

      # Should be able to evolve
      metapop.evolve_step
      # Should not crash
    end
  end
end
