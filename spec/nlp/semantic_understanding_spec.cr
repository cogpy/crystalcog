require "spec"
require "../../src/nlp/semantic_understanding"

describe NLP::SemanticUnderstanding do
  describe "Analyzer" do
    it "initializes with a language" do
      analyzer = NLP::SemanticUnderstanding::Analyzer.new("en")
      analyzer.language.should eq("en")
    end

    it "analyzes text into a semantic analysis" do
      analyzer = NLP::SemanticUnderstanding::Analyzer.new
      analysis = analyzer.analyze("The cat sits on the mat")
      analysis.should be_a(NLP::SemanticUnderstanding::SemanticAnalysis)
      analysis.text.should eq("The cat sits on the mat")
    end

    it "extracts capitalized named entities" do
      analyzer = NLP::SemanticUnderstanding::Analyzer.new
      entities = analyzer.extract_named_entities("the scientist met Albert Einstein yesterday")
      entities.should contain("Albert")
      entities.should contain("Einstein")
    end

    it "computes semantic similarity between related texts" do
      analyzer = NLP::SemanticUnderstanding::Analyzer.new
      # Shared capitalized entity drives a non-zero similarity score
      sim = analyzer.semantic_similarity("I met Albert today", "she saw Albert too")
      sim.should be > 0.0
    end

    it "returns zero similarity for unrelated texts" do
      analyzer = NLP::SemanticUnderstanding::Analyzer.new
      sim = analyzer.semantic_similarity("cats", "dogs")
      sim.should eq(0.0)
    end
  end

  describe "module API" do
    it "exposes a module-level analyze" do
      analysis = NLP::SemanticUnderstanding.analyze("Socrates is human")
      analysis.should be_a(NLP::SemanticUnderstanding::SemanticAnalysis)
    end
  end
end
