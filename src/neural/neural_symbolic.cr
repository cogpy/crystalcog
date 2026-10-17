# Neural-Symbolic Integration Module for CrystalCog
#
# This module provides integration between neural network models and
# symbolic reasoning systems including:
# - Neural network abstraction layer
# - Symbol grounding and embedding
# - Neural-symbolic hybrid reasoning
# - Knowledge graph embeddings
# - Neuro-symbolic program synthesis
#
# References:
# - Neural-Symbolic Integration: Garcez, Lamb, Gabbay 2009
# - Logic Tensor Networks: Serafini & d'Avila Garcez 2016
# - Neural Theorem Provers: Rocktäschel & Riedel 2017

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../pln/pln"

module Neural
  VERSION = "0.1.0"

  # Exception classes
  class NeuralException < Exception
  end

  class ModelLoadException < NeuralException
  end

  class InferenceException < NeuralException
  end

  class EmbeddingException < NeuralException
  end

  # Tensor representation
  class Tensor
    getter shape : Array(Int32)
    getter data : Array(Float64)
    getter dtype : String

    def initialize(@shape : Array(Int32), @dtype : String = "float64")
      size = @shape.reduce(1) { |acc, dim| acc * dim }
      @data = Array(Float64).new(size, 0.0)
    end

    def initialize(@shape : Array(Int32), @data : Array(Float64), @dtype : String = "float64")
      expected_size = @shape.reduce(1) { |acc, dim| acc * dim }
      raise NeuralException.new("Data size mismatch") if @data.size != expected_size
    end

    def self.zeros(shape : Array(Int32)) : Tensor
      new(shape)
    end

    def self.ones(shape : Array(Int32)) : Tensor
      size = shape.reduce(1) { |acc, dim| acc * dim }
      new(shape, Array(Float64).new(size, 1.0))
    end

    def self.random(shape : Array(Int32), min : Float64 = 0.0, max : Float64 = 1.0) : Tensor
      size = shape.reduce(1) { |acc, dim| acc * dim }
      data = Array(Float64).new(size) { Random.rand * (max - min) + min }
      new(shape, data)
    end

    def self.from_array(data : Array(Float64)) : Tensor
      new([data.size], data)
    end

    def size : Int32
      @data.size
    end

    def ndim : Int32
      @shape.size
    end

    def [](index : Int32) : Float64
      @data[index]
    end

    def []=(index : Int32, value : Float64)
      @data[index] = value
    end

    def +(other : Tensor) : Tensor
      raise NeuralException.new("Shape mismatch") unless @shape == other.shape
      Tensor.new(@shape, @data.zip(other.data).map { |a, b| a + b })
    end

    def -(other : Tensor) : Tensor
      raise NeuralException.new("Shape mismatch") unless @shape == other.shape
      Tensor.new(@shape, @data.zip(other.data).map { |a, b| a - b })
    end

    def *(scalar : Float64) : Tensor
      Tensor.new(@shape, @data.map { |x| x * scalar })
    end

    def dot(other : Tensor) : Float64
      raise NeuralException.new("Dot product requires same size") unless size == other.size
      @data.zip(other.data).sum { |a, b| a * b }
    end

    def norm : Float64
      Math.sqrt(@data.sum { |x| x * x })
    end

    def normalize : Tensor
      n = norm
      return self if n == 0.0
      self * (1.0 / n)
    end

    def softmax : Tensor
      max_val = @data.max
      exp_data = @data.map { |x| Math.exp(x - max_val) }
      sum = exp_data.sum
      Tensor.new(@shape, exp_data.map { |x| x / sum })
    end

    def argmax : Int32
      @data.each_with_index.max_by { |val, _| val }[1]
    end

    def to_array : Array(Float64)
      @data.dup
    end

    def reshape(new_shape : Array(Int32)) : Tensor
      expected_size = new_shape.reduce(1) { |acc, dim| acc * dim }
      raise NeuralException.new("Reshape size mismatch") if expected_size != size
      Tensor.new(new_shape, @data.dup)
    end

    def cosine_similarity(other : Tensor) : Float64
      dot(other) / (norm * other.norm + 1e-10)
    end
  end

  # Activation functions
  module Activation
    def self.relu(x : Float64) : Float64
      x > 0 ? x : 0.0
    end

    def self.sigmoid(x : Float64) : Float64
      1.0 / (1.0 + Math.exp(-x))
    end

    def self.tanh(x : Float64) : Float64
      Math.tanh(x)
    end

    def self.softplus(x : Float64) : Float64
      Math.log(1.0 + Math.exp(x))
    end

    def self.apply(tensor : Tensor, func : Symbol) : Tensor
      f = case func
          when :relu    then ->(x : Float64) { relu(x) }
          when :sigmoid then ->(x : Float64) { sigmoid(x) }
          when :tanh    then ->(x : Float64) { tanh(x) }
          else               ->(x : Float64) { x }
          end

      Tensor.new(tensor.shape, tensor.data.map { |x| f.call(x) })
    end
  end

  # Abstract neural network layer
  abstract class Layer
    getter name : String
    getter input_size : Int32
    getter output_size : Int32

    def initialize(@name : String, @input_size : Int32, @output_size : Int32)
    end

    abstract def forward(input : Tensor) : Tensor
    abstract def parameters : Array(Tensor)
  end

  # Dense (fully connected) layer
  class DenseLayer < Layer
    getter weights : Tensor
    getter bias : Tensor
    getter activation : Symbol

    def initialize(name : String, input_size : Int32, output_size : Int32,
                   @activation : Symbol = :none)
      super(name, input_size, output_size)
      # Xavier initialization
      scale = Math.sqrt(2.0 / (input_size + output_size))
      @weights = Tensor.random([input_size, output_size], -scale, scale)
      @bias = Tensor.zeros([output_size])
    end

    def forward(input : Tensor) : Tensor
      raise NeuralException.new("Input size mismatch") if input.size != @input_size

      # Matrix-vector multiplication
      output_data = Array(Float64).new(@output_size, 0.0)
      @output_size.times do |j|
        sum = @bias[j]
        @input_size.times do |i|
          sum += input[i] * @weights[i * @output_size + j]
        end
        output_data[j] = sum
      end

      output = Tensor.new([@output_size], output_data)
      Activation.apply(output, @activation)
    end

    def parameters : Array(Tensor)
      [@weights, @bias]
    end

    def set_weights(weights : Tensor, bias : Tensor)
      @weights = weights
      @bias = bias
    end
  end

  # Embedding layer for symbol to vector conversion
  class EmbeddingLayer < Layer
    getter embeddings : Hash(String, Tensor)
    getter embedding_dim : Int32

    def initialize(name : String, @embedding_dim : Int32, vocab_size : Int32 = 0)
      super(name, 1, @embedding_dim)
      @embeddings = {} of String => Tensor
    end

    def forward(input : Tensor) : Tensor
      # For embedding lookup, input is expected to be an index
      raise NeuralException.new("Embedding lookup requires single value") if input.size != 1
      # Return zero vector if not found
      Tensor.zeros([@embedding_dim])
    end

    def embed(symbol : String) : Tensor
      @embeddings[symbol]? || initialize_embedding(symbol)
    end

    def add_embedding(symbol : String, vector : Tensor)
      raise EmbeddingException.new("Dimension mismatch") if vector.size != @embedding_dim
      @embeddings[symbol] = vector
    end

    def has_embedding?(symbol : String) : Bool
      @embeddings.has_key?(symbol)
    end

    def similarity(symbol1 : String, symbol2 : String) : Float64
      embed(symbol1).cosine_similarity(embed(symbol2))
    end

    def nearest_neighbors(symbol : String, k : Int32 = 5) : Array(Tuple(String, Float64))
      target = embed(symbol)
      similarities = @embeddings.map do |s, v|
        {s, target.cosine_similarity(v)}
      end
      similarities.sort_by { |_, sim| -sim }.first(k)
    end

    def parameters : Array(Tensor)
      @embeddings.values
    end

    private def initialize_embedding(symbol : String) : Tensor
      embedding = Tensor.random([@embedding_dim], -0.1, 0.1)
      @embeddings[symbol] = embedding
      embedding
    end
  end

  # Simple feedforward neural network
  class NeuralNetwork
    getter layers : Array(Layer)
    getter name : String

    def initialize(@name : String)
      @layers = [] of Layer
      CogUtil::Logger.info("NeuralNetwork '#{@name}' created")
    end

    def add_layer(layer : Layer)
      @layers << layer
    end

    def forward(input : Tensor) : Tensor
      @layers.reduce(input) { |x, layer| layer.forward(x) }
    end

    def predict(input : Array(Float64)) : Array(Float64)
      forward(Tensor.from_array(input)).to_array
    end

    def parameters : Array(Tensor)
      @layers.flat_map(&.parameters)
    end
  end

  # Symbol grounding - maps symbols to neural representations
  class SymbolGrounder
    getter embeddings : EmbeddingLayer
    getter atomspace : AtomSpace::AtomSpace
    @concept_cache : Hash(String, Tensor)

    def initialize(@atomspace : AtomSpace::AtomSpace, embedding_dim : Int32 = 128)
      @embeddings = EmbeddingLayer.new("symbol_embeddings", embedding_dim)
      @concept_cache = {} of String => Tensor
      CogUtil::Logger.info("SymbolGrounder initialized with dim=#{embedding_dim}")
    end

    # Ground a concept node to its embedding
    def ground(atom : AtomSpace::Atom) : Tensor
      key = atom_key(atom)

      if cached = @concept_cache[key]?
        return cached
      end

      embedding = case atom
                  when AtomSpace::Node
                    ground_node(atom)
                  when AtomSpace::Link
                    ground_link(atom)
                  else
                    Tensor.zeros([@embeddings.embedding_dim])
                  end

      @concept_cache[key] = embedding
      embedding
    end

    # Learn embeddings from AtomSpace structure
    def learn_embeddings(iterations : Int32 = 100, learning_rate : Float64 = 0.01)
      CogUtil::Logger.info("Learning embeddings from AtomSpace...")

      atoms = @atomspace.get_all_atoms

      iterations.times do |iter|
        atoms.each do |atom|
          if atom.is_a?(AtomSpace::Link)
            update_link_embeddings(atom, learning_rate)
          end
        end

        if (iter + 1) % 10 == 0
          CogUtil::Logger.debug("Embedding iteration #{iter + 1}/#{iterations}")
        end
      end

      CogUtil::Logger.info("Embedding learning complete")
    end

    # Find similar concepts
    def similar_concepts(concept : String, k : Int32 = 5) : Array(Tuple(String, Float64))
      @embeddings.nearest_neighbors(concept, k)
    end

    # Analogy completion: A is to B as C is to ?
    def analogy(a : String, b : String, c : String, k : Int32 = 1) : Array(Tuple(String, Float64))
      # vector(B) - vector(A) + vector(C)
      vec_a = @embeddings.embed(a)
      vec_b = @embeddings.embed(b)
      vec_c = @embeddings.embed(c)

      target = vec_b - vec_a + vec_c

      # Find nearest to target
      similarities = @embeddings.embeddings.map do |symbol, vec|
        next {symbol, -1.0} if symbol == a || symbol == b || symbol == c
        {symbol, target.cosine_similarity(vec)}
      end

      similarities.sort_by { |_, sim| -sim }.first(k)
    end

    private def atom_key(atom : AtomSpace::Atom) : String
      case atom
      when AtomSpace::Node
        "#{atom.type}:#{atom.name}"
      when AtomSpace::Link
        "#{atom.type}:[#{atom.outgoing.map { |a| atom_key(a) }.join(",")}]"
      else
        "unknown"
      end
    end

    private def ground_node(node : AtomSpace::Node) : Tensor
      @embeddings.embed(node.name)
    end

    private def ground_link(link : AtomSpace::Link) : Tensor
      # Compose embeddings of outgoing atoms
      if link.outgoing.empty?
        return Tensor.zeros([@embeddings.embedding_dim])
      end

      # Average of outgoing embeddings + link type embedding
      outgoing_embeddings = link.outgoing.map { |a| ground(a) }

      sum = outgoing_embeddings.reduce(Tensor.zeros([@embeddings.embedding_dim])) { |acc, e| acc + e }
      avg = sum * (1.0 / outgoing_embeddings.size)

      type_embedding = @embeddings.embed(link.type.to_s)
      (avg + type_embedding) * 0.5
    end

    private def update_link_embeddings(link : AtomSpace::Link, lr : Float64)
      return if link.outgoing.size < 2

      # Links define relations: make related concepts closer in embedding space
      link.outgoing.each_with_index do |atom1, i|
        link.outgoing.each_with_index do |atom2, j|
          next if i >= j

          key1 = atom_key(atom1)
          key2 = atom_key(atom2)

          if atom1.is_a?(AtomSpace::Node) && atom2.is_a?(AtomSpace::Node)
            emb1 = @embeddings.embed(atom1.name)
            emb2 = @embeddings.embed(atom2.name)

            # Move embeddings closer together
            diff = emb2 - emb1
            update = diff * (lr * 0.1)

            @embeddings.add_embedding(atom1.name, emb1 + update)
            @embeddings.add_embedding(atom2.name, emb2 - update)
          end
        end
      end
    end
  end

  # Knowledge Graph Embedding (TransE-style)
  class KnowledgeGraphEmbedding
    getter entity_embeddings : EmbeddingLayer
    getter relation_embeddings : EmbeddingLayer
    getter embedding_dim : Int32
    @margin : Float64

    def initialize(@embedding_dim : Int32 = 128, @margin : Float64 = 1.0)
      @entity_embeddings = EmbeddingLayer.new("entities", @embedding_dim)
      @relation_embeddings = EmbeddingLayer.new("relations", @embedding_dim)
      CogUtil::Logger.info("KnowledgeGraphEmbedding initialized")
    end

    # Score a triple (head, relation, tail)
    # Lower score = more likely to be true
    def score(head : String, relation : String, tail : String) : Float64
      h = @entity_embeddings.embed(head)
      r = @relation_embeddings.embed(relation)
      t = @entity_embeddings.embed(tail)

      # TransE scoring: ||h + r - t||
      (h + r - t).norm
    end

    # Train on a set of triples
    def train(triples : Array(Tuple(String, String, String)),
              epochs : Int32 = 100,
              learning_rate : Float64 = 0.01,
              negative_samples : Int32 = 5)
      CogUtil::Logger.info("Training KGE on #{triples.size} triples...")

      entities = triples.flat_map { |h, _, t| [h, t] }.uniq
      relations = triples.map { |_, r, _| r }.uniq

      epochs.times do |epoch|
        total_loss = 0.0

        triples.each do |head, relation, tail|
          # Positive sample
          pos_score = score(head, relation, tail)

          # Negative samples (corrupt head or tail)
          negative_samples.times do
            if Random.rand < 0.5
              neg_head = entities.sample
              neg_score = score(neg_head, relation, tail)
            else
              neg_tail = entities.sample
              neg_score = score(head, relation, neg_tail)
            end

            # Margin-based loss
            loss = @margin + pos_score - neg_score
            if loss > 0
              total_loss += loss
              update_embeddings(head, relation, tail, learning_rate)
            end
          end
        end

        if (epoch + 1) % 10 == 0
          CogUtil::Logger.debug("Epoch #{epoch + 1}: loss = #{total_loss / triples.size}")
        end
      end

      CogUtil::Logger.info("KGE training complete")
    end

    # Predict missing tail: (head, relation, ?)
    def predict_tail(head : String, relation : String, k : Int32 = 5) : Array(Tuple(String, Float64))
      @entity_embeddings.embeddings.keys.map do |entity|
        {entity, -score(head, relation, entity)}  # Negate for descending sort
      end.sort_by { |_, s| -s }.first(k)
    end

    # Predict missing head: (?, relation, tail)
    def predict_head(relation : String, tail : String, k : Int32 = 5) : Array(Tuple(String, Float64))
      @entity_embeddings.embeddings.keys.map do |entity|
        {entity, -score(entity, relation, tail)}
      end.sort_by { |_, s| -s }.first(k)
    end

    # Predict relation: (head, ?, tail)
    def predict_relation(head : String, tail : String, k : Int32 = 5) : Array(Tuple(String, Float64))
      @relation_embeddings.embeddings.keys.map do |relation|
        {relation, -score(head, relation, tail)}
      end.sort_by { |_, s| -s }.first(k)
    end

    private def update_embeddings(head : String, relation : String, tail : String, lr : Float64)
      h = @entity_embeddings.embed(head)
      r = @relation_embeddings.embed(relation)
      t = @entity_embeddings.embed(tail)

      # Gradient of ||h + r - t||
      diff = h + r - t
      norm = diff.norm
      return if norm == 0

      gradient = diff * (1.0 / norm)

      # Update embeddings
      @entity_embeddings.add_embedding(head, (h - gradient * lr).normalize)
      @relation_embeddings.add_embedding(relation, (r - gradient * lr).normalize)
      @entity_embeddings.add_embedding(tail, (t + gradient * lr).normalize)
    end
  end

  # Neural-Symbolic Reasoner - combines neural predictions with symbolic inference
  class NeuralSymbolicReasoner
    getter atomspace : AtomSpace::AtomSpace
    getter symbol_grounder : SymbolGrounder
    getter kg_embedding : KnowledgeGraphEmbedding
    getter neural_threshold : Float64

    def initialize(@atomspace : AtomSpace::AtomSpace,
                   embedding_dim : Int32 = 128,
                   @neural_threshold : Float64 = 0.7)
      @symbol_grounder = SymbolGrounder.new(@atomspace, embedding_dim)
      @kg_embedding = KnowledgeGraphEmbedding.new(embedding_dim)
      CogUtil::Logger.info("NeuralSymbolicReasoner initialized")
    end

    # Train neural components from atomspace
    def train_from_atomspace(epochs : Int32 = 100)
      CogUtil::Logger.info("Training neural components from AtomSpace...")

      # Extract triples from links
      triples = extract_triples

      if triples.empty?
        CogUtil::Logger.warn("No triples found for training")
        return
      end

      # Train KGE
      @kg_embedding.train(triples, epochs)

      # Learn symbol embeddings
      @symbol_grounder.learn_embeddings(epochs)

      CogUtil::Logger.info("Neural training complete")
    end

    # Hybrid inference - combines neural predictions with symbolic reasoning
    def infer(query : AtomSpace::Atom) : Array(InferenceResult)
      results = [] of InferenceResult

      case query
      when AtomSpace::Link
        # Try neural prediction first
        neural_results = neural_inference(query)
        results.concat(neural_results)

        # Then do symbolic inference for validation
        symbolic_results = symbolic_inference(query)

        # Merge results, boosting confidence when both agree
        merged = merge_results(neural_results, symbolic_results)
        results.concat(merged)
      when AtomSpace::Node
        # For nodes, find related concepts
        similar = @symbol_grounder.similar_concepts(query.name, 10)
        similar.each do |concept, similarity|
          if similarity >= @neural_threshold
            results << InferenceResult.new(
              concept,
              similarity,
              InferenceSource::NEURAL
            )
          end
        end
      end

      results.sort_by { |r| -r.confidence }
    end

    # Complete a partial triple using neural predictions
    def complete_triple(head : String?, relation : String?, tail : String?) : Array(Tuple(String, Float64))
      if head && relation && tail.nil?
        @kg_embedding.predict_tail(head, relation)
      elsif head.nil? && relation && tail
        @kg_embedding.predict_head(relation, tail)
      elsif head && relation.nil? && tail
        @kg_embedding.predict_relation(head, tail)
      else
        [] of Tuple(String, Float64)
      end
    end

    # Check if a triple is likely true
    def is_likely_true?(head : String, relation : String, tail : String) : Bool
      score = @kg_embedding.score(head, relation, tail)
      score < 2.0  # Lower TransE score = more likely
    end

    # Add neural predictions to atomspace
    def materialize_predictions(min_confidence : Float64 = 0.8)
      CogUtil::Logger.info("Materializing neural predictions to AtomSpace...")

      entities = @kg_embedding.entity_embeddings.embeddings.keys
      relations = @kg_embedding.relation_embeddings.embeddings.keys

      count = 0
      entities.each do |head|
        relations.each do |relation|
          predictions = complete_triple(head, relation, nil)
          predictions.each do |tail, confidence|
            next if confidence < min_confidence

            # Add predicted link to atomspace
            head_node = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, head)
            tail_node = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, tail)
            rel_node = @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, relation)

            @atomspace.add_link(
              AtomSpace::AtomType::EVALUATION_LINK,
              [rel_node, @atomspace.add_link(
                AtomSpace::AtomType::LIST_LINK,
                [head_node, tail_node]
              )],
              AtomSpace::SimpleTruthValue.new(confidence, 0.8)
            )
            count += 1
          end
        end
      end

      CogUtil::Logger.info("Materialized #{count} predictions")
    end

    private def extract_triples : Array(Tuple(String, String, String))
      triples = [] of Tuple(String, String, String)

      @atomspace.get_all_atoms.each do |atom|
        next unless atom.is_a?(AtomSpace::Link)
        next unless atom.type == AtomSpace::AtomType::EVALUATION_LINK

        outgoing = atom.outgoing
        next unless outgoing.size == 2

        predicate = outgoing[0]
        args = outgoing[1]

        next unless predicate.is_a?(AtomSpace::Node)
        next unless args.is_a?(AtomSpace::Link) && args.type == AtomSpace::AtomType::LIST_LINK

        arg_list = args.outgoing
        next unless arg_list.size == 2
        next unless arg_list[0].is_a?(AtomSpace::Node) && arg_list[1].is_a?(AtomSpace::Node)

        head = arg_list[0].as(AtomSpace::Node).name
        relation = predicate.name
        tail = arg_list[1].as(AtomSpace::Node).name

        triples << {head, relation, tail}
      end

      triples
    end

    private def neural_inference(query : AtomSpace::Link) : Array(InferenceResult)
      results = [] of InferenceResult

      if query.type == AtomSpace::AtomType::EVALUATION_LINK
        outgoing = query.outgoing
        return results unless outgoing.size == 2

        predicate = outgoing[0]
        args = outgoing[1]

        return results unless predicate.is_a?(AtomSpace::Node)
        return results unless args.is_a?(AtomSpace::Link)

        arg_list = args.outgoing
        return results unless arg_list.size == 2

        if arg_list[0].is_a?(AtomSpace::Node) && arg_list[1].is_a?(AtomSpace::Node)
          head = arg_list[0].as(AtomSpace::Node).name
          relation = predicate.name
          tail = arg_list[1].as(AtomSpace::Node).name

          score = @kg_embedding.score(head, relation, tail)
          confidence = 1.0 / (1.0 + score)  # Convert score to confidence

          if confidence >= @neural_threshold
            results << InferenceResult.new(
              "#{head} #{relation} #{tail}",
              confidence,
              InferenceSource::NEURAL
            )
          end
        end
      end

      results
    end

    private def symbolic_inference(query : AtomSpace::Link) : Array(InferenceResult)
      # Use existing PLN inference
      results = [] of InferenceResult

      # Check if query already exists in atomspace
      @atomspace.get_all_atoms.each do |atom|
        next unless atom.is_a?(AtomSpace::Link)
        next unless same_structure?(atom, query)

        tv = atom.truth_value
        confidence = tv.strength * tv.confidence

        results << InferenceResult.new(
          atom.to_s,
          confidence,
          InferenceSource::SYMBOLIC
        )
      end

      results
    end

    private def same_structure?(a : AtomSpace::Link, b : AtomSpace::Link) : Bool
      return false unless a.type == b.type
      return false unless a.outgoing.size == b.outgoing.size

      a.outgoing.zip(b.outgoing).all? do |ai, bi|
        case {ai, bi}
        when {AtomSpace::Node, AtomSpace::Node}
          ai.name == bi.name
        when {AtomSpace::Link, AtomSpace::Link}
          same_structure?(ai, bi)
        else
          false
        end
      end
    end

    private def merge_results(neural : Array(InferenceResult),
                              symbolic : Array(InferenceResult)) : Array(InferenceResult)
      merged = [] of InferenceResult

      neural.each do |nr|
        matching = symbolic.find { |sr| sr.result == nr.result }
        if matching
          # Both agree - boost confidence
          combined_confidence = 1.0 - (1.0 - nr.confidence) * (1.0 - matching.confidence)
          merged << InferenceResult.new(
            nr.result,
            combined_confidence,
            InferenceSource::HYBRID
          )
        end
      end

      merged
    end
  end

  # Inference result with source tracking
  enum InferenceSource
    NEURAL
    SYMBOLIC
    HYBRID
  end

  struct InferenceResult
    getter result : String
    getter confidence : Float64
    getter source : InferenceSource

    def initialize(@result : String, @confidence : Float64, @source : InferenceSource)
    end
  end

  # Neuro-Symbolic Program Synthesis
  class ProgramSynthesizer
    getter neural_network : NeuralNetwork
    getter atomspace : AtomSpace::AtomSpace
    @program_templates : Array(ProgramTemplate)

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @neural_network = NeuralNetwork.new("program_synthesizer")
      @program_templates = [] of ProgramTemplate
      setup_network
      CogUtil::Logger.info("ProgramSynthesizer initialized")
    end

    def add_template(template : ProgramTemplate)
      @program_templates << template
    end

    # Synthesize a program from input-output examples
    def synthesize(examples : Array(Tuple(Array(Float64), Array(Float64)))) : ProgramTemplate?
      return nil if examples.empty? || @program_templates.empty?

      best_template : ProgramTemplate? = nil
      best_score = Float64::INFINITY

      @program_templates.each do |template|
        score = evaluate_template(template, examples)
        if score < best_score
          best_score = score
          best_template = template
        end
      end

      best_template
    end

    private def setup_network
      # Simple network for program scoring
      @neural_network.add_layer(DenseLayer.new("hidden1", 64, 32, :relu))
      @neural_network.add_layer(DenseLayer.new("hidden2", 32, 16, :relu))
      @neural_network.add_layer(DenseLayer.new("output", 16, 1, :sigmoid))
    end

    private def evaluate_template(template : ProgramTemplate,
                                  examples : Array(Tuple(Array(Float64), Array(Float64)))) : Float64
      total_error = 0.0

      examples.each do |input, expected_output|
        actual_output = template.execute(input)
        error = expected_output.zip(actual_output).sum { |e, a| (e - a).abs }
        total_error += error
      end

      total_error / examples.size
    end
  end

  # Program template for synthesis
  abstract class ProgramTemplate
    getter name : String

    def initialize(@name : String)
    end

    abstract def execute(input : Array(Float64)) : Array(Float64)
  end

  # Identity program
  class IdentityProgram < ProgramTemplate
    def initialize
      super("identity")
    end

    def execute(input : Array(Float64)) : Array(Float64)
      input.dup
    end
  end

  # Linear transformation program
  class LinearProgram < ProgramTemplate
    getter weights : Array(Float64)
    getter bias : Float64

    def initialize(@weights : Array(Float64), @bias : Float64 = 0.0)
      super("linear")
    end

    def execute(input : Array(Float64)) : Array(Float64)
      result = input.zip(@weights).sum { |x, w| x * w } + @bias
      [result]
    end
  end

  # Module-level convenience methods
  def self.create_tensor(shape : Array(Int32)) : Tensor
    Tensor.zeros(shape)
  end

  def self.create_network(name : String) : NeuralNetwork
    NeuralNetwork.new(name)
  end

  def self.create_reasoner(atomspace : AtomSpace::AtomSpace) : NeuralSymbolicReasoner
    NeuralSymbolicReasoner.new(atomspace)
  end

  def self.create_kg_embedding(dim : Int32 = 128) : KnowledgeGraphEmbedding
    KnowledgeGraphEmbedding.new(dim)
  end
end
