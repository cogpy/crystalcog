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

  # Neural attention mechanism: soft attention weights over concept embeddings
  # for guiding symbolic focus, analogous to transformer attention.
  class NeuralAttention
    getter embedding_store : EmbeddingStore
    getter temperature : Float64

    def initialize(@embedding_store : EmbeddingStore, @temperature : Float64 = 1.0)
      raise NeuralSymbolicException.new("temperature must be positive") if @temperature <= 0.0
    end

    # Compute attention weights from a query concept to all stored concepts.
    # Returns concept -> weight pairs (softmax over cosine similarities).
    def attention_weights(query_concept : String) : Array(Tuple(String, Float64))
      query = @embedding_store.get(query_concept)
      return [] of Tuple(String, Float64) unless query

      scores = @embedding_store.embeddings.map do |concept, emb|
        sim = query.cosine_similarity(emb) / @temperature
        {concept, sim}
      end

      softmax(scores)
    end

    # Attend: produce a weighted combination of value embeddings using
    # attention weights from the query. Returns a new Embedding.
    def attend(query_concept : String, output_name : String = "attended") : Embedding?
      weights = attention_weights(query_concept)
      return nil if weights.empty?

      dim = @embedding_store.embeddings.values.first.dimension
      result = Array(Float64).new(dim, 0.0)

      weights.each do |concept, w|
        emb = @embedding_store.get(concept)
        next unless emb
        dim.times { |d| result[d] += w * emb.vector[d] }
      end

      Embedding.new(output_name, result)
    end

    # Top-k attended concepts
    def top_k(query_concept : String, k : Int32 = 5) : Array(Tuple(String, Float64))
      attention_weights(query_concept).first(k)
    end

    private def softmax(scores : Array(Tuple(String, Float64))) : Array(Tuple(String, Float64))
      return [] of Tuple(String, Float64) if scores.empty?

      max_s = scores.max_of { |_, s| s }
      exps = scores.map { |c, s| {c, Math.exp(s - max_s)} }
      sum = exps.sum { |_, e| e }
      return scores.map { |c, _| {c, 1.0 / scores.size} } if sum <= 0.0

      result = exps.map { |c, e| {c, e / sum} }
      result.sort_by { |_, w| -w }
    end
  end

  # Differentiable reasoning: soft logic operations over truth values
  # that admit gradient-like updates via embedding similarity.
  class DifferentiableReasoner
    getter embedding_store : EmbeddingStore
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace, @embedding_store : EmbeddingStore)
    end

    # Soft conjunction (product t-norm): T(a,b) = a * b
    def soft_and(a : Float64, b : Float64) : Float64
      (a.clamp(0.0, 1.0) * b.clamp(0.0, 1.0))
    end

    # Soft disjunction (probabilistic sum): T(a,b) = a + b - a*b
    def soft_or(a : Float64, b : Float64) : Float64
      aa = a.clamp(0.0, 1.0)
      bb = b.clamp(0.0, 1.0)
      aa + bb - aa * bb
    end

    # Soft negation
    def soft_not(a : Float64) : Float64
      1.0 - a.clamp(0.0, 1.0)
    end

    # Soft implication (Reichenbach): I(a,b) = 1 - a + a*b
    def soft_implies(a : Float64, b : Float64) : Float64
      aa = a.clamp(0.0, 1.0)
      bb = b.clamp(0.0, 1.0)
      (1.0 - aa + aa * bb).clamp(0.0, 1.0)
    end

    # Differentiable modus ponens: given P and P->Q, estimate Q
    # using soft logic and embedding similarity as a prior.
    def soft_modus_ponens(p_strength : Float64, impl_strength : Float64,
                          concept_p : String? = nil, concept_q : String? = nil) : AtomSpace::SimpleTruthValue
      # Base soft MP: Q >= P * (P->Q) under product semantics
      base = soft_and(p_strength, impl_strength)

      # Blend with embedding similarity prior if available
      prior = 0.5
      if concept_p && concept_q
        emb_p = @embedding_store.get(concept_p.not_nil!)
        emb_q = @embedding_store.get(concept_q.not_nil!)
        if emb_p && emb_q
          sim = emb_p.cosine_similarity(emb_q)
          prior = ((sim + 1.0) / 2.0).clamp(0.0, 1.0)
        end
      end

      strength = (0.7 * base + 0.3 * prior).clamp(0.0, 1.0)
      confidence = soft_and(p_strength, impl_strength) * 0.9
      AtomSpace::SimpleTruthValue.new(strength, confidence.clamp(0.0, 1.0))
    end

    # Multi-hop soft reasoning: chain implications along a path of concepts
    def soft_chain(concept_path : Array(String), hop_strengths : Array(Float64)) : AtomSpace::SimpleTruthValue?
      return nil if concept_path.size < 2
      return nil if hop_strengths.size != concept_path.size - 1

      strength = 1.0
      hop_strengths.each { |h| strength = soft_and(strength, h) }

      # Embedding path coherence: average adjacent similarities
      coherence = 0.0
      pairs = 0
      concept_path.each_cons_pair do |a, b|
        emb_a = @embedding_store.get(a)
        emb_b = @embedding_store.get(b)
        if emb_a && emb_b
          coherence += ((emb_a.cosine_similarity(emb_b) + 1.0) / 2.0)
          pairs += 1
        end
      end
      coherence = pairs > 0 ? coherence / pairs : 0.5

      final = (0.6 * strength + 0.4 * coherence).clamp(0.0, 1.0)
      AtomSpace::SimpleTruthValue.new(final, strength.clamp(0.0, 0.95))
    end
  end

  # Knowledge graph embedding support: TransE-style scoring of (h, r, t) triples
  class KnowledgeGraphEmbeddings
    getter dimension : Int32
    getter entity_vectors : Hash(String, Array(Float64))
    getter relation_vectors : Hash(String, Array(Float64))

    def initialize(@dimension : Int32 = 16)
      raise NeuralSymbolicException.new("dimension must be positive") if @dimension <= 0
      @entity_vectors = {} of String => Array(Float64)
      @relation_vectors = {} of String => Array(Float64)
    end

    def init_entity(name : String, seed : Int64? = nil)
      rng = Random.new(seed || stable_seed(name))
      @entity_vectors[name] = Array(Float64).new(@dimension) { rng.rand * 0.1 - 0.05 }
    end

    def init_relation(name : String, seed : Int64? = nil)
      rng = Random.new(seed || (stable_seed(name) &+ 1))
      @relation_vectors[name] = Array(Float64).new(@dimension) { rng.rand * 0.1 - 0.05 }
    end

    private def stable_seed(name : String) : Int64
      # Mix string bytes into a stable Int64 without overflow
      h = 0_i64
      name.each_byte do |b|
        h = (h &* 31_i64) &+ b.to_i64
      end
      h
    end

    # TransE score: ||h + r - t|| (lower is better)
    def score_triple(head : String, relation : String, tail : String) : Float64?
      h = @entity_vectors[head]?
      r = @relation_vectors[relation]?
      t = @entity_vectors[tail]?
      return nil unless h && r && t

      dist = 0.0
      @dimension.times do |d|
        diff = h[d] + r[d] - t[d]
        dist += diff * diff
      end
      Math.sqrt(dist)
    end

    # Convert TransE distance to a truth value (closer => higher strength)
    def triple_truth_value(head : String, relation : String, tail : String,
                           scale : Float64 = 1.0) : AtomSpace::SimpleTruthValue?
      dist = score_triple(head, relation, tail)
      return nil unless dist
      strength = Math.exp(-dist * scale).clamp(0.0, 1.0)
      AtomSpace::SimpleTruthValue.new(strength, 0.8)
    end

    # Train one epoch of TransE on positive triples with simple gradient steps
    def train_epoch(triples : Array(Tuple(String, String, String)),
                    learning_rate : Float64 = 0.01, margin : Float64 = 1.0) : Float64
      total_loss = 0.0

      triples.each do |h, r, t|
        init_entity(h) unless @entity_vectors.has_key?(h)
        init_entity(t) unless @entity_vectors.has_key?(t)
        init_relation(r) unless @relation_vectors.has_key?(r)

        # Corrupt tail for negative sample
        neg_t = @entity_vectors.keys.sample
        next if neg_t == t

        pos = score_triple(h, r, t).not_nil!
        neg = score_triple(h, r, neg_t).not_nil!
        loss = Math.max(0.0, margin + pos - neg)
        total_loss += loss
        next if loss <= 0.0

        # Simple push: move t toward h+r, push neg_t away
        hv = @entity_vectors[h]
        rv = @relation_vectors[r]
        tv = @entity_vectors[t]
        ntv = @entity_vectors[neg_t]

        @dimension.times do |d|
          target = hv[d] + rv[d]
          # Attract positive tail
          grad = tv[d] - target
          tv[d] -= learning_rate * grad
          hv[d] -= learning_rate * grad * 0.5
          rv[d] -= learning_rate * grad * 0.5
          # Repel negative tail slightly
          n_target = hv[d] + rv[d]
          n_grad = ntv[d] - n_target
          ntv[d] += learning_rate * n_grad * 0.5
        end
      end

      total_loss
    end

    # Export entity embeddings into an EmbeddingStore
    def to_embedding_store : EmbeddingStore
      store = EmbeddingStore.new
      @entity_vectors.each do |name, vec|
        store.add(Embedding.new(name, vec.dup))
      end
      store
    end

    # Import triples from AtomSpace EvaluationLinks / InheritanceLinks
    def load_from_atomspace(atomspace : AtomSpace::AtomSpace) : Array(Tuple(String, String, String))
      triples = [] of Tuple(String, String, String)

      atomspace.get_all_atoms.each do |atom|
        next unless atom.is_a?(AtomSpace::Link)

        case atom.type
        when AtomSpace::AtomType::INHERITANCE_LINK
          if atom.outgoing.size >= 2
            c = atom.outgoing[0]
            p = atom.outgoing[1]
            if c.is_a?(AtomSpace::Node) && p.is_a?(AtomSpace::Node)
              triples << {c.name, "inherits", p.name}
            end
          end
        when AtomSpace::AtomType::EVALUATION_LINK
          if atom.outgoing.size >= 2
            pred = atom.outgoing[0]
            args = atom.outgoing[1]
            if pred.is_a?(AtomSpace::Node) && args.is_a?(AtomSpace::Link) && args.outgoing.size >= 2
              a0 = args.outgoing[0]
              a1 = args.outgoing[1]
              if a0.is_a?(AtomSpace::Node) && a1.is_a?(AtomSpace::Node)
                triples << {a0.name, pred.name, a1.name}
              end
            end
          end
        end
      end

      triples.each do |h, r, t|
        init_entity(h)
        init_entity(t)
        init_relation(r)
      end

      triples
    end
  end

  # Initialize the NeuralSymbolic subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing NeuralSymbolic subsystem...")
    CogUtil::Logger.info("NeuralSymbolic subsystem initialized successfully")
  end
end
