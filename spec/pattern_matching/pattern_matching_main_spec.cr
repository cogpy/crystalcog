require "spec"
require "../../src/pattern_matching/pattern_matching_main"

describe "Pattern Matching Main" do
  describe "initialization" do
    it "initializes Pattern Matching system" do
      PatternMatching.initialize
      # Should not crash
    end

    it "has correct version" do
      PatternMatching::VERSION.should eq("0.1.0")
    end

    it "creates pattern matcher" do
      atomspace = AtomSpace::AtomSpace.new
      matcher = PatternMatching.create_matcher(atomspace)
      matcher.should be_a(PatternMatching::PatternMatcher)
    end
  end

  describe "main functionality" do
    it "provides pattern creation utilities" do
      atomspace = AtomSpace::AtomSpace.new
      concept = atomspace.add_concept_node("test")
      pattern = PatternMatching.create_pattern(concept)
      pattern.should be_a(PatternMatching::Pattern)
    end

    it "provides matching utilities" do
      atomspace = AtomSpace::AtomSpace.new
      concept = atomspace.add_concept_node("test")
      pattern = PatternMatching::Pattern.new(concept)
      results = PatternMatching.match_pattern(atomspace, pattern)
      results.should be_a(Array(PatternMatching::MatchResult))
    end
  end

  describe "system integration" do
    it "integrates with AtomSpace" do
      CogUtil.initialize
      AtomSpace.initialize
      PatternMatching.initialize

      # Should work with atomspace
      atomspace = AtomSpace.create_atomspace
      matcher = PatternMatching.create_matcher(atomspace)
      matcher.should_not be_nil
    end
  end
end
