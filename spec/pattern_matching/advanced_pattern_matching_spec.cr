require "spec"
require "../../src/pattern_matching/pattern_matching_main"

describe PatternMatching::Advanced::RecursiveQueryComposer do
  it "registers patterns and composes AND" do
    atomspace = AtomSpace::AtomSpace.new
    dog = atomspace.add_concept_node("dog")
    animal = atomspace.add_concept_node("animal")
    atomspace.add_inheritance_link(dog, animal)

    composer = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)
    var_x = AtomSpace::VariableNode.new("$X")
    pattern = PatternMatching::Pattern.new(var_x)
    composer.register_pattern("any", pattern.template)

    # re-register properly
    composer2 = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)
    composer2.register_pattern("any", var_x)
    results = composer2.compose_or(["any"])
    results.should_not be_empty
  end

  it "raises on missing pattern for AND" do
    atomspace = AtomSpace::AtomSpace.new
    composer = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)
    expect_raises(PatternMatching::Advanced::PatternCompositionException) do
      composer.compose_and(["missing"])
    end
  end

  it "handles empty nested composition" do
    atomspace = AtomSpace::AtomSpace.new
    composer = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)
    composer.compose_nested("OR", [] of Array(String)).should be_empty
    composer.compose_nested("AND", [["missing"]]).should be_empty
  end

  it "caches composition results and can clear cache" do
    atomspace = AtomSpace::AtomSpace.new
    atomspace.add_concept_node("a")
    composer = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)
    var = AtomSpace::VariableNode.new("$V")
    composer.register_pattern("v", var)

    composer.compose_or(["v"])
    composer.cache_size.should be > 0
    composer.clear_cache
    composer.cache_size.should eq(0)
  end

  it "merges compatible bindings" do
    atomspace = AtomSpace::AtomSpace.new
    a = atomspace.add_concept_node("a")
    b = atomspace.add_concept_node("b")
    var_x = AtomSpace::VariableNode.new("$X")
    var_y = AtomSpace::VariableNode.new("$Y")

    bindings_a = PatternMatching::VariableBinding.new
    bindings_a[var_x] = a
    bindings_b = PatternMatching::VariableBinding.new
    bindings_b[var_y] = b

    r1 = PatternMatching::MatchResult.new(bindings_a, [a] of AtomSpace::Atom)
    r2 = PatternMatching::MatchResult.new(bindings_b, [b] of AtomSpace::Atom)

    composer = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)
    merged = composer.merge_compatible([r1], [r2])
    merged.size.should eq(1)
    merged.first.bindings.size.should eq(2)
  end

  it "rejects negative max_depth for recursive compose" do
    atomspace = AtomSpace::AtomSpace.new
    composer = PatternMatching::Advanced::RecursiveQueryComposer.new(atomspace)
    var = AtomSpace::VariableNode.new("$X")
    composer.register_pattern("x", var)
    expect_raises(PatternMatching::Advanced::PatternCompositionException) do
      composer.compose_recursive("x", -1)
    end
  end
end

describe PatternMatching::TemporalConstraint do
  it "enforces before relation using provided timestamps" do
    atomspace = AtomSpace::AtomSpace.new
    a = atomspace.add_concept_node("early")
    b = atomspace.add_concept_node("late")
    var_x = AtomSpace::VariableNode.new("$X")
    var_y = AtomSpace::VariableNode.new("$Y")

    timestamps = {
      a.handle => 100_i64,
      b.handle => 200_i64,
    } of AtomSpace::Handle => Int64

    constraint = PatternMatching::TemporalConstraint.new(
      var_x, var_y, PatternMatching::TemporalConstraint::Relation::Before, 0_i64, timestamps
    )

    bindings = PatternMatching::VariableBinding.new
    bindings[var_x] = a
    bindings[var_y] = b
    constraint.satisfied?(bindings, atomspace).should be_true

    bindings2 = PatternMatching::VariableBinding.new
    bindings2[var_x] = b
    bindings2[var_y] = a
    constraint.satisfied?(bindings2, atomspace).should be_false
  end

  it "enforces within window" do
    atomspace = AtomSpace::AtomSpace.new
    a = atomspace.add_concept_node("a")
    b = atomspace.add_concept_node("b")
    var_x = AtomSpace::VariableNode.new("$X")
    var_y = AtomSpace::VariableNode.new("$Y")
    timestamps = {a.handle => 100_i64, b.handle => 150_i64} of AtomSpace::Handle => Int64

    constraint = PatternMatching::TemporalConstraint.new(
      var_x, var_y, PatternMatching::TemporalConstraint::Relation::Within, 60_i64, timestamps
    )
    bindings = PatternMatching::VariableBinding.new
    bindings[var_x] = a
    bindings[var_y] = b
    constraint.satisfied?(bindings, atomspace).should be_true
  end
