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

describe NeuralSymbolic::EmbeddingTrainer do
  it "raises for non-positive dimension" do
    atomspace = AtomSpace::AtomSpace.new
    expect_raises(NeuralSymbolic::NeuralSymbolicException) do
      NeuralSymbolic::EmbeddingTrainer.new(atomspace, 0)
    end
  end

  it "returns empty store for empty atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    trainer = NeuralSymbolic::EmbeddingTrainer.new(atomspace, 8)
    store = trainer.train
    store.size.should eq(0)
  end

  it "trains embeddings for all concepts in the atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    dog = atomspace.add_concept_node("dog")
    animal = atomspace.add_concept_node("animal")
    atomspace.add_inheritance_link(dog, animal)

    trainer = NeuralSymbolic::EmbeddingTrainer.new(atomspace, 8)
    store = trainer.train
    store.size.should eq(2)
    store.get("dog").not_nil!.dimension.should eq(8)
  end

  it "makes co-occurring concepts more similar than unrelated ones" do
    atomspace = AtomSpace::AtomSpace.new
    dog = atomspace.add_concept_node("dog")
    animal = atomspace.add_concept_node("animal")
    rock = atomspace.add_concept_node("rock")
    atomspace.add_inheritance_link(dog, animal)

    trainer = NeuralSymbolic::EmbeddingTrainer.new(atomspace, 16)
    store = trainer.train(20)

    dog_emb = store.get("dog").not_nil!
    animal_emb = store.get("animal").not_nil!
    rock_emb = store.get("rock").not_nil!

    related_sim = dog_emb.cosine_similarity(animal_emb)
    unrelated_sim = dog_emb.cosine_similarity(rock_emb)
    (related_sim > unrelated_sim).should be_true
  end
end

describe NeuralSymbolic::TruthValueEstimator do
  it "returns nil for unknown concepts" do
    store = NeuralSymbolic::EmbeddingStore.new
    estimator = NeuralSymbolic::TruthValueEstimator.new(store)
    estimator.estimate("a", "b").should be_nil
  end

  it "estimates high strength for identical embeddings" do
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("a", [1.0, 0.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("b", [1.0, 0.0, 0.0]))

    estimator = NeuralSymbolic::TruthValueEstimator.new(store)
    tv = estimator.estimate("a", "b").not_nil!
    tv.strength.should be_close(1.0, 1e-9)
    tv.confidence.should be > 0.5
  end

  it "estimates low strength for opposite embeddings" do
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("a", [1.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("b", [-1.0, 0.0]))

    estimator = NeuralSymbolic::TruthValueEstimator.new(store)
    tv = estimator.estimate("a", "b").not_nil!
    tv.strength.should be_close(0.0, 1e-9)
  end

  it "materializes estimated similarity links into the atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("cat", [1.0, 0.1]))
    store.add(NeuralSymbolic::Embedding.new("dog", [0.9, 0.2]))

    estimator = NeuralSymbolic::TruthValueEstimator.new(store)
    count = estimator.materialize_estimates(atomspace, 0.5)
    count.should eq(1)

    preds = atomspace.get_nodes_by_name("estimated_similar_to", AtomSpace::AtomType::PREDICATE_NODE)
    preds.should_not be_empty
  end

  it "does not materialize links below the threshold" do
    atomspace = AtomSpace::AtomSpace.new
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("a", [1.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("b", [-1.0, 0.0]))

    estimator = NeuralSymbolic::TruthValueEstimator.new(store)
    estimator.materialize_estimates(atomspace, 0.5).should eq(0)
  end
end
