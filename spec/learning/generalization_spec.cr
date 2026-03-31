require "spec"
require "../../src/learning/generalization"

describe Learning::Generalization do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe "Rule" do
    it "creates a rule with antecedent and consequent" do
      rule = Learning::Generalization::Rule.new(["A", "B"], "C")
      rule.antecedent.should eq(["A", "B"])
      rule.consequent.should eq("C")
      rule.support.should eq(0)
      rule.confidence.should eq(0.0)
    end

    it "creates a rule with support and confidence" do
      rule = Learning::Generalization::Rule.new(["A"], "B", 10, 0.8)
      rule.support.should eq(10)
      rule.confidence.should eq(0.8)
    end

    it "converts to string representation" do
      rule = Learning::Generalization::Rule.new(["X", "Y"], "Z", 5, 0.75)
      rule.to_s.should contain("X AND Y")
      rule.to_s.should contain("Z")
      rule.to_s.should contain("0.75")
    end

    it "converts rule to AtomSpace representation" do
      atomspace = AtomSpace::AtomSpace.new
      rule = Learning::Generalization::Rule.new(["has_wings"], "is_bird", 3, 0.9)

      atom = rule.to_atomspace(atomspace)
      atom.should be_a(AtomSpace::Atom)
      atom.type.should eq(AtomSpace::AtomType::IMPLICATION_LINK)
    end
  end

  describe "AntiUnification" do
    it "returns single example unchanged" do
      result = Learning::Generalization::AntiUnification.generalize(["hello world"])
      result.should eq("hello world")
    end

    it "finds common pattern in two sentences" do
      result = Learning::Generalization::AntiUnification.generalize([
        "the cat sat",
        "the dog sat",
      ])
      # Common words: "the" and "sat"; differing: "cat"/"dog"
      result.should contain("the")
      result.should contain("sat")
      result.should contain("?")
    end

    it "generalizes multiple examples" do
      examples = [
        "birds can fly",
        "birds can swim",
        "birds can run",
      ]
      result = Learning::Generalization::AntiUnification.generalize(examples)
      result.should contain("birds")
      result.should contain("can")
    end
  end

  describe "AssociationRuleMiner" do
    it "creates miner with default thresholds" do
      miner = Learning::Generalization::AssociationRuleMiner.new
      miner.min_support.should eq(0.3)
      miner.min_confidence.should eq(0.7)
    end

    it "creates miner with custom thresholds" do
      miner = Learning::Generalization::AssociationRuleMiner.new(0.5, 0.8)
      miner.min_support.should eq(0.5)
      miner.min_confidence.should eq(0.8)
    end

    it "mines association rules from transactions" do
      transactions = [
        ["bread", "milk", "butter"],
        ["bread", "milk"],
        ["bread", "butter"],
        ["milk", "butter"],
        ["bread", "milk", "butter"],
      ]

      miner = Learning::Generalization::AssociationRuleMiner.new(0.5, 0.6)
      rules = miner.mine_rules(transactions)

      # Should find some rules given the frequent items
      rules.should be_a(Array(Learning::Generalization::Rule))
    end

    it "returns no rules when support threshold is too high" do
      transactions = [
        ["apple", "banana"],
        ["cherry", "date"],
      ]

      miner = Learning::Generalization::AssociationRuleMiner.new(1.0, 1.0)
      rules = miner.mine_rules(transactions)
      rules.should be_empty
    end

    it "produces rules with valid confidence scores" do
      transactions = [
        ["a", "b"],
        ["a", "b"],
        ["a", "b"],
        ["a", "c"],
      ]

      miner = Learning::Generalization::AssociationRuleMiner.new(0.3, 0.5)
      rules = miner.mine_rules(transactions)

      rules.each do |rule|
        rule.confidence.should be >= 0.0
        rule.confidence.should be <= 1.0
      end
    end
  end

  describe "InductiveLearner" do
    it "creates a learner with empty background knowledge" do
      learner = Learning::Generalization::InductiveLearner.new
      learner.background_knowledge.should be_empty
    end

    it "accepts background knowledge rules" do
      learner = Learning::Generalization::InductiveLearner.new
      rule = Learning::Generalization::Rule.new(["has_wings"], "can_fly", 1, 0.8)
      learner.add_background(rule)
      learner.background_knowledge.size.should eq(1)
    end

    it "learns rules from positive and negative examples" do
      learner = Learning::Generalization::InductiveLearner.new

      positives = [
        {"color" => "yellow", "size" => "small"},
        {"color" => "yellow", "size" => "medium"},
        {"color" => "yellow", "size" => "large"},
      ]

      negatives = [
        {"color" => "red", "size" => "small"},
        {"color" => "blue", "size" => "medium"},
      ]

      rules = learner.learn(positives, negatives)
      rules.should be_a(Array(Learning::Generalization::Rule))
    end

    it "returns rules sorted by confidence descending" do
      learner = Learning::Generalization::InductiveLearner.new

      # feature_a=x appears in all positives and no negatives -> high confidence
      # feature_b=y appears in only 1 positive and 2 negatives -> low confidence
      positives = [
        {"feature_a" => "x", "feature_b" => "y"},
        {"feature_a" => "x", "feature_b" => "z"},
        {"feature_a" => "x", "feature_b" => "w"},
      ]

      negatives = [
        {"feature_a" => "q", "feature_b" => "y"},
        {"feature_a" => "q", "feature_b" => "y"},
      ]

      rules = learner.learn(positives, negatives)
      # Confidence values should be non-increasing
      rules.each_cons(2) do |pair|
        pair[0].confidence.should be >= pair[1].confidence
      end
      # There should be at least two rules with different confidence values
      # to meaningfully verify sorting
      if rules.size >= 2
        confidences = rules.map(&.confidence).uniq
        confidences.size.should be >= 2
      end
    end
  end

  describe "AnalogyMaker" do
    it "finds analogy between domains with matching roles" do
      maker = Learning::Generalization::AnalogyMaker.new

      source = {"parent" => "earth", "child" => "moon"}
      target = {"parent" => "sun", "child" => "earth"}

      mapping = maker.find_analogy(source, target)
      mapping["earth"].should eq("sun")
      mapping["moon"].should eq("earth")
    end

    it "transfers knowledge using analogy mapping" do
      maker = Learning::Generalization::AnalogyMaker.new

      source_rules = [
        Learning::Generalization::Rule.new(["moon", "orbits"], "earth", 5, 0.9),
      ]

      analogy = {"moon" => "earth", "earth" => "sun"}

      transferred = maker.transfer_knowledge(source_rules, analogy)
      transferred.size.should eq(1)
      transferred.first.antecedent.should contain("earth")
      transferred.first.consequent.should eq("sun")
      # Transferred confidence should be lower than source
      transferred.first.confidence.should be < 0.9
    end
  end

  describe "ClusterGeneralizer" do
    it "generalizes clusters into concepts" do
      generalizer = Learning::Generalization::ClusterGeneralizer.new

      clusters = [
        [
          {"color" => "red", "size" => "small"},
          {"color" => "red", "size" => "medium"},
        ],
        [
          {"color" => "blue", "size" => "large"},
          {"color" => "blue", "size" => "huge"},
        ],
      ]

      concepts = generalizer.generalize_clusters(clusters)
      concepts.size.should eq(2)

      # First cluster: common feature is color=red
      concepts[0].features["color"].should eq("red")
      # Second cluster: common feature is color=blue
      concepts[1].features["color"].should eq("blue")
    end

    it "returns empty concepts for empty clusters" do
      generalizer = Learning::Generalization::ClusterGeneralizer.new
      concepts = generalizer.generalize_clusters([] of Array(Hash(String, String)))
      concepts.should be_empty
    end
  end

  describe "module-level convenience methods" do
    it "mines association rules" do
      transactions = [
        ["a", "b", "c"],
        ["a", "b"],
        ["a", "b", "c"],
        ["b", "c"],
      ]

      rules = Learning::Generalization.mine_association_rules(transactions, 0.5, 0.6)
      rules.should be_a(Array(Learning::Generalization::Rule))
    end

    it "generalizes examples using anti-unification" do
      examples = ["the cat ran", "the dog ran"]
      result = Learning::Generalization.generalize_examples(examples)
      result.should contain("the")
      result.should contain("ran")
    end
  end
end
