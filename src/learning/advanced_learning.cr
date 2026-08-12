# Advanced learning capabilities for CrystalCog
# Supervised, reinforcement, online, transfer, and curriculum learning

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./concept_learning"

module Learning
  module Advanced
    VERSION = "0.1.0"

    class LearningException < Exception
    end

    # Labeled example for supervised learning
    struct LabeledExample
      getter features : Hash(String, Float64)
      getter label : String

      def initialize(@features : Hash(String, Float64), @label : String)
      end
    end

    # Simple supervised learner: nearest-centroid classifier over feature space
    class SupervisedLearner
      getter centroids : Hash(String, Hash(String, Float64))
      getter counts : Hash(String, Int32)

      def initialize
        @centroids = {} of String => Hash(String, Float64)
        @counts = Hash(String, Int32).new(0)
      end

      def train(examples : Array(LabeledExample))
        examples.each { |ex| partial_fit(ex) }
      end

      def partial_fit(example : LabeledExample)
        label = example.label
        @counts[label] = @counts[label] + 1
        n = @counts[label]

        centroid = @centroids[label]? || ({} of String => Float64)
        example.features.each do |k, v|
          old = centroid[k]? || 0.0
          centroid[k] = old + (v - old) / n.to_f
        end
        @centroids[label] = centroid
      end

      def predict(features : Hash(String, Float64)) : String?
        return nil if @centroids.empty?

        best_label = nil.as(String?)
        best_dist = Float64::INFINITY

        @centroids.each do |label, centroid|
          dist = euclidean(features, centroid)
          if dist < best_dist
            best_dist = dist
            best_label = label
          end
        end

        best_label
      end

      def accuracy(examples : Array(LabeledExample)) : Float64
        return 0.0 if examples.empty?
        correct = examples.count { |ex| predict(ex.features) == ex.label }
        correct.to_f / examples.size
      end

      # Export labels as concept nodes with confidence = inverse distance score
      def to_atomspace(atomspace : AtomSpace::AtomSpace) : Int32
        count = 0
        @centroids.each do |label, _|
          conf = Math.min(1.0, @counts[label].to_f / 10.0)
          atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            "learned_#{label}",
            AtomSpace::SimpleTruthValue.new(conf, 0.9)
          )
          count += 1
        end
        count
      end

      private def euclidean(a : Hash(String, Float64), b : Hash(String, Float64)) : Float64
        keys = (a.keys + b.keys).uniq
        sum = keys.sum do |k|
          da = a[k]? || 0.0
          db = b[k]? || 0.0
          (da - db) ** 2
        end
        Math.sqrt(sum)
      end
    end

    # Tabular Q-learning for discrete reinforcement learning
    class ReinforcementLearner
      getter q_table : Hash(String, Hash(String, Float64))
      getter learning_rate : Float64
      getter discount : Float64
      getter epsilon : Float64

      def initialize(@learning_rate : Float64 = 0.1, @discount : Float64 = 0.9, @epsilon : Float64 = 0.1)
        raise LearningException.new("learning_rate must be in (0,1]") unless @learning_rate > 0.0 && @learning_rate <= 1.0
        @q_table = Hash(String, Hash(String, Float64)).new { |h, k| h[k] = Hash(String, Float64).new(0.0) }
      end

      def q_value(state : String, action : String) : Float64
        @q_table[state][action]
      end

      def available_actions(state : String) : Array(String)
        @q_table[state].keys
      end

      def ensure_actions(state : String, actions : Array(String))
        # Materialize default Q=0.0 entries so actions appear in keys
        actions.each do |a|
          @q_table[state][a] = @q_table[state][a]? || 0.0
        end
      end

      # Epsilon-greedy action selection
      def select_action(state : String, actions : Array(String)) : String
        raise LearningException.new("no actions") if actions.empty?
        ensure_actions(state, actions)

        if Random.rand < @epsilon
          actions.sample
        else
          actions.max_by { |a| q_value(state, a) }
        end
      end

      # Q-learning update: Q(s,a) <- Q + α[r + γ max Q(s',a') - Q]
      def update(state : String, action : String, reward : Float64, next_state : String, next_actions : Array(String))
        ensure_actions(state, [action])
        ensure_actions(next_state, next_actions) unless next_actions.empty?

        max_next = next_actions.empty? ? 0.0 : next_actions.max_of { |a| q_value(next_state, a) }
        old = q_value(state, action)
        td_target = reward + @discount * max_next
        @q_table[state][action] = old + @learning_rate * (td_target - old)
      end

      def best_action(state : String) : String?
        actions = available_actions(state)
        return nil if actions.empty?
        actions.max_by { |a| q_value(state, a) }
      end

      def policy : Hash(String, String)
        result = {} of String => String
        @q_table.each do |state, actions|
          next if actions.empty?
          result[state] = actions.max_by { |_, v| v }[0]
        end
        result
      end
    end

    # Online learner: incremental updates with a sliding window of recent examples
    class OnlineLearner
      getter window_size : Int32
      getter supervised : SupervisedLearner
      @window : Deque(LabeledExample)
      getter updates : Int64

      def initialize(@window_size : Int32 = 100)
        raise LearningException.new("window_size must be positive") if @window_size <= 0
        @supervised = SupervisedLearner.new
        @window = Deque(LabeledExample).new
        @updates = 0_i64
      end

      def observe(example : LabeledExample)
        @window << example
        if @window.size > @window_size
          @window.shift
        end
        @supervised.partial_fit(example)
        @updates += 1
      end

      def predict(features : Hash(String, Float64)) : String?
        @supervised.predict(features)
      end

      def window_count : Int32
        @window.size
      end

      def recent_accuracy : Float64
        @supervised.accuracy(@window.to_a)
      end
    end

    # Transfer learning: reuse source centroids for a related target domain
    class TransferLearner
      getter source : SupervisedLearner
      getter target : SupervisedLearner
      getter feature_map : Hash(String, String)
      getter transfer_weight : Float64

      def initialize(@source : SupervisedLearner,
                     @feature_map : Hash(String, String) = {} of String => String,
                     @transfer_weight : Float64 = 0.5)
        @target = SupervisedLearner.new
      end

      # Initialize target centroids from source with optional feature renaming
      def transfer_knowledge
        @source.centroids.each do |label, centroid|
          mapped = {} of String => Float64
          centroid.each do |feat, val|
            new_feat = @feature_map[feat]? || feat
            mapped[new_feat] = val * @transfer_weight
          end
          # Seed target with one synthetic example per feature dimension
          next if mapped.empty?
          @target.partial_fit(LabeledExample.new(mapped, label))
        end
      end

      def fine_tune(examples : Array(LabeledExample))
        @target.train(examples)
      end

      def predict(features : Hash(String, Float64)) : String?
        @target.predict(features)
      end
    end

    # Curriculum learning: present examples in increasing difficulty order
    class CurriculumLearner
      getter supervised : SupervisedLearner
      getter difficulty_fn : LabeledExample -> Float64

      def initialize(@difficulty_fn : LabeledExample -> Float64 = ->(ex : LabeledExample) { ex.features.values.sum.abs })
        @supervised = SupervisedLearner.new
      end

      # Sort by difficulty ascending, then train in stages
      def train_curriculum(examples : Array(LabeledExample), stages : Int32 = 3)
        raise LearningException.new("stages must be positive") if stages <= 0
        return if examples.empty?

        sorted = examples.sort_by { |ex| @difficulty_fn.call(ex) }
        stage_size = (sorted.size + stages - 1) // stages

        (1..stages).each do |stage|
          subset = sorted.first(stage * stage_size)
          @supervised.train(subset)
          CogUtil::Logger.info("CurriculumLearner", "Stage #{stage}/#{stages}: trained on #{subset.size} examples")
        end
      end

      def predict(features : Hash(String, Float64)) : String?
        @supervised.predict(features)
      end

      def accuracy(examples : Array(LabeledExample)) : Float64
        @supervised.accuracy(examples)
      end
    end
  end
end
