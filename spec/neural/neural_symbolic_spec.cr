require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/pln/pln"
require "../../src/neural/neural_symbolic"

describe Neural do
  describe Neural::Tensor do
    it "creates zero tensor" do
      tensor = Neural::Tensor.zeros([3, 4])
      tensor.shape.should eq([3, 4])
      tensor.size.should eq(12)
      tensor.data.all?(&.==(0.0)).should be_true
    end

    it "creates ones tensor" do
      tensor = Neural::Tensor.ones([2, 2])
      tensor.size.should eq(4)
      tensor.data.all?(&.==(1.0)).should be_true
    end

    it "creates random tensor" do
      tensor = Neural::Tensor.random([10])
      tensor.size.should eq(10)
      tensor.data.all? { |x| x >= 0.0 && x <= 1.0 }.should be_true
    end

    it "creates from array" do
      tensor = Neural::Tensor.from_array([1.0, 2.0, 3.0])
      tensor.shape.should eq([3])
      tensor[0].should eq(1.0)
      tensor[1].should eq(2.0)
      tensor[2].should eq(3.0)
    end

    it "performs addition" do
      a = Neural::Tensor.from_array([1.0, 2.0, 3.0])
      b = Neural::Tensor.from_array([4.0, 5.0, 6.0])
      c = a + b

      c[0].should eq(5.0)
      c[1].should eq(7.0)
      c[2].should eq(9.0)
    end

    it "performs subtraction" do
      a = Neural::Tensor.from_array([5.0, 5.0, 5.0])
      b = Neural::Tensor.from_array([1.0, 2.0, 3.0])
      c = a - b

      c[0].should eq(4.0)
      c[1].should eq(3.0)
      c[2].should eq(2.0)
    end

    it "performs scalar multiplication" do
      a = Neural::Tensor.from_array([1.0, 2.0, 3.0])
      b = a * 2.0

      b[0].should eq(2.0)
      b[1].should eq(4.0)
      b[2].should eq(6.0)
    end

    it "computes dot product" do
      a = Neural::Tensor.from_array([1.0, 2.0, 3.0])
      b = Neural::Tensor.from_array([4.0, 5.0, 6.0])

      a.dot(b).should eq(32.0)  # 1*4 + 2*5 + 3*6
    end

    it "computes norm" do
      a = Neural::Tensor.from_array([3.0, 4.0])
      a.norm.should eq(5.0)
    end

    it "normalizes tensor" do
      a = Neural::Tensor.from_array([3.0, 4.0])
      b = a.normalize

      b.norm.should be_close(1.0, 0.001)
    end

    it "computes softmax" do
      a = Neural::Tensor.from_array([1.0, 2.0, 3.0])
      b = a.softmax

      # Sum should be 1
      b.data.sum.should be_close(1.0, 0.001)
      # Values should be in order
      (b[2] > b[1] > b[0]).should be_true
    end

    it "finds argmax" do
      a = Neural::Tensor.from_array([0.1, 0.8, 0.1])
      a.argmax.should eq(1)
    end

    it "computes cosine similarity" do
      a = Neural::Tensor.from_array([1.0, 0.0])
      b = Neural::Tensor.from_array([1.0, 0.0])

      a.cosine_similarity(b).should be_close(1.0, 0.001)

      c = Neural::Tensor.from_array([0.0, 1.0])
      a.cosine_similarity(c).should be_close(0.0, 0.001)
    end

    it "reshapes tensor" do
      a = Neural::Tensor.from_array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
      b = a.reshape([2, 3])

      b.shape.should eq([2, 3])
      b.size.should eq(6)
    end
  end

  describe Neural::Activation do
    it "applies relu" do
      Neural::Activation.relu(5.0).should eq(5.0)
      Neural::Activation.relu(-5.0).should eq(0.0)
    end

    it "applies sigmoid" do
      Neural::Activation.sigmoid(0.0).should eq(0.5)
      Neural::Activation.sigmoid(100.0).should be_close(1.0, 0.001)
      Neural::Activation.sigmoid(-100.0).should be_close(0.0, 0.001)
    end

    it "applies tanh" do
      Neural::Activation.tanh(0.0).should eq(0.0)
      Neural::Activation.tanh(100.0).should be_close(1.0, 0.001)
      Neural::Activation.tanh(-100.0).should be_close(-1.0, 0.001)
    end
  end

  describe Neural::DenseLayer do
    it "creates dense layer" do
      layer = Neural::DenseLayer.new("hidden", 10, 5, :relu)
      layer.name.should eq("hidden")
      layer.input_size.should eq(10)
      layer.output_size.should eq(5)
    end

    it "performs forward pass" do
      layer = Neural::DenseLayer.new("hidden", 3, 2)
      input = Neural::Tensor.from_array([1.0, 2.0, 3.0])

      output = layer.forward(input)
      output.size.should eq(2)
    end
  end

  describe Neural::EmbeddingLayer do
    it "creates embedding layer" do
      layer = Neural::EmbeddingLayer.new("embeddings", 64)
      layer.embedding_dim.should eq(64)
    end

    it "embeds symbols" do
      layer = Neural::EmbeddingLayer.new("embeddings", 32)

      emb1 = layer.embed("cat")
      emb2 = layer.embed("cat")
      emb3 = layer.embed("dog")

      # Same symbol should have same embedding
      emb1.data.should eq(emb2.data)
      # Different symbols should have different embeddings
      emb1.data.should_not eq(emb3.data)
    end

    it "computes similarity" do
      layer = Neural::EmbeddingLayer.new("embeddings", 32)

      # Add similar embeddings manually
      base = Neural::Tensor.random([32])
      layer.add_embedding("king", base)
      layer.add_embedding("queen", base + Neural::Tensor.random([32]) * 0.1)

      sim = layer.similarity("king", "queen")
      sim.should be > 0.9
    end

    it "finds nearest neighbors" do
      layer = Neural::EmbeddingLayer.new("embeddings", 16)

      layer.embed("a")
      layer.embed("b")
      layer.embed("c")

      neighbors = layer.nearest_neighbors("a", 2)
      neighbors.size.should eq(2)
    end
  end

  describe Neural::NeuralNetwork do
    it "creates neural network" do
      net = Neural::NeuralNetwork.new("test_net")
      net.name.should eq("test_net")
      net.layers.should be_empty
    end

    it "adds layers" do
      net = Neural::NeuralNetwork.new("test_net")
      net.add_layer(Neural::DenseLayer.new("hidden", 10, 5, :relu))
      net.add_layer(Neural::DenseLayer.new("output", 5, 2))

      net.layers.size.should eq(2)
    end

    it "performs forward pass" do
      net = Neural::NeuralNetwork.new("test_net")
      net.add_layer(Neural::DenseLayer.new("hidden", 3, 4, :relu))
      net.add_layer(Neural::DenseLayer.new("output", 4, 2))

      input = Neural::Tensor.from_array([1.0, 2.0, 3.0])
      output = net.forward(input)

      output.size.should eq(2)
    end

    it "predicts from array" do
      net = Neural::NeuralNetwork.new("test_net")
      net.add_layer(Neural::DenseLayer.new("output", 3, 2))

      result = net.predict([1.0, 2.0, 3.0])
      result.size.should eq(2)
    end
  end

  describe Neural::SymbolGrounder do
    it "creates symbol grounder" do
      atomspace = AtomSpace::AtomSpace.new
      grounder = Neural::SymbolGrounder.new(atomspace, 64)

      grounder.embeddings.embedding_dim.should eq(64)
    end

    it "grounds atoms to embeddings" do
      atomspace = AtomSpace::AtomSpace.new
      grounder = Neural::SymbolGrounder.new(atomspace, 32)

      node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat")
      embedding = grounder.ground(node)

      embedding.size.should eq(32)
    end

    it "finds similar concepts" do
      atomspace = AtomSpace::AtomSpace.new
      grounder = Neural::SymbolGrounder.new(atomspace, 32)

      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat")
      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "animal")

      # Initialize embeddings
      grounder.ground(atomspace.get_all_atoms[0])
      grounder.ground(atomspace.get_all_atoms[1])
      grounder.ground(atomspace.get_all_atoms[2])

      similar = grounder.similar_concepts("cat", 2)
      similar.size.should eq(2)
    end
  end

  describe Neural::KnowledgeGraphEmbedding do
    it "creates KG embedding" do
      kge = Neural::KnowledgeGraphEmbedding.new(64)
      kge.embedding_dim.should eq(64)
    end

    it "scores triples" do
      kge = Neural::KnowledgeGraphEmbedding.new(32)

      # Initialize some embeddings
      kge.entity_embeddings.embed("cat")
      kge.entity_embeddings.embed("mammal")
      kge.relation_embeddings.embed("is_a")

      score = kge.score("cat", "is_a", "mammal")
      score.should be >= 0.0
    end

    it "predicts tail entities" do
      kge = Neural::KnowledgeGraphEmbedding.new(32)

      kge.entity_embeddings.embed("cat")
      kge.entity_embeddings.embed("dog")
      kge.entity_embeddings.embed("mammal")
      kge.relation_embeddings.embed("is_a")

      predictions = kge.predict_tail("cat", "is_a", 2)
      predictions.size.should eq(2)
    end

    it "predicts head entities" do
      kge = Neural::KnowledgeGraphEmbedding.new(32)

      kge.entity_embeddings.embed("cat")
      kge.entity_embeddings.embed("dog")
      kge.relation_embeddings.embed("is_a")

      predictions = kge.predict_head("is_a", "mammal", 2)
      predictions.size.should be <= 2
    end

    it "predicts relations" do
      kge = Neural::KnowledgeGraphEmbedding.new(32)

      kge.entity_embeddings.embed("cat")
      kge.entity_embeddings.embed("mammal")
      kge.relation_embeddings.embed("is_a")
      kge.relation_embeddings.embed("likes")

      predictions = kge.predict_relation("cat", "mammal", 2)
      predictions.size.should eq(2)
    end
  end

  describe Neural::NeuralSymbolicReasoner do
    it "creates neural-symbolic reasoner" do
      atomspace = AtomSpace::AtomSpace.new
      reasoner = Neural::NeuralSymbolicReasoner.new(atomspace, 32)

      reasoner.neural_threshold.should eq(0.7)
    end

    it "checks if triple is likely true" do
      atomspace = AtomSpace::AtomSpace.new
      reasoner = Neural::NeuralSymbolicReasoner.new(atomspace, 32)

      # Initialize embeddings
      reasoner.kg_embedding.entity_embeddings.embed("cat")
      reasoner.kg_embedding.entity_embeddings.embed("mammal")
      reasoner.kg_embedding.relation_embeddings.embed("is_a")

      result = reasoner.is_likely_true?("cat", "is_a", "mammal")
      result.should be_a(Bool)
    end

    it "completes partial triples" do
      atomspace = AtomSpace::AtomSpace.new
      reasoner = Neural::NeuralSymbolicReasoner.new(atomspace, 32)

      reasoner.kg_embedding.entity_embeddings.embed("cat")
      reasoner.kg_embedding.entity_embeddings.embed("dog")
      reasoner.kg_embedding.relation_embeddings.embed("is_a")

      # Complete: (cat, is_a, ?)
      completions = reasoner.complete_triple("cat", "is_a", nil)
      completions.should_not be_empty
    end
  end

  describe Neural::ProgramSynthesizer do
    it "creates program synthesizer" do
      atomspace = AtomSpace::AtomSpace.new
      synth = Neural::ProgramSynthesizer.new(atomspace)
      synth.should_not be_nil
    end

    it "adds program templates" do
      atomspace = AtomSpace::AtomSpace.new
      synth = Neural::ProgramSynthesizer.new(atomspace)

      synth.add_template(Neural::IdentityProgram.new)
      synth.add_template(Neural::LinearProgram.new([1.0, 2.0]))
    end
  end

  describe Neural::IdentityProgram do
    it "executes identity" do
      program = Neural::IdentityProgram.new
      result = program.execute([1.0, 2.0, 3.0])

      result.should eq([1.0, 2.0, 3.0])
    end
  end

  describe Neural::LinearProgram do
    it "executes linear transformation" do
      program = Neural::LinearProgram.new([2.0, 3.0], 1.0)
      result = program.execute([1.0, 1.0])

      result.should eq([6.0])  # 2*1 + 3*1 + 1
    end
  end

  describe "Module convenience methods" do
    it "creates tensor" do
      tensor = Neural.create_tensor([3, 4])
      tensor.shape.should eq([3, 4])
    end

    it "creates network" do
      net = Neural.create_network("test")
      net.name.should eq("test")
    end

    it "creates reasoner" do
      atomspace = AtomSpace::AtomSpace.new
      reasoner = Neural.create_reasoner(atomspace)
      reasoner.should_not be_nil
    end

    it "creates KG embedding" do
      kge = Neural.create_kg_embedding(64)
      kge.embedding_dim.should eq(64)
    end
  end
end
