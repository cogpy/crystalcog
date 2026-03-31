require "spec"
require "../../src/learning/concept_learning"

describe Learning::ConceptLearning do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe "Concept" do
    it "creates a concept with a name" do
      concept = Learning::ConceptLearning::Concept.new("animal")
      concept.name.should eq("animal")
      concept.features.should be_empty
      concept.positive_examples.should be_empty
      concept.negative_examples.should be_empty
    end

    it "creates a concept with initial features" do
      features = {"legs" => "four", "warm_blooded" => "true"} of String => String | Float64 | Bool
      concept = Learning::ConceptLearning::Concept.new("mammal", features)
      concept.features["legs"].should eq("four")
      concept.features["warm_blooded"].should eq("true")
    end

    it "initializes with the given confidence" do
      concept = Learning::ConceptLearning::Concept.new("bird", {} of String => String | Float64 | Bool, 0.9)
      concept.confidence.should eq(0.9)
    end

    it "accepts positive examples and updates confidence" do
      concept = Learning::ConceptLearning::Concept.new("mammal")
      example = {"legs" => "four", "warm_blooded" => "true"} of String => String | Float64 | Bool
      concept.add_positive_example(example)
      concept.positive_examples.size.should eq(1)
      concept.confidence.should eq(1.0)
    end

    it "accepts negative examples and adjusts confidence" do
      concept = Learning::ConceptLearning::Concept.new("mammal")
      pos = {"legs" => "four"} of String => String | Float64 | Bool
      neg = {"legs" => "six"} of String => String | Float64 | Bool
      concept.add_positive_example(pos)
      concept.add_negative_example(neg)
      concept.negative_examples.size.should eq(1)
      # With one positive and one negative, confidence should be 0.5
      concept.confidence.should eq(0.5)
    end

    it "matches examples based on features" do
      features = {"color" => "red", "shape" => "round"} of String => String | Float64 | Bool
      concept = Learning::ConceptLearning::Concept.new("apple", features)

      matching = {"color" => "red", "shape" => "round"} of String => String | Float64 | Bool
      non_matching = {"color" => "green", "shape" => "round"} of String => String | Float64 | Bool

      concept.matches?(matching).should be_true
      concept.matches?(non_matching).should be_false
    end

    it "matches when example has extra keys" do
      features = {"color" => "red"} of String => String | Float64 | Bool
      concept = Learning::ConceptLearning::Concept.new("red_thing", features)
      example = {"color" => "red", "size" => "big"} of String => String | Float64 | Bool
      concept.matches?(example).should be_true
    end

    it "converts concept to AtomSpace representation" do
      atomspace = AtomSpace::AtomSpace.new
      features = {"legs" => "four"} of String => String | Float64 | Bool
      concept = Learning::ConceptLearning::Concept.new("dog", features, 0.8)

      atoms = concept.to_atomspace(atomspace)
      atoms.should_not be_empty
      atomspace.size.should be > 0

      # Should have a concept node named "dog"
      concept_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
      concept_nodes.any? { |a| a.name == "dog" }.should be_true
    end

    it "refines features from multiple positive examples" do
      concept = Learning::ConceptLearning::Concept.new("bird")
      ex1 = {"has_wings" => "true", "lays_eggs" => "true", "color" => "red"} of String => String | Float64 | Bool
      ex2 = {"has_wings" => "true", "lays_eggs" => "true", "color" => "blue"} of String => String | Float64 | Bool
      concept.add_positive_example(ex1)
      concept.add_positive_example(ex2)

      # Common features with a single value should be in features
      concept.features["has_wings"].should eq("true")
      concept.features["lays_eggs"].should eq("true")
      # Non-common values should not be set
      concept.features.has_key?("color").should be_false
    end
  end

  describe "CandidateElimination" do
    it "initializes with general and specific boundaries" do
      ce = Learning::ConceptLearning::CandidateElimination.new
      ce.general_boundary.size.should eq(1)
      ce.specific_boundary.size.should eq(1)
    end

    it "learns from a positive example" do
      ce = Learning::ConceptLearning::CandidateElimination.new
      example = {"color" => "red", "shape" => "round"}
      ce.learn_positive(example)
      ce.specific_boundary.should_not be_empty
    end

    it "learns from a negative example" do
      ce = Learning::ConceptLearning::CandidateElimination.new
      # Learn a positive example first to establish boundaries
      ce.learn_positive({"color" => "red", "shape" => "round"})
      # Now provide a negative example
      ce.learn_negative({"color" => "blue", "shape" => "square"})
      ce.specific_boundary.should_not be_empty
    end
  end

  describe "Hypothesis" do
    it "creates a most-general hypothesis" do
      h = Learning::ConceptLearning::Hypothesis.new_most_general
      h.constraints.should be_empty
    end

    it "creates a most-specific hypothesis" do
      h = Learning::ConceptLearning::Hypothesis.new_most_specific
      h.constraints.has_key?("__none__").should be_true
    end

    it "most-general matches any example" do
      h = Learning::ConceptLearning::Hypothesis.new_most_general
      example = {"color" => "red", "shape" => "round"}
      h.matches?(example).should be_true
    end

    it "most-specific matches no example" do
      h = Learning::ConceptLearning::Hypothesis.new_most_specific
      example = {"color" => "red", "shape" => "round"}
      h.matches?(example).should be_false
    end

    it "matches examples matching constraints" do
      h = Learning::ConceptLearning::Hypothesis.new({"color" => "red"} of String => String | Symbol)
      h.matches?({"color" => "red", "shape" => "round"}).should be_true
      h.matches?({"color" => "blue", "shape" => "round"}).should be_false
    end

    it "generates minimal generalizations" do
      h = Learning::ConceptLearning::Hypothesis.new({"color" => "red", "shape" => "round"} of String => String | Symbol)
      example = {"color" => "blue", "shape" => "round"}
      generalizations = h.minimal_generalizations(example)
      generalizations.should_not be_empty
    end
  end

  describe "ConceptHierarchy" do
    it "creates an empty hierarchy" do
      hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
      hierarchy.concepts.should be_empty
      hierarchy.hierarchy.should be_empty
    end

    it "adds concepts" do
      hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
      concept = Learning::ConceptLearning::Concept.new("animal")
      hierarchy.add_concept(concept)
      hierarchy.concepts.size.should eq(1)
    end

    it "records is-a relationships" do
      hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
      hierarchy.add_is_a_relation("dog", "mammal")
      hierarchy.add_is_a_relation("mammal", "animal")

      hierarchy.inherits_from?("dog", "mammal").should be_true
      hierarchy.inherits_from?("dog", "animal").should be_true
      hierarchy.inherits_from?("dog", "plant").should be_false
    end

    it "returns all ancestors" do
      hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
      hierarchy.add_is_a_relation("poodle", "dog")
      hierarchy.add_is_a_relation("dog", "mammal")
      hierarchy.add_is_a_relation("mammal", "animal")

      ancestors = hierarchy.get_ancestors("poodle")
      ancestors.should contain("dog")
      ancestors.should contain("mammal")
      ancestors.should contain("animal")
    end

    it "converts hierarchy to AtomSpace" do
      atomspace = AtomSpace::AtomSpace.new
      hierarchy = Learning::ConceptLearning::ConceptHierarchy.new

      dog = Learning::ConceptLearning::Concept.new("dog")
      animal = Learning::ConceptLearning::Concept.new("animal")
      hierarchy.add_concept(dog)
      hierarchy.add_concept(animal)
      hierarchy.add_is_a_relation("dog", "animal")

      atoms = hierarchy.to_atomspace(atomspace)
      atoms.should_not be_empty
      atomspace.size.should be > 0

      # Should have inheritance links
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
      inheritance_links.size.should be >= 1
    end
  end

  describe "module-level methods" do
    it "creates a concept via create_concept" do
      concept = Learning::ConceptLearning.create_concept("plant")
      concept.should be_a(Learning::ConceptLearning::Concept)
      concept.name.should eq("plant")
    end

    it "creates a hierarchy via create_hierarchy" do
      hierarchy = Learning::ConceptLearning.create_hierarchy
      hierarchy.should be_a(Learning::ConceptLearning::ConceptHierarchy)
      hierarchy.concepts.should be_empty
    end
  end
end
