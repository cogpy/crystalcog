require "spec"
require "../../src/ml/ml_integration"

describe ML do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    ML.initialize
  end

  describe "TrainingData" do
    it "creates training data from matching arrays" do
      inputs = [[1.0, 2.0], [3.0, 4.0]]
      outputs = [[0.0], [1.0]]
      data = ML::TrainingData.new(inputs, outputs)
      data.size.should eq(2)
    end

    it "raises when input and output sizes differ" do
      expect_raises(ML::MLException) do
        ML::TrainingData.new([[1.0]], [[0.0], [1.0]])
      end
    end

    it "shuffles data preserving size" do
      inputs = [[1.0], [2.0], [3.0], [4.0], [5.0]]
      outputs = [[1.0], [2.0], [3.0], [4.0], [5.0]]
      data = ML::TrainingData.new(inputs, outputs)
      shuffled = data.shuffle
      shuffled.size.should eq(data.size)
    end

    it "splits data into train and test sets" do
      inputs = (1..10).map { |i| [i.to_f] }
      outputs = (1..10).map { |i| [i.to_f] }
      data = ML::TrainingData.new(inputs, outputs)

      train, test = data.split(0.8)
      train.size.should eq(8)
      test.size.should eq(2)
    end

    it "splits with 0.5 ratio" do
      inputs = [[1.0], [2.0], [3.0], [4.0]]
      outputs = [[1.0], [2.0], [3.0], [4.0]]
      data = ML::TrainingData.new(inputs, outputs)

      train, test = data.split(0.5)
      train.size.should eq(2)
      test.size.should eq(2)
    end
  end

  describe "Activation" do
    describe "sigmoid" do
      it "returns 0.5 for input 0" do
        ML::Activation.sigmoid(0.0).should be_close(0.5, 0.0001)
      end

      it "approaches 1 for large positive inputs" do
        ML::Activation.sigmoid(100.0).should be_close(1.0, 0.0001)
      end

      it "approaches 0 for large negative inputs" do
        ML::Activation.sigmoid(-100.0).should be_close(0.0, 0.0001)
      end

      it "is monotonically increasing" do
        ML::Activation.sigmoid(-1.0).should be < ML::Activation.sigmoid(0.0)
        ML::Activation.sigmoid(0.0).should be < ML::Activation.sigmoid(1.0)
      end
    end

    describe "sigmoid_derivative" do
      it "returns max near 0.25 at x=0.5" do
        ML::Activation.sigmoid_derivative(0.5).should be_close(0.25, 0.0001)
      end

      it "approaches 0 at extremes" do
        ML::Activation.sigmoid_derivative(0.0).should be_close(0.0, 0.0001)
        ML::Activation.sigmoid_derivative(1.0).should be_close(0.0, 0.0001)
      end
    end

    describe "tanh" do
      it "returns 0 for input 0" do
        ML::Activation.tanh(0.0).should be_close(0.0, 0.0001)
      end

      it "approaches 1 for large positive inputs" do
        ML::Activation.tanh(10.0).should be_close(1.0, 0.001)
      end

      it "approaches -1 for large negative inputs" do
        ML::Activation.tanh(-10.0).should be_close(-1.0, 0.001)
      end
    end

    describe "relu" do
      it "passes positive values through" do
        ML::Activation.relu(5.0).should eq(5.0)
      end

      it "returns 0 for negative values" do
        ML::Activation.relu(-3.0).should eq(0.0)
      end

      it "returns 0 for zero" do
        ML::Activation.relu(0.0).should eq(0.0)
      end
    end

    describe "relu_derivative" do
      it "returns 1 for positive input" do
        ML::Activation.relu_derivative(1.0).should eq(1.0)
      end

      it "returns 0 for non-positive input" do
        ML::Activation.relu_derivative(0.0).should eq(0.0)
        ML::Activation.relu_derivative(-1.0).should eq(0.0)
      end
    end

    describe "softmax" do
      it "outputs values that sum to 1" do
        result = ML::Activation.softmax([1.0, 2.0, 3.0])
        result.sum.should be_close(1.0, 0.0001)
      end

      it "assigns highest probability to largest input" do
        result = ML::Activation.softmax([0.0, 0.0, 10.0])
        result[2].should be > result[0]
        result[2].should be > result[1]
      end

      it "handles uniform input" do
        result = ML::Activation.softmax([1.0, 1.0, 1.0])
        result.each { |v| v.should be_close(1.0 / 3.0, 0.0001) }
      end
    end
  end

  describe "Loss" do
    describe "mean_squared_error" do
      it "returns 0 for identical arrays" do
        ML::Loss.mean_squared_error([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]).should eq(0.0)
      end

      it "calculates correct MSE" do
        # MSE([0,0], [1,1]) = (1 + 1) / 2 = 1.0
        ML::Loss.mean_squared_error([0.0, 0.0], [1.0, 1.0]).should be_close(1.0, 0.0001)
      end

      it "raises when sizes differ" do
        expect_raises(ML::MLException) do
          ML::Loss.mean_squared_error([1.0], [1.0, 2.0])
        end
      end

      it "is always non-negative" do
        loss = ML::Loss.mean_squared_error([0.3, 0.7], [0.6, 0.4])
        loss.should be >= 0.0
      end
    end

    describe "cross_entropy" do
      it "returns near 0 for perfect predictions" do
        # Near-perfect prediction: very high confidence for correct class
        loss = ML::Loss.cross_entropy([0.9999], [1.0])
        loss.should be_close(0.0, 0.01)
      end

      it "is always non-negative" do
        loss = ML::Loss.cross_entropy([0.3, 0.7], [0.0, 1.0])
        loss.should be >= 0.0
      end

      it "raises when sizes differ" do
        expect_raises(ML::MLException) do
          ML::Loss.cross_entropy([0.5], [0.5, 0.5])
        end
      end
    end
  end

  describe "AtomSpaceIntegration" do
    it "converts atoms to feature vectors" do
      atomspace = AtomSpace::AtomSpace.new
      atom = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat",
        AtomSpace::SimpleTruthValue.new(0.8, 0.9))

      features = ML::AtomSpaceIntegration.atoms_to_features([atom])
      features.should_not be_empty
      features.size.should be > 0
    end

    it "converts multiple atoms to features" do
      atomspace = AtomSpace::AtomSpace.new
      atom1 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
      atom2 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "animal")

      features = ML::AtomSpaceIntegration.atoms_to_features([atom1, atom2])
      # Should be 2× the features per atom
      features.size.should be > 4
    end

    it "creates atom from prediction" do
      atomspace = AtomSpace::AtomSpace.new
      prediction = [5.0, 0.8, 0.9, 0.5, 0.0, 0.0, 0.0, 0.0]
      atom = ML::AtomSpaceIntegration.prediction_to_atom(prediction, atomspace)
      atom.should_not be_nil
    end

    it "returns nil for too-short prediction" do
      atomspace = AtomSpace::AtomSpace.new
      atom = ML::AtomSpaceIntegration.prediction_to_atom([1.0, 2.0], atomspace)
      atom.should be_nil
    end

    it "builds training data from AtomSpace patterns" do
      atomspace = AtomSpace::AtomSpace.new
      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "cat")
      atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
      atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "is_animal")

      data = ML::AtomSpaceIntegration.build_training_data(
        atomspace,
        AtomSpace::AtomType::CONCEPT_NODE,
        AtomSpace::AtomType::PREDICATE_NODE
      )

      data.should be_a(ML::TrainingData)
    end
  end

  describe "Metrics" do
    describe "accuracy" do
      it "returns 1.0 for perfect predictions" do
        predictions = [[1.0, 0.0], [0.0, 1.0], [1.0, 0.0]]
        actuals = [[1.0, 0.0], [0.0, 1.0], [1.0, 0.0]]
        ML::Metrics.accuracy(predictions, actuals).should eq(1.0)
      end

      it "returns 0.0 for all-wrong predictions" do
        predictions = [[1.0, 0.0], [1.0, 0.0]]
        actuals = [[0.0, 1.0], [0.0, 1.0]]
        ML::Metrics.accuracy(predictions, actuals).should eq(0.0)
      end

      it "returns 0.5 for 50% correct" do
        predictions = [[1.0, 0.0], [1.0, 0.0]]
        actuals = [[1.0, 0.0], [0.0, 1.0]]
        ML::Metrics.accuracy(predictions, actuals).should eq(0.5)
      end
    end

    describe "precision_recall" do
      it "returns high precision and recall for perfect predictions" do
        predictions = [[1.0], [0.0], [1.0]]
        actuals = [[1.0], [0.0], [1.0]]
        precision, recall = ML::Metrics.precision_recall(predictions, actuals)
        precision.should be_close(1.0, 0.001)
        recall.should be_close(1.0, 0.001)
      end

      it "returns values between 0 and 1" do
        predictions = [[0.8, 0.2], [0.3, 0.7]]
        actuals = [[1.0, 0.0], [0.0, 1.0]]
        precision, recall = ML::Metrics.precision_recall(predictions, actuals)
        precision.should be >= 0.0
        precision.should be <= 1.0
        recall.should be >= 0.0
        recall.should be <= 1.0
      end
    end

    describe "f1_score" do
      it "returns 1.0 for perfect predictions" do
        predictions = [[1.0, 0.0], [0.0, 1.0]]
        actuals = [[1.0, 0.0], [0.0, 1.0]]
        f1 = ML::Metrics.f1_score(predictions, actuals)
        f1.should be_close(1.0, 0.001)
      end

      it "returns a value between 0 and 1" do
        predictions = [[0.8, 0.2], [0.4, 0.6]]
        actuals = [[1.0, 0.0], [0.0, 1.0]]
        f1 = ML::Metrics.f1_score(predictions, actuals)
        f1.should be >= 0.0
        f1.should be <= 1.0
      end
    end
  end
end
