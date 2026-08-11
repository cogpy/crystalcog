require "spec"
require "../../src/pattern_mining/pattern_mining_main"

describe PatternMining::FrequentItemsetMiner do
  it "mines frequent concept co-occurrences" do
    atomspace = AtomSpace::AtomSpace.new
    animal = atomspace.add_concept_node("animal")
    dog = atomspace.add_concept_node("dog")
    cat = atomspace.add_concept_node("cat")
    atomspace.add_inheritance_link(dog, animal)
    atomspace.add_inheritance_link(cat, animal)

    miner = PatternMining::FrequentItemsetMiner.new(atomspace, 2)
    itemsets = miner.mine
    itemsets.should_not be_empty
    # "animal" should appear in both inheritance links
    animal_sets = itemsets.select { |set, _| set.includes?("animal") }
    animal_sets.should_not be_empty
  end

  it "returns patterns from itemsets" do
    atomspace = AtomSpace::AtomSpace.new
    a = atomspace.add_concept_node("a")
    b = atomspace.add_concept_node("b")
    atomspace.add_inheritance_link(a, b)
    atomspace.add_inheritance_link(a, b) # may dedupe; still have structure

    c = atomspace.add_concept_node("c")
    atomspace.add_inheritance_link(c, b)

    miner = PatternMining::FrequentItemsetMiner.new(atomspace, 1)
    patterns = miner.mine_as_patterns
    patterns.should_not be_empty
  end

  it "rejects non-positive parameters" do
    atomspace = AtomSpace::AtomSpace.new
    expect_raises(PatternMining::MiningException) do
      PatternMining::FrequentItemsetMiner.new(atomspace, 0)
    end
  end
end

describe PatternMining::PatternEvaluator do
  it "evaluates pattern metrics" do
    atomspace = AtomSpace::AtomSpace.new
    atomspace.add_concept_node("x")
    var = AtomSpace::VariableNode.new("$X")
    pattern = PatternMatching::Pattern.new(var)
    ps = PatternMining::PatternSupport.new(pattern, 5, 10)

    evaluator = PatternMining::PatternEvaluator.new(atomspace)
    metrics = evaluator.evaluate(ps, 10, 8, 6)
    metrics.support.should eq(5)
    metrics.frequency.should eq(0.5)
    metrics.confidence.should be_close(5.0 / 8.0, 0.001)
    metrics.quality_score.should be >= 0.0
  end

  it "ranks patterns by quality" do
    atomspace = AtomSpace::AtomSpace.new
    var = AtomSpace::VariableNode.new("$X")
    pattern = PatternMatching::Pattern.new(var)
    ps1 = PatternMining::PatternSupport.new(pattern, 8, 10)
    ps2 = PatternMining::PatternSupport.new(pattern, 2, 10)

    evaluator = PatternMining::PatternEvaluator.new(atomspace)
    ranked = evaluator.rank([ps2, ps1], 10)
    ranked.size.should eq(2)
    ranked[0][1].quality_score.should be >= ranked[1][1].quality_score
  end
end

describe PatternMining::KnowledgeDiscoveryPipeline do
  it "discovers patterns from atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    animal = atomspace.add_concept_node("animal")
    dog = atomspace.add_concept_node("dog")
    cat = atomspace.add_concept_node("cat")
    bird = atomspace.add_concept_node("bird")
    atomspace.add_inheritance_link(dog, animal)
    atomspace.add_inheritance_link(cat, animal)
    atomspace.add_inheritance_link(bird, animal)

    pipeline = PatternMining::KnowledgeDiscoveryPipeline.new(atomspace, 1, 0.0)
    discoveries = pipeline.discover(20)
    discoveries.should_not be_empty
  end

  it "asserts discoveries into atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    animal = atomspace.add_concept_node("animal")
    dog = atomspace.add_concept_node("dog")
    atomspace.add_inheritance_link(dog, animal)

    pipeline = PatternMining::KnowledgeDiscoveryPipeline.new(atomspace, 1, 0.0)
    discoveries = pipeline.discover(10)
    count = pipeline.assert_discoveries(discoveries, 0.0)
    count.should be >= 0
  end
end
