require "spec"
require "../../src/pattern_mining/pattern_mining_main"

describe "Pattern Mining Main" do
  describe "initialization" do
    it "initializes Pattern Mining system" do
      PatternMining.initialize
      # Should not crash
    end

    it "has correct version" do
      PatternMining::VERSION.should eq("0.1.0")
    end

    it "creates pattern miner" do
      atomspace = AtomSpace::AtomSpace.new
      miner = PatternMining.create_miner(atomspace)
      miner.should be_a(PatternMining::PatternMiner)
    end
  end

  describe "mining functionality" do
    it "provides mining utilities" do
      # Test that the mine method exists and works
      atomspace = AtomSpace::AtomSpace.new
      # Add some atoms to the atomspace
      atomspace.add_concept_node("test1")
      atomspace.add_concept_node("test2")
      
      # The mine method should exist and be callable
      result = PatternMining.mine(atomspace, min_support: 1, max_patterns: 10, timeout_seconds: 5)
      result.should be_a(PatternMining::MiningResult)
    end

    it "provides frequency analysis" do
      # Test that frequency analysis is available through MiningResult
      atomspace = AtomSpace::AtomSpace.new
      atomspace.add_concept_node("test1")
      atomspace.add_concept_node("test2")
      
      result = PatternMining.mine(atomspace, min_support: 1, max_patterns: 10, timeout_seconds: 5)
      # The result should have frequency analysis methods
      frequent = result.frequent_patterns(1)
      frequent.should_not be_nil
    end
  end

  describe "system integration" do
    it "integrates with AtomSpace" do
      CogUtil.initialize
      AtomSpace.initialize
      PatternMining.initialize

      # Should work with atomspace
      atomspace = AtomSpace.create_atomspace
      miner = PatternMining.create_miner(atomspace)
      miner.should_not be_nil
    end
  end
end
