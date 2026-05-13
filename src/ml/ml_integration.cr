# Machine Learning Integration for CrystalCog
#
# This module provides integration with machine learning frameworks,
# enabling neural network-based learning and prediction within the
# CogPrime cognitive architecture.
#
# References:
# - Neural-Symbolic Integration: https://arxiv.org/abs/1905.06088
# - Differentiable Neural Computers: https://arxiv.org/abs/1610.06258

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module ML
  VERSION = "0.1.0"

  # Exception classes
  class MLException < Exception
  end

  class TrainingException < MLException
  end

  class PredictionException < MLException
  end

  # Represents training data
  struct TrainingData
    getter inputs : Array(Array(Float64))
    getter outputs : Array(Array(Float64))

    def initialize(@inputs : Array(Array(Float64)), @outputs : Array(Array(Float64)))
      if @inputs.size != @outputs.size
        raise MLException.new("Input and output sizes must match")
      end
    end

    def size : Int32
      @inputs.size
    end

    def shuffle : TrainingData
      indices = (0...size).to_a.shuffle
      shuffled_inputs = indices.map { |i| @inputs[i] }
      shuffled_outputs = indices.map { |i| @outputs[i] }
      TrainingData.new(shuffled_inputs, shuffled_outputs)
    end

    def split(ratio : Float64 = 0.8) : Tuple(TrainingData, TrainingData)
      split_idx = (size * ratio).to_i

      train = TrainingData.new(@inputs[0...split_idx], @outputs[0...split_idx])
      test = TrainingData.new(@inputs[split_idx..-1], @outputs[split_idx..-1])

      {train, test}
    end
  end

  # Activation functions
  module Activation
    def self.sigmoid(x : Float64) : Float64
      1.0 / (1.0 + Math.exp(-x))
    end

    def self.sigmoid_derivative(y : Float64) : Float64
      y * (1.0 - y)
    end

    def self.tanh(x : Float64) : Float64
      Math.tanh(x)
    end

    def self.tanh_derivative(y : Float64) : Float64
      1.0 - y * y
    end

    def self.relu(x : Float64) : Float64
      x > 0 ? x : 0.0
    end

    def self.relu_derivative(x : Float64) : Float64
      x > 0 ? 1.0 : 0.0
    end

    def self.softmax(x : Array(Float64)) : Array(Float64)
      max_x = x.max
      exp_x = x.map { |v| Math.exp(v - max_x) }
      sum_exp = exp_x.sum
      exp_x.map { |v| v / sum_exp }
    end
  end

  # Loss functions
  module Loss
    def self.mean_squared_error(predicted : Array(Float64),
                                actual : Array(Float64)) : Float64
      if predicted.size != actual.size
        raise MLException.new("Predicted and actual arrays must have same size")
      end

      sum = 0.0
      predicted.zip(actual).each do |p, a|
        diff = p - a
        sum += diff * diff
      end
      sum / predicted.size
    end

    def self.cross_entropy(predicted : Array(Float64),
                           actual : Array(Float64)) : Float64
      if predicted.size != actual.size
        raise MLException.new("Predicted and actual arrays must have same size")
      end

      sum = 0.0
      predicted.zip(actual).each do |p, a|
        # Avoid log(0)
        p_safe = p.clamp(1e-10, 1.0 - 1e-10)
        sum -= a * Math.log(p_safe)
      end
      sum
    end
  end

  # Integration with AtomSpace
  module AtomSpaceIntegration
    # Convert AtomSpace atoms to ML features
    def self.atoms_to_features(atoms : Array(AtomSpace::Atom)) : Array(Float64)
      features = [] of Float64

      atoms.each do |atom|
        # Encode atom type
        features << atom.type.value.to_f

        # Encode truth value
        if tv = atom.truth_value
          features << tv.strength
          features << tv.confidence
        else
          features << 0.0
          features << 0.0
        end

        # Encode name hash (normalized)
        name_hash = atom.name.hash.abs.to_f
        features << (name_hash % 1000) / 1000.0

        # Encode connectivity
        features << atom.outgoing.size.to_f / 10.0
      end

      features
    end

    # Create atom from ML prediction
    def self.prediction_to_atom(prediction : Array(Float64),
                                atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil if prediction.size < 4

      # Decode atom type (simplified — map to the nearest valid enum member)
      atom_type_idx = prediction[0].to_i
      atom_type = AtomSpace::AtomType.from_value?(atom_type_idx) || AtomSpace::AtomType::CONCEPT_NODE

      # Decode truth value
      strength = prediction[1].clamp(0.0, 1.0)
      confidence = prediction[2].clamp(0.0, 1.0)
      tv = AtomSpace::SimpleTruthValue.new(strength, confidence)

      # Create atom (simplified - would need more sophisticated decoding)
      atomspace.add_node(atom_type, "ml_generated_#{Random.rand(1000)}", tv)
    end

    # Build training data from AtomSpace patterns
    def self.build_training_data(atomspace : AtomSpace::AtomSpace,
                                 pattern_type : AtomSpace::AtomType,
                                 target_type : AtomSpace::AtomType) : TrainingData
      inputs = [] of Array(Float64)
      outputs = [] of Array(Float64)

      # Get patterns
      patterns = atomspace.get_atoms_by_type(pattern_type)
      targets = atomspace.get_atoms_by_type(target_type)

      # Create input-output pairs
      patterns.each do |pattern|
        input_features = atoms_to_features([pattern])

        # Find related target (simplified)
        targets.each do |target|
          output_features = atoms_to_features([target])

          inputs << input_features
          outputs << output_features
        end
      end

      TrainingData.new(inputs, outputs)
    end
  end

  # Simple predictor interface
  module Predictor
    abstract def predict(input : Array(Float64)) : Array(Float64)
    abstract def train(data : TrainingData, epochs : Int32 = 100)
  end

  # Online learning interface
  module OnlineLearner
    abstract def update(input : Array(Float64), target : Array(Float64))
    abstract def predict(input : Array(Float64)) : Array(Float64)
  end

  # Model evaluation metrics
  module Metrics
    def self.accuracy(predictions : Array(Array(Float64)),
                      actuals : Array(Array(Float64))) : Float64
      correct = 0

      predictions.zip(actuals).each do |pred, actual|
        pred_class = pred.index(pred.max) || 0
        actual_class = actual.index(actual.max) || 0
        correct += 1 if pred_class == actual_class
      end

      correct.to_f / predictions.size
    end

    def self.precision_recall(predictions : Array(Array(Float64)),
                              actuals : Array(Array(Float64)),
                              threshold : Float64 = 0.5) : Tuple(Float64, Float64)
      true_positives = 0
      false_positives = 0
      false_negatives = 0

      predictions.zip(actuals).each do |pred, actual|
        pred.zip(actual).each do |p, a|
          if p >= threshold && a >= threshold
            true_positives += 1
          elsif p >= threshold && a < threshold
            false_positives += 1
          elsif p < threshold && a >= threshold
            false_negatives += 1
          end
        end
      end

      precision = true_positives.to_f / (true_positives + false_positives + 1e-10)
      recall = true_positives.to_f / (true_positives + false_negatives + 1e-10)

      {precision, recall}
    end

    def self.f1_score(predictions : Array(Array(Float64)),
                      actuals : Array(Array(Float64))) : Float64
      precision, recall = precision_recall(predictions, actuals)
      2.0 * (precision * recall) / (precision + recall + 1e-10)
    end
  end

  # Initialize ML subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing ML subsystem...")
    CogUtil::Logger.info("ML subsystem initialized successfully")
  end
end
