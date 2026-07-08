# Neural-Symbolic Integration for CrystalCog
#
# This module bridges neural network representations with symbolic
# AtomSpace knowledge, enabling hybrid neural-symbolic reasoning.
#
# References:
# - Neural-Symbolic Learning and Reasoning: https://arxiv.org/abs/1905.06088
# - CogPrime: https://goertzel.org/CogPrime_Overview.pdf

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../ml/ml_main"

module NeuralSymbolic
  VERSION = "0.1.0"

  class NeuralSymbolicException < Exception
  end

  # Embedding: a dense float vector representation of a concept
  struct Embedding
    getter concept : String
    getter vector : Array(Float64)

    def initialize(@concept : String, @vector : Array(Float64))
    end

    def dimension : Int32
      @vector.size
    end

    # Cosine similarity to another embedding
    def cosine_similarity(other : Embedding) : Float64
      raise NeuralSymbolicException.new("Dimension mismatch") if @vector.size != other.vector.size
      dot = @vector.zip(other.vector).sum { |a, b| a * b }
      norm_a = Math.sqrt(@vector.sum { |v| v ** 2 })
      norm_b = Math.sqrt(other.vector.sum { |v| v ** 2 })
      return 0.0 if norm_a == 0.0 || norm_b == 0.0
      dot / (norm_a * norm_b)
    end

    def euclidean_distance(other : Embedding) : Float64
      raise NeuralSymbolicException.new("Dimension mismatch") if @vector.size != other.vector.size
      Math.sqrt(@vector.zip(other.vector).sum { |a, b| (a - b) ** 2 })
    end
  end

  # Stores and retrieves concept embeddings
  class EmbeddingStore
    getter embeddings : Hash(String, Embedding)

    def initialize
      @embeddings = {} of String => Embedding
    end

    def add(embedding : Embedding)
      @embeddings[embedding.concept] = embedding
    end

    def get(concept : String) : Embedding?
      @embeddings[concept]?
    end

    def size : Int32
      @embeddings.size
    end

    # Return the top-k most similar concepts to the query embedding
    def nearest(query : Embedding, k : Int32 = 5) : Array(Tuple(String, Float64))
      scored = @embeddings.map do |concept, emb|
        {concept, query.cosine_similarity(emb)}
      end
      scored.sort_by { |_, sim| -sim }.first(k)
    end

    # Store embeddings as AtomSpace atoms (concept nodes with attention values)
    def to_atomspace(atomspace : AtomSpace::AtomSpace)
      @embeddings.each do |concept, emb|
        node = atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          concept,
          AtomSpace::SimpleTruthValue.new(1.0, 1.0)
        )
        # Store embedding dimension as a property
        dim_node = atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          "embedding_dim_#{emb.dimension}"
        )
        atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [dim_node, node])
      end
    end
  end

  # Performs neural-guided symbolic reasoning: uses embeddings to rank
  # candidate atoms before applying symbolic inference rules.
  class NeuralSymbolicReasoner
    getter embedding_store : EmbeddingStore
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @embedding_store = EmbeddingStore.new
      CogUtil::Logger.info("NeuralSymbolicReasoner initialized")
    end

    # Add an embedding for a concept
    def add_embedding(concept : String, vector : Array(Float64))
      emb = Embedding.new(concept, vector)
      @embedding_store.add(emb)
    end

    # Given a query concept, retrieve semantically similar concepts from AtomSpace
    def retrieve_similar(query_concept : String, k : Int32 = 5) : Array(AtomSpace::Atom)
      query_emb = @embedding_store.get(query_concept)
      return [] of AtomSpace::Atom unless query_emb

      nearest = @embedding_store.nearest(query_emb, k)

      nearest.compact_map do |concept, _sim|
        @atomspace.get_nodes_by_name(concept, AtomSpace::AtomType::CONCEPT_NODE).first?
      end
    end

    # Map neural prediction (probability distribution) to truth value
    def neural_to_truth_value(probability : Float64, confidence : Float64 = 0.9) : AtomSpace::SimpleTruthValue
      AtomSpace::SimpleTruthValue.new(probability.clamp(0.0, 1.0), confidence)
    end

    # Enrich AtomSpace with semantic similarity links derived from embeddings
    def enrich_with_similarities(threshold : Float64 = 0.8)
      concepts = @embedding_store.embeddings.keys
      count = 0

      concepts.each_with_index do |c1, i|
        (i + 1...concepts.size).each do |j|
          c2 = concepts[j]
          emb1 = @embedding_store.get(c1).not_nil!
          emb2 = @embedding_store.get(c2).not_nil!
          sim = emb1.cosine_similarity(emb2)

          if sim >= threshold
            n1 = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, c1)
            n2 = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, c2)
            sim_pred = @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "similar_to")
            list = @atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [n1, n2])
            similarity_link = @atomspace.add_link(
              AtomSpace::AtomType::EVALUATION_LINK,
              [sim_pred, list],
              AtomSpace::SimpleTruthValue.new(sim, 0.9)
            )
            count += 1
            _ = similarity_link
          end
        end
      end

      CogUtil::Logger.info("Added #{count} similarity links (threshold=#{threshold})")
      count
    end
  end

  # Converts between neural network outputs and AtomSpace structures
  class NeuralAtomSpaceMapper
    def initialize(@atomspace : AtomSpace::AtomSpace)
    end

    # Map a neural network's output vector to AtomSpace concept activations
    def map_output(concepts : Array(String), output : Array(Float64)) : Array(AtomSpace::Atom)
      raise NeuralSymbolicException.new("Size mismatch") if concepts.size != output.size

      concepts.zip(output).map do |concept, activation|
        tv = AtomSpace::SimpleTruthValue.new(activation.clamp(0.0, 1.0), 0.9)
        @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, concept, tv)
      end
    end

    # Convert AtomSpace concept truth values to a feature vector for neural input
    def map_to_input(concepts : Array(String)) : Array(Float64)
      concepts.map do |concept|
        node = @atomspace.get_nodes_by_name(concept, AtomSpace::AtomType::CONCEPT_NODE).first?
        node ? node.truth_value.strength : 0.0
      end
    end
  end

  # Trains concept embeddings from the structural relationships in an
  # AtomSpace, using link co-occurrence as the training signal. This
  # completes the embedding-to-atom round trip: atoms -> embeddings -> atoms.
  class EmbeddingTrainer
    getter atomspace : AtomSpace::AtomSpace
    getter dimension : Int32

    def initialize(@atomspace : AtomSpace::AtomSpace, @dimension : Int32 = 16)
      raise NeuralSymbolicException.new("dimension must be positive") if @dimension <= 0
    end

    # Train embeddings from concept co-occurrence in links. Concepts that
    # appear together in links receive similar embeddings via iterative
    # averaging (a simplified skip-gram style update).
    def train(iterations : Int32 = 10, learning_rate : Float64 = 0.5) : EmbeddingStore
      store = EmbeddingStore.new
      concepts = @atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
        .compact_map { |a| a.as?(AtomSpace::Node).try(&.name) }
        .uniq

      return store if concepts.empty?

      # Initialize with deterministic pseudo-random vectors (seeded per concept)
      vectors = Hash(String, Array(Float64)).new
      concepts.each do |c|
        rng = Random.new(c.hash.to_u64!)
        vectors[c] = Array(Float64).new(@dimension) { rng.rand * 2.0 - 1.0 }
      end

      pairs = co_occurring_pairs

      iterations.times do
        pairs.each do |c1, c2|
          v1, v2 = vectors[c1]?, vectors[c2]?
          next unless v1 && v2
          # Pull co-occurring concepts toward each other
          @dimension.times do |d|
            mid = (v1[d] + v2[d]) / 2.0
            v1[d] += learning_rate * (mid - v1[d])
            v2[d] += learning_rate * (mid - v2[d])
          end
        end
      end

      vectors.each { |c, v| store.add(Embedding.new(c, v)) }
      CogUtil::Logger.info("Trained #{vectors.size} embeddings (dim=#{@dimension}, iters=#{iterations})")
      store
    end

    # Extract concept name pairs that co-occur within the same link
    private def co_occurring_pairs : Array(Tuple(String, String))
      pairs = [] of Tuple(String, String)

      @atomspace.get_all_atoms.each do |atom|
        next unless atom.is_a?(AtomSpace::Link)
        names = collect_concept_names(atom)
        names.each_with_index do |n1, i|
          names[(i + 1)..].each { |n2| pairs << {n1, n2} }
        end
      end

      pairs
    end

    private def collect_concept_names(link : AtomSpace::Link) : Array(String)
      names = [] of String
      link.outgoing.each do |child|
        case child
        when AtomSpace::Link
          names.concat(collect_concept_names(child))
        when AtomSpace::Node
          names << child.name if child.type == AtomSpace::AtomType::CONCEPT_NODE
        end
      end
      names
    end
  end

  # Estimates truth values for unobserved relationships using embedding
  # similarity — "neural truth value estimation".
  class TruthValueEstimator
    getter embedding_store : EmbeddingStore

    def initialize(@embedding_store : EmbeddingStore)
    end

    # Estimate the truth value of a similarity/inheritance relation between
    # two concepts from their embedding similarity. Confidence scales with
    # the magnitude of the similarity signal.
    def estimate(concept_a : String, concept_b : String) : AtomSpace::SimpleTruthValue?
      emb_a = @embedding_store.get(concept_a)
      emb_b = @embedding_store.get(concept_b)
      return nil unless emb_a && emb_b

      sim = emb_a.cosine_similarity(emb_b)
      strength = ((sim + 1.0) / 2.0).clamp(0.0, 1.0) # Map [-1,1] -> [0,1]
      confidence = sim.abs.clamp(0.0, 0.9)           # Stronger signal -> higher confidence
      AtomSpace::SimpleTruthValue.new(strength, confidence)
    end

    # Materialize estimated relations into the AtomSpace for concept pairs
    # exceeding a similarity threshold. Returns the number of links created.
    def materialize_estimates(atomspace : AtomSpace::AtomSpace, threshold : Float64 = 0.5) : Int32
      concepts = @embedding_store.embeddings.keys
      count = 0

      concepts.each_with_index do |c1, i|
        concepts[(i + 1)..].each do |c2|
          tv = estimate(c1, c2)
          next unless tv && tv.strength >= threshold

          n1 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, c1)
          n2 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, c2)
          pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "estimated_similar_to")
          list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [n1, n2])
          atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [pred, list], tv)
          count += 1
        end
      end

      CogUtil::Logger.info("Materialized #{count} estimated similarity links")
      count
    end
  end

  # Initialize the NeuralSymbolic subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing NeuralSymbolic subsystem...")
    CogUtil::Logger.info("NeuralSymbolic subsystem initialized successfully")
  end
end
