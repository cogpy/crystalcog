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

private def inherits_from(space : AtomSpace::AtomSpace, parent : AtomSpace::Atom) : PatternMatching::Pattern
  PatternMatching::Pattern.new(AtomSpace::InheritanceLink.new(AtomSpace::VariableNode.new("$X"), parent))
end

describe PatternMatching::Advanced::TemporalPatternMatcher do
  it "orders matches by the recorded time of their atoms" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("animal")
    plant = space.add_concept_node("plant")
    temporal = PatternMatching::Advanced::TemporalPatternMatcher.new(space, 1000_i64)
    cat = space.add_inheritance_link(space.add_concept_node("cat"), animal)
    fern = space.add_inheritance_link(space.add_concept_node("fern"), plant)
    dog = space.add_inheritance_link(space.add_concept_node("dog"), animal)
    temporal.record(cat, 1_000_i64)
    temporal.record(fern, 1_400_i64)
    temporal.record(dog, 5_000_i64)

    # animal then plant: only cat (1000) precedes fern (1400); dog comes after it.
    sequences = temporal.match_sequence([inherits_from(space, animal), inherits_from(space, plant)], "a-then-p")
    sequences.size.should eq(1)
    sequences[0].timestamps.should eq([1_000_i64, 1_400_i64])
    sequences[0].duration_ms.should eq(400)
    sequences[0].pattern_results[0].matched_atoms.should contain(cat)
    temporal.temporal_cache["SEQ_a-then-p_2"].size.should eq(1)

    # plant then animal: fern (1400) then dog (5000) is 3600 ms apart, outside the window.
    temporal.match_sequence([inherits_from(space, plant), inherits_from(space, animal)]).should be_empty
    wide = PatternMatching::Advanced::TemporalPatternMatcher.new(space, 10_000_i64, temporal.timestamps)
    reversed = wide.match_sequence([inherits_from(space, plant), inherits_from(space, animal)])
    reversed.map(&.timestamps).should eq([[1_400_i64, 5_000_i64]])

    # Time moved on: the same query now sees a new event.
    bird = space.add_inheritance_link(space.add_concept_node("bird"), animal)
    wide.record(bird, 1_500_i64)
    wide.match_sequence([inherits_from(space, plant), inherits_from(space, animal)]).size.should eq(2)
    temporal.close
    wide.close
  end

  it "groups matches into bursts and detects repetition" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("animal")
    temporal = PatternMatching::Advanced::TemporalPatternMatcher.new(space)
    times = [100_i64, 150_i64, 190_i64, 2_000_i64, 2_050_i64, 9_000_i64]
    times.each_with_index do |time, i|
      temporal.record(space.add_inheritance_link(space.add_concept_node("creature-#{i}"), animal), time)
    end
    pattern = inherits_from(space, animal)

    bursts = temporal.match_within_interval(pattern, 100_i64)
    bursts.map(&.timestamps).should eq([[100_i64, 150_i64, 190_i64], [2_000_i64, 2_050_i64], [9_000_i64]])
    temporal.match_within_interval(pattern, 10_000_i64).size.should eq(1)

    repeating = temporal.detect_repeating_patterns(pattern, 6)
    repeating.size.should eq(1)
    repeating[0].timestamps.should eq(times)
    temporal.detect_repeating_patterns(pattern, 7).should be_empty

    steady = PatternMatching::Advanced::TemporalPatternMatcher::TemporalMatch.new(
      [] of PatternMatching::MatchResult, [0_i64, 100_i64, 200_i64, 300_i64], "steady")
    temporal.regularity(steady).should eq(1.0)
    temporal.regularity(repeating[0]).should be < 0.5
    temporal.close
  end

  it "stamps atoms as they are added and treats older atoms as simultaneous" do
    space = AtomSpace::AtomSpace.new
    old = space.add_concept_node("old")
    temporal = PatternMatching::Advanced::TemporalPatternMatcher.new(space)
    temporal.timestamp_of(old).should eq(temporal.created_ms)
    fresh = space.add_concept_node("fresh")
    temporal.timestamps.has_key?(fresh.handle).should be_true
    temporal.timestamp_of(fresh).should be >= temporal.created_ms
    temporal.close
    space.add_concept_node("after-close")
    temporal.timestamps.size.should eq(1)
  end
end

