require "spec"
require "../../src/neural_symbolic/neural_symbolic"

describe NeuralSymbolic::NeuralAttention do
  it "computes attention weights via softmax" do
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("cat", [1.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("dog", [0.9, 0.1]))
    store.add(NeuralSymbolic::Embedding.new("car", [0.0, 1.0]))

    attn = NeuralSymbolic::NeuralAttention.new(store)
    weights = attn.attention_weights("cat")
    weights.should_not be_empty
    sum = weights.sum { |_, w| w }
    sum.should be_close(1.0, 0.001)
    weights.first[0].should eq("cat")
  end

  it "produces an attended embedding" do
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("a", [1.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("b", [0.0, 1.0]))
    attn = NeuralSymbolic::NeuralAttention.new(store)
    result = attn.attend("a")
    result.should_not be_nil
    result.not_nil!.dimension.should eq(2)
  end

  it "returns top-k concepts" do
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("a", [1.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("b", [0.5, 0.5]))
    store.add(NeuralSymbolic::Embedding.new("c", [0.0, 1.0]))
    attn = NeuralSymbolic::NeuralAttention.new(store)
    top = attn.top_k("a", 2)
    top.size.should eq(2)
  end
end

describe NeuralSymbolic::DifferentiableReasoner do
  it "computes soft logic operations" do
    atomspace = AtomSpace::AtomSpace.new
    store = NeuralSymbolic::EmbeddingStore.new
    reasoner = NeuralSymbolic::DifferentiableReasoner.new(atomspace, store)

    reasoner.soft_and(0.8, 0.5).should be_close(0.4, 0.001)
    reasoner.soft_or(0.8, 0.5).should be_close(0.9, 0.001)
    reasoner.soft_not(0.3).should be_close(0.7, 0.001)
    reasoner.soft_implies(1.0, 0.5).should be_close(0.5, 0.001)
  end

  it "performs soft modus ponens" do
    atomspace = AtomSpace::AtomSpace.new
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("bird", [1.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("flies", [0.9, 0.1]))
    reasoner = NeuralSymbolic::DifferentiableReasoner.new(atomspace, store)

    tv = reasoner.soft_modus_ponens(0.9, 0.8, "bird", "flies")
    tv.strength.should be > 0.0
    tv.confidence.should be > 0.0
  end

  it "chains soft reasoning multi-hop" do
    atomspace = AtomSpace::AtomSpace.new
    store = NeuralSymbolic::EmbeddingStore.new
    store.add(NeuralSymbolic::Embedding.new("a", [1.0, 0.0]))
    store.add(NeuralSymbolic::Embedding.new("b", [0.8, 0.2]))
    store.add(NeuralSymbolic::Embedding.new("c", [0.6, 0.4]))
    reasoner = NeuralSymbolic::DifferentiableReasoner.new(atomspace, store)

    tv = reasoner.soft_chain(["a", "b", "c"], [0.9, 0.8])
    tv.should_not be_nil
    tv.not_nil!.strength.should be > 0.0
  end
end

describe NeuralSymbolic::KnowledgeGraphEmbeddings do
  it "scores triples with TransE distance" do
    kg = NeuralSymbolic::KnowledgeGraphEmbeddings.new(4)
    kg.init_entity("paris")
    kg.init_entity("france")
    kg.init_relation("capital_of")

    score = kg.score_triple("paris", "capital_of", "france")
    score.should_not be_nil
    score.not_nil!.should be >= 0.0
  end

  it "converts distance to truth value" do
    kg = NeuralSymbolic::KnowledgeGraphEmbeddings.new(4)
    kg.init_entity("a")
    kg.init_entity("b")
    kg.init_relation("r")
    tv = kg.triple_truth_value("a", "r", "b")
    tv.should_not be_nil
    tv.not_nil!.strength.should be >= 0.0
  end

  it "loads triples from atomspace and trains" do
    atomspace = AtomSpace::AtomSpace.new
    dog = atomspace.add_concept_node("dog")
    animal = atomspace.add_concept_node("animal")
    atomspace.add_inheritance_link(dog, animal)

    kg = NeuralSymbolic::KnowledgeGraphEmbeddings.new(8)
    triples = kg.load_from_atomspace(atomspace)
    triples.should_not be_empty

    loss = kg.train_epoch(triples, 0.05)
    loss.should be >= 0.0

    store = kg.to_embedding_store
    store.size.should be >= 2
  end
end
