require "spec"
require "../../src/learning/learning_main"

describe "Learning Main" do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    Learning.initialize
  end

  describe "initialization" do
    it "initializes the Learning subsystem without errors" do
      Learning.initialize
    end

    it "has correct version" do
      Learning::VERSION.should eq("0.1.0")
    end
  end

  describe "module accessibility" do
    it "exposes ConceptLearning module" do
      Learning::ConceptLearning::VERSION.should eq("0.1.0")
    end

    it "exposes Generalization module" do
      Learning::Generalization::VERSION.should eq("0.1.0")
    end
  end
end