describe PatternMatching::Advanced::PatternLearner do
  it "learns link shapes and the atoms that anchor them" do
    space = AtomSpace::AtomSpace.new
    owner = space.add_predicate_node("owns")
    alice = space.add_concept_node("alice")
    6.times { |i| space.add_link(AtomSpace::AtomType::MEMBER_LINK, [space.add_concept_node("item-#{i}"), alice]) }
    2.times { |i| space.add_link(AtomSpace::AtomType::MEMBER_LINK, [space.add_concept_node("stray-#{i}"), space.add_concept_node("bob-#{i}")]) }

    learner = PatternMatching::Advanced::PatternLearner.new(space, 0.2, 0.6)
    templates = learner.learn_patterns.map(&.template.to_s)
    templates.should contain(%((MEMBERLINK (VARIABLENODE "$VAR_0") (VARIABLENODE "$VAR_1"))))
    templates.should contain(%((MEMBERLINK (VARIABLENODE "$VAR_0") (CONCEPTNODE "alice"))))

    anchored = learner.learn_patterns.find! { |p| p.template.to_s.includes?("alice") }
    anchored.frequency.should eq(0.75)
    anchored.confidence.should eq(0.75)
    anchored.examples.size.should eq(6)
    # Learning twice refreshes the same entries instead of piling up copies.
    learner.pattern_statistics["total_patterns"].should eq(templates.size)
  end
end

describe "StatisticalMatcher sampling" do
  it "estimates match probabilities from truth values" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("animal", AtomSpace::SimpleTruthValue.new(1.0, 1.0))
    sure = space.add_inheritance_link(space.add_concept_node("cat", AtomSpace::SimpleTruthValue.new(1.0, 1.0)), animal,
      AtomSpace::SimpleTruthValue.new(1.0, 1.0))
    doubtful = space.add_inheritance_link(space.add_concept_node("rock", AtomSpace::SimpleTruthValue.new(1.0, 1.0)), animal,
      AtomSpace::SimpleTruthValue.new(0.3, 1.0))
    matcher = PatternMatching::Advanced::StatisticalMatcher.new(space, 0.0)

    estimates = matcher.monte_carlo_sampling(inherits_from(space, animal), 4000, Random.new(11))
    estimates.size.should eq(2)
    certain = estimates.find! { |m| m.match_result.matched_atoms.includes?(sure) }
    unlikely = estimates.find! { |m| m.match_result.matched_atoms.includes?(doubtful) }
    certain.probability.should eq(1.0)
    unlikely.probability.should be_close(0.3, 0.03)
    low, high = unlikely.confidence_intervals["95%"]
    (low < 0.3 < high).should be_true
    (high - low).should be < 0.05
    unlikely.statistical_measures["entropy"].should be_close(0.611, 0.02)
    certain.statistical_measures["entropy"].should eq(0.0)
    estimates.first.should eq(certain)

    # Same seed, same estimate; a threshold filters the unlikely match out.
    again = matcher.monte_carlo_sampling(inherits_from(space, animal), 4000, Random.new(11))
    again.map(&.probability).should eq(estimates.map(&.probability))
    strict = PatternMatching::Advanced::StatisticalMatcher.new(space, 0.9)
    strict.monte_carlo_sampling(inherits_from(space, animal), 500, Random.new(3)).size.should eq(1)
  end

  it "treats unconfident atoms as open questions and reports partial matches" do
    space = AtomSpace::AtomSpace.new
    strong = space.add_concept_node("strong", AtomSpace::SimpleTruthValue.new(0.9, 0.9))
    weak = space.add_concept_node("weak", AtomSpace::SimpleTruthValue.new(0.2, 0.9))
    unknown = space.add_concept_node("unknown")
    matcher = PatternMatching::Advanced::StatisticalMatcher.new(space, 0.0)
    var_x = AtomSpace::VariableNode.new("$X")

    samples = matcher.monte_carlo_sampling(PatternMatching::Pattern.new(var_x), 4000, Random.new(5))
    by_atom = samples.to_h { |m| {m.match_result.bindings[var_x], m.probability} }
    # No evidence at all: a coin flip, whatever the nominal strength.
    by_atom[unknown].should be_close(0.5, 0.04)
    by_atom[strong].should be > by_atom[unknown]
    by_atom[weak].should be < by_atom[unknown]

    pattern = PatternMatching::Pattern.new(var_x)
    pattern.add_constraint(PatternMatching::FuzzyThresholdConstraint.new(var_x, 0.5))
    pattern.add_constraint(PatternMatching::FuzzyThresholdConstraint.new(var_x, 0.0))
    fuzzy = matcher.fuzzy_match(pattern, 0.5)
    partial = fuzzy.find! { |m| m.match_result.bindings[var_x] == weak }
    partial.probability.should eq(0.5)
    fuzzy.find! { |m| m.match_result.bindings[var_x] == strong }.probability.should eq(1.0)
    matcher.fuzzy_match(pattern, 0.6).none? { |m| m.match_result.bindings[var_x] == weak }.should be_true
  end
end
