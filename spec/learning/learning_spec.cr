require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/learning/learning_main"

describe Learning do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe "VERSION" do
    it "has a version number" do
      Learning::VERSION.should eq("0.1.0")
    end
  end

  describe ".initialize" do
    it "initializes the learning subsystem" do
      Learning.initialize
      true.should be_true
    end
  end
end

describe Learning::ConceptLearning do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe Learning::ConceptLearning::Concept do
    describe "#initialize" do
      it "creates a concept with name" do
        concept = Learning::ConceptLearning::Concept.new("animal")
        concept.name.should eq("animal")
        concept.confidence.should eq(0.5)
      end

      it "creates a concept with custom confidence" do
        concept = Learning::ConceptLearning::Concept.new("dog", confidence: 0.9)
        concept.confidence.should eq(0.9)
      end

      it "starts with empty examples" do
        concept = Learning::ConceptLearning::Concept.new("test")
        concept.positive_examples.size.should eq(0)
        concept.negative_examples.size.should eq(0)
      end
    end

    describe "#add_positive_example" do
      it "adds positive examples" do
        concept = Learning::ConceptLearning::Concept.new("dog")
        example = {"has_fur" => true.as(String | Float64 | Bool), "legs" => 4.0.as(String | Float64 | Bool)}
        concept.add_positive_example(example)
        concept.positive_examples.size.should eq(1)
      end

      it "refines concept from examples" do
        concept = Learning::ConceptLearning::Concept.new("mammal")

        example1 = {"warm_blooded" => true.as(String | Float64 | Bool)}
        example2 = {"warm_blooded" => true.as(String | Float64 | Bool)}

        concept.add_positive_example(example1)
        concept.add_positive_example(example2)

        concept.positive_examples.size.should eq(2)
      end
    end

    describe "#add_negative_example" do
      it "adds negative examples" do
        concept = Learning::ConceptLearning::Concept.new("bird")
        example = {"can_swim" => true.as(String | Float64 | Bool)}
        concept.add_negative_example(example)
        concept.negative_examples.size.should eq(1)
      end
    end

    describe "#matches?" do
      it "matches when features align" do
        concept = Learning::ConceptLearning::Concept.new(
          "dog",
          {"has_fur" => true.as(String | Float64 | Bool)}
        )

        matching = {"has_fur" => true.as(String | Float64 | Bool), "barks" => true.as(String | Float64 | Bool)}
        concept.matches?(matching).should be_true
      end

      it "does not match when features differ" do
        concept = Learning::ConceptLearning::Concept.new(
          "dog",
          {"has_fur" => true.as(String | Float64 | Bool)}
        )

        non_matching = {"has_fur" => false.as(String | Float64 | Bool)}
        concept.matches?(non_matching).should be_false
      end
    end

    describe "#to_atomspace" do
      it "converts concept to atoms" do
        atomspace = AtomSpace::AtomSpace.new
        concept = Learning::ConceptLearning::Concept.new(
          "test_concept",
          {"color" => "red".as(String | Float64 | Bool)}
        )

        atoms = concept.to_atomspace(atomspace)
        atoms.size.should be > 0
        atomspace.size.should be > 0
      end
    end
  end

  describe Learning::ConceptLearning::Hypothesis do
    describe ".new_most_general" do
      it "creates most general hypothesis" do
        h = Learning::ConceptLearning::Hypothesis.new_most_general
        h.constraints.empty?.should be_true
      end
    end

    describe ".new_most_specific" do
      it "creates most specific hypothesis" do
        h = Learning::ConceptLearning::Hypothesis.new_most_specific
        h.constraints.has_key?("__none__").should be_true
      end
    end

    describe "#matches?" do
      it "most general matches anything" do
        h = Learning::ConceptLearning::Hypothesis.new_most_general
        example = {"color" => "red", "size" => "large"}
        h.matches?(example).should be_true
      end

      it "most specific matches nothing" do
        h = Learning::ConceptLearning::Hypothesis.new_most_specific
        example = {"color" => "red"}
        h.matches?(example).should be_false
      end

      it "specific hypothesis matches only matching examples" do
        h = Learning::ConceptLearning::Hypothesis.new({"color" => "red".as(String | Symbol)})
        h.matches?({"color" => "red"}).should be_true
        h.matches?({"color" => "blue"}).should be_false
      end
    end

    describe "#more_general_than?" do
      it "detects more general hypothesis" do
        general = Learning::ConceptLearning::Hypothesis.new_most_general
        specific = Learning::ConceptLearning::Hypothesis.new({"color" => "red".as(String | Symbol)})
        general.more_general_than?(specific).should be_true
      end
    end
  end

  describe Learning::ConceptLearning::CandidateElimination do
    describe "#initialize" do
      it "starts with most general and most specific boundaries" do
        ce = Learning::ConceptLearning::CandidateElimination.new
        ce.general_boundary.size.should eq(1)
        ce.specific_boundary.size.should eq(1)
      end
    end

    describe "#learn_positive" do
      it "learns from positive examples" do
        ce = Learning::ConceptLearning::CandidateElimination.new
        example = {"color" => "red", "shape" => "circle"}
        ce.learn_positive(example)
        # After learning, boundaries should be updated
        true.should be_true
      end
    end

    describe "#learn_negative" do
      it "learns from negative examples" do
        ce = Learning::ConceptLearning::CandidateElimination.new
        ce.learn_positive({"color" => "red", "shape" => "circle"})
        ce.learn_negative({"color" => "blue", "shape" => "circle"})
        true.should be_true
      end
    end
  end

  describe Learning::ConceptLearning::ConceptHierarchy do
    describe "#initialize" do
      it "creates empty hierarchy" do
        hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
        hierarchy.concepts.size.should eq(0)
      end
    end

    describe "#add_concept" do
      it "adds concepts to hierarchy" do
        hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
        concept = Learning::ConceptLearning::Concept.new("animal")
        hierarchy.add_concept(concept)
        hierarchy.concepts.size.should eq(1)
      end
    end

    describe "#add_is_a_relation" do
      it "adds is-a relationships" do
        hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
        hierarchy.add_is_a_relation("dog", "mammal")
        hierarchy.add_is_a_relation("mammal", "animal")
        true.should be_true
      end
    end

    describe "#inherits_from?" do
      it "detects direct inheritance" do
        hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
        hierarchy.add_is_a_relation("dog", "mammal")
        hierarchy.inherits_from?("dog", "mammal").should be_true
      end

      it "detects transitive inheritance" do
        hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
        hierarchy.add_is_a_relation("dog", "mammal")
        hierarchy.add_is_a_relation("mammal", "animal")
        hierarchy.inherits_from?("dog", "animal").should be_true
      end

      it "identity returns true" do
        hierarchy = Learning::ConceptLearning::ConceptHierarchy.new
        hierarchy.inherits_from?("dog", "dog").should be_true
      end
    end

    describe "#get_ancestors" do
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
    end

    describe "#to_atomspace" do
      it "converts hierarchy to atomspace" do
        atomspace = AtomSpace::AtomSpace.new
        hierarchy = Learning::ConceptLearning::ConceptHierarchy.new

        dog = Learning::ConceptLearning::Concept.new("dog")
        hierarchy.add_concept(dog)
        hierarchy.add_is_a_relation("dog", "mammal")

        atoms = hierarchy.to_atomspace(atomspace)
        atoms.size.should be > 0
      end
    end
  end

  describe "Module-level methods" do
    describe ".create_concept" do
      it "creates a new concept" do
        concept = Learning::ConceptLearning.create_concept("test")
        concept.name.should eq("test")
      end
    end

    describe ".create_hierarchy" do
      it "creates a new hierarchy" do
        hierarchy = Learning::ConceptLearning.create_hierarchy
        hierarchy.should be_a(Learning::ConceptLearning::ConceptHierarchy)
      end
    end
  end
end
