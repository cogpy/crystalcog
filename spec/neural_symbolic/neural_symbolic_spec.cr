require "spec"
require "../../src/neural_symbolic/neural_symbolic"

describe NeuralSymbolic do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    NeuralSymbolic.initialize
  end

  describe "initialization" do
    it "initializes the NeuralSymbolic subsystem without errors" do
      NeuralSymbolic.initialize
    end

    it "has correct version" do
      NeuralSymbolic::VERSION.should eq("0.1.0")
    end
  end

  describe "Embedding" do
    it "creates an embedding with a concept and vector" do
      emb = NeuralSymbolic::Embedding.new("cat", [0.1, 0.2, 0.3])
      emb.concept.should eq("cat")
      emb.vector.should eq([0.1, 0.2, 0.3])
      emb.dimension.should eq(3)
    end

    it "computes cosine similarity (identical vectors = 1.0)" do
      emb1 = NeuralSymbolic::Embedding.new("a", [1.0, 0.0, 0.0])
      emb2 = NeuralSymbolic::Embedding.new("b", [1.0, 0.0, 0.0])
      emb1.cosine_similarity(emb2).should be_close(1.0, 0.0001)
    end

    it "computes cosine similarity (orthogonal vectors = 0.0)" do
      emb1 = NeuralSymbolic::Embedding.new("a", [1.0, 0.0])
      emb2 = NeuralSymbolic::Embedding.new("b", [0.0, 1.0])
      emb1.cosine_similarity(emb2).should be_close(0.0, 0.0001)
    end

    it "computes euclidean distance" do
      emb1 = NeuralSymbolic::Embedding.new("a", [0.0, 0.0])
      emb2 = NeuralSymbolic::Embedding.new("b", [3.0, 4.0])
      emb1.euclidean_distance(emb2).should be_close(5.0, 0.0001)
    end
  end

  describe "EmbeddingStore" do
    it "stores and retrieves embeddings" do
      store = NeuralSymbolic::EmbeddingStore.new
      emb = NeuralSymbolic::Embedding.new("dog", [0.5, 0.5])
      store.add(emb)
      store.get("dog").should_not be_nil
      store.size.should eq(1)
    end

    it "returns nil for unknown concept" do
      store = NeuralSymbolic::EmbeddingStore.new
      store.get("unknown").should be_nil
    end

    it "finds nearest neighbors" do
      store = NeuralSymbolic::EmbeddingStore.new
      store.add(NeuralSymbolic::Embedding.new("cat", [1.0, 0.0]))
      store.add(NeuralSymbolic::Embedding.new("dog", [0.9, 0.1]))
      store.add(NeuralSymbolic::Embedding.new("fish", [0.0, 1.0]))
      query = NeuralSymbolic::Embedding.new("q", [1.0, 0.0])
      nearest = store.nearest(query, 2)
      nearest.size.should eq(2)
      # cat should be the closest
      nearest.first[0].should eq("cat")
    end
  end

  describe "NeuralSymbolicReasoner" do
    it "initializes with an atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      reasoner = NeuralSymbolic::NeuralSymbolicReasoner.new(atomspace)
      reasoner.should_not be_nil
      reasoner.embedding_store.size.should eq(0)
    end

    it "adds embeddings and retrieves similar concepts" do
      atomspace = AtomSpace::AtomSpace.new
      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat")
      reasoner = NeuralSymbolic::NeuralSymbolicReasoner.new(atomspace)
      reasoner.add_embedding("dog", [1.0, 0.0])
      reasoner.add_embedding("cat", [0.9, 0.1])
      similar = reasoner.retrieve_similar("dog", 2)
      similar.size.should be >= 1
    end

    it "converts neural probability to truth value" do
      atomspace = AtomSpace::AtomSpace.new
      reasoner = NeuralSymbolic::NeuralSymbolicReasoner.new(atomspace)
      tv = reasoner.neural_to_truth_value(0.8)
      tv.strength.should be_close(0.8, 0.0001)
    end

    it "adds similarity links when threshold is met" do
      atomspace = AtomSpace::AtomSpace.new
      reasoner = NeuralSymbolic::NeuralSymbolicReasoner.new(atomspace)
      reasoner.add_embedding("cat", [1.0, 0.0])
      reasoner.add_embedding("kitten", [0.98, 0.02])
      reasoner.add_embedding("car", [0.0, 1.0])
      count = reasoner.enrich_with_similarities(0.9)
      count.should be >= 1
    end
  end

  describe "NeuralAtomSpaceMapper" do
    it "maps output vector to atomspace atoms" do
      atomspace = AtomSpace::AtomSpace.new
      mapper = NeuralSymbolic::NeuralAtomSpaceMapper.new(atomspace)
      concepts = ["cat", "dog", "fish"]
      output = [0.8, 0.1, 0.1]
      atoms = mapper.map_output(concepts, output)
      atoms.size.should eq(3)
    end

    it "maps atomspace concept TVs to input vector" do
      atomspace = AtomSpace::AtomSpace.new
      tv = AtomSpace::SimpleTruthValue.new(0.9, 1.0)
      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat", tv)
      mapper = NeuralSymbolic::NeuralAtomSpaceMapper.new(atomspace)
      vec = mapper.map_to_input(["cat", "unknown"])
      vec[0].should be_close(0.9, 0.0001)
      vec[1].should eq(0.0)
    end
  end
end
