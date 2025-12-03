require "spec"
require "../../src/moses/moses_main"

describe "MOSES Main" do
  describe "initialization" do
    it "initializes MOSES system" do
      MOSES.initialize
      # Should not crash
    end

    it "has correct version" do
      MOSES::VERSION.should eq("0.1.0")
    end

    it "creates MOSES optimizer" do
      optimizer = MOSES.create_optimizer
      optimizer.should be_a(MOSES::Optimizer)
    end
  end

  describe "optimization functionality" do
    it "provides evolutionary optimization" do
      MOSES.responds_to?(:optimize).should be_true
    end

    it "provides metapopulation management" do
      MOSES.responds_to?(:create_metapopulation).should be_true
    end

    it "provides scoring functions" do
      MOSES.responds_to?(:create_scorer).should be_true
    end
  end

  describe "system integration" do
    it "integrates with AtomSpace" do
      CogUtil.initialize
      AtomSpace.initialize
      MOSES.initialize

      # Should work with atomspace
      atomspace = AtomSpace.create_atomspace
      optimizer = MOSES.create_optimizer(atomspace)
      optimizer.should_not be_nil
    end
  end
end