end

describe PatternMatching::FuzzyThresholdConstraint do
  it "accepts atoms above threshold" do
    atomspace = AtomSpace::AtomSpace.new
    node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "strong",
      AtomSpace::SimpleTruthValue.new(0.9, 0.8))
    var = AtomSpace::VariableNode.new("$X")
    constraint = PatternMatching::FuzzyThresholdConstraint.new(var, 0.5)
    bindings = PatternMatching::VariableBinding.new
    bindings[var] = node
    constraint.satisfied?(bindings, atomspace).should be_true
  end

  it "rejects atoms below threshold" do
    atomspace = AtomSpace::AtomSpace.new
    node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "weak",
      AtomSpace::SimpleTruthValue.new(0.2, 0.8))
    var = AtomSpace::VariableNode.new("$X")
    constraint = PatternMatching::FuzzyThresholdConstraint.new(var, 0.5)
    bindings = PatternMatching::VariableBinding.new
    bindings[var] = node
    constraint.satisfied?(bindings, atomspace).should be_false
  end

  it "rejects invalid thresholds" do
    var = AtomSpace::VariableNode.new("$X")
    expect_raises(PatternMatching::PatternMatchingException) do
      PatternMatching::FuzzyThresholdConstraint.new(var, 1.5)
    end
  end
end

describe PatternMatching::Advanced::PatternMatchCache do
  it "stores and fetches entries" do
    cache = PatternMatching::Advanced::PatternMatchCache.new(10, 60.0)
    results = [] of PatternMatching::MatchResult
    cache.store("k", results)
    cache.fetch("k").should_not be_nil
    cache.stats["hits"].should eq(1.0)
  end

  it "misses unknown keys" do
    cache = PatternMatching::Advanced::PatternMatchCache.new
    cache.fetch("nope").should be_nil
    cache.stats["misses"].should eq(1.0)
  end

  it "evicts when over capacity" do
    cache = PatternMatching::Advanced::PatternMatchCache.new(2, 60.0)
    empty = [] of PatternMatching::MatchResult
    cache.store("a", empty)
    cache.store("b", empty)
    cache.store("c", empty)
    cache.size.should eq(2)
  end
end

describe PatternMatching::Advanced::OptimizedPatternMatcher do
  it "caches match results" do
    atomspace = AtomSpace::AtomSpace.new
    atomspace.add_concept_node("dog")
    matcher = PatternMatching::Advanced::OptimizedPatternMatcher.new(atomspace)
    pattern = PatternMatching::Pattern.new(AtomSpace::VariableNode.new("$X"))

    r1 = matcher.match(pattern)
    r2 = matcher.match(pattern)
    r1.size.should eq(r2.size)
    matcher.cache_stats["hits"].should be >= 1.0
  end

  it "clears cache" do
    atomspace = AtomSpace::AtomSpace.new
    matcher = PatternMatching::Advanced::OptimizedPatternMatcher.new(atomspace)
    matcher.match(PatternMatching::Pattern.new(AtomSpace::VariableNode.new("$X")))
    matcher.clear_cache
    matcher.cache_stats["size"].should eq(0.0)
  end
end

describe PatternMatching::Advanced::StatisticalMatcher do
  it "performs fuzzy match with configurable threshold" do
    atomspace = AtomSpace::AtomSpace.new
    atomspace.add_concept_node("cat")
    stats = PatternMatching::Advanced::StatisticalMatcher.new(atomspace, 0.5)
    pattern = PatternMatching::Pattern.new(AtomSpace::VariableNode.new("$X"))
    results = stats.fuzzy_match(pattern, 0.5)
    results.should_not be_empty
  end
end
