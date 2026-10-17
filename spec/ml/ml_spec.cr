require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/ml/ml_main"

describe ML do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe "VERSION" do
    it "has a version number" do
      ML::VERSION.should eq("0.1.0")
    end
  end

  describe ".initialize" do
    it "initializes the ML subsystem" do
      ML.initialize
      true.should be_true
    end
  end
end

describe ML::TrainingData do
  describe "#initialize" do
    it "creates training data with matching sizes" do
      inputs = [[1.0, 2.0], [3.0, 4.0]]
      outputs = [[0.0], [1.0]]
      data = ML::TrainingData.new(inputs, outputs)
      data.size.should eq(2)
    end

    it "raises when sizes don't match" do
      inputs = [[1.0, 2.0], [3.0, 4.0]]
      outputs = [[0.0]]
      expect_raises(ML::MLException) do
        ML::TrainingData.new(inputs, outputs)
      end
    end
  end

  describe "#size" do
    it "returns number of samples" do
      inputs = [[1.0], [2.0], [3.0]]
      outputs = [[0.0], [1.0], [0.0]]
      data = ML::TrainingData.new(inputs, outputs)
      data.size.should eq(3)
    end
  end

  describe "#shuffle" do
    it "returns shuffled copy" do
      inputs = [[1.0], [2.0], [3.0], [4.0], [5.0]]
      outputs = [[0.0], [1.0], [0.0], [1.0], [0.0]]
      data = ML::TrainingData.new(inputs, outputs)
      shuffled = data.shuffle
      shuffled.size.should eq(data.size)
    end
  end

  describe "#split" do
    it "splits data into train and test sets" do
      inputs = [[1.0], [2.0], [3.0], [4.0], [5.0], [6.0], [7.0], [8.0], [9.0], [10.0]]
      outputs = [[0.0], [1.0], [0.0], [1.0], [0.0], [1.0], [0.0], [1.0], [0.0], [1.0]]
      data = ML::TrainingData.new(inputs, outputs)

      train, test = data.split(0.8)
      train.size.should eq(8)
      test.size.should eq(2)
    end

    it "uses default 0.8 ratio" do
      inputs = [[1.0], [2.0], [3.0], [4.0], [5.0]]
      outputs = [[0.0], [1.0], [0.0], [1.0], [0.0]]
      data = ML::TrainingData.new(inputs, outputs)

      train, test = data.split
      train.size.should eq(4)
      test.size.should eq(1)
    end
  end
end

describe ML::Activation do
  describe ".sigmoid" do
    it "returns 0.5 for input 0" do
      ML::Activation.sigmoid(0.0).should be_close(0.5, 0.001)
    end

    it "returns value close to 1 for large positive input" do
      ML::Activation.sigmoid(10.0).should be_close(1.0, 0.001)
    end

    it "returns value close to 0 for large negative input" do
      ML::Activation.sigmoid(-10.0).should be_close(0.0, 0.001)
    end
  end

  describe ".sigmoid_derivative" do
    it "returns correct derivative at 0.5" do
      # At sigmoid(0) = 0.5, derivative = 0.5 * 0.5 = 0.25
      ML::Activation.sigmoid_derivative(0.5).should be_close(0.25, 0.001)
    end
  end

  describe ".tanh" do
    it "returns 0 for input 0" do
      ML::Activation.tanh(0.0).should be_close(0.0, 0.001)
    end

    it "returns value close to 1 for large positive input" do
      ML::Activation.tanh(10.0).should be_close(1.0, 0.001)
    end

    it "returns value close to -1 for large negative input" do
      ML::Activation.tanh(-10.0).should be_close(-1.0, 0.001)
    end
  end

  describe ".tanh_derivative" do
    it "returns correct derivative at 0" do
      # At tanh(0) = 0, derivative = 1 - 0^2 = 1
      ML::Activation.tanh_derivative(0.0).should be_close(1.0, 0.001)
    end
  end

  describe ".relu" do
    it "returns 0 for negative input" do
      ML::Activation.relu(-5.0).should eq(0.0)
    end

    it "returns input for positive input" do
      ML::Activation.relu(5.0).should eq(5.0)
    end

    it "returns 0 for zero input" do
      ML::Activation.relu(0.0).should eq(0.0)
    end
  end

  describe ".relu_derivative" do
    it "returns 0 for negative input" do
      ML::Activation.relu_derivative(-5.0).should eq(0.0)
    end

    it "returns 1 for positive input" do
      ML::Activation.relu_derivative(5.0).should eq(1.0)
    end
  end

  describe ".softmax" do
    it "returns probabilities that sum to 1" do
      input = [1.0, 2.0, 3.0]
      output = ML::Activation.softmax(input)
      output.sum.should be_close(1.0, 0.001)
    end

    it "preserves ordering" do
      input = [1.0, 2.0, 3.0]
      output = ML::Activation.softmax(input)
      output[2].should be > output[1]
      output[1].should be > output[0]
    end

    it "handles large values without overflow" do
      input = [1000.0, 1001.0, 1002.0]
      output = ML::Activation.softmax(input)
      output.sum.should be_close(1.0, 0.001)
    end
  end
end

describe ML::Loss do
  describe ".mean_squared_error" do
    it "returns 0 for perfect prediction" do
      predicted = [1.0, 2.0, 3.0]
      actual = [1.0, 2.0, 3.0]
      ML::Loss.mean_squared_error(predicted, actual).should eq(0.0)
    end

    it "returns positive value for imperfect prediction" do
      predicted = [1.0, 2.0, 3.0]
      actual = [2.0, 3.0, 4.0]
      # Each diff is 1, so MSE = (1 + 1 + 1) / 3 = 1
      ML::Loss.mean_squared_error(predicted, actual).should be_close(1.0, 0.001)
    end

    it "raises for mismatched sizes" do
      predicted = [1.0, 2.0]
      actual = [1.0, 2.0, 3.0]
      expect_raises(ML::MLException) do
        ML::Loss.mean_squared_error(predicted, actual)
      end
    end
  end

  describe ".cross_entropy" do
    it "returns low value for confident correct prediction" do
      predicted = [0.9, 0.1]
      actual = [1.0, 0.0]
      loss = ML::Loss.cross_entropy(predicted, actual)
      loss.should be < 0.5
    end

    it "returns high value for confident wrong prediction" do
      predicted = [0.1, 0.9]
      actual = [1.0, 0.0]
      loss = ML::Loss.cross_entropy(predicted, actual)
      loss.should be > 2.0
    end

    it "raises for mismatched sizes" do
      predicted = [0.5]
      actual = [1.0, 0.0]
      expect_raises(ML::MLException) do
        ML::Loss.cross_entropy(predicted, actual)
      end
    end
  end
end

describe ML::Metrics do
  describe ".accuracy" do
    it "returns 1.0 for all correct predictions" do
      predictions = [[0.1, 0.9], [0.9, 0.1], [0.1, 0.9]]
      actuals = [[0.0, 1.0], [1.0, 0.0], [0.0, 1.0]]
      ML::Metrics.accuracy(predictions, actuals).should eq(1.0)
    end

    it "returns 0.0 for all wrong predictions" do
      predictions = [[0.9, 0.1], [0.1, 0.9]]
      actuals = [[0.0, 1.0], [1.0, 0.0]]
      ML::Metrics.accuracy(predictions, actuals).should eq(0.0)
    end

    it "returns correct ratio for mixed predictions" do
      predictions = [[0.1, 0.9], [0.9, 0.1]]  # First correct, second wrong
      actuals = [[0.0, 1.0], [0.0, 1.0]]
      ML::Metrics.accuracy(predictions, actuals).should eq(0.5)
    end
  end

  describe ".precision_recall" do
    it "returns perfect precision and recall for perfect predictions" do
      predictions = [[0.9], [0.1]]
      actuals = [[1.0], [0.0]]
      precision, recall = ML::Metrics.precision_recall(predictions, actuals)
      precision.should be_close(1.0, 0.01)
      recall.should be_close(1.0, 0.01)
    end

    it "handles no positive predictions" do
      predictions = [[0.1], [0.1]]
      actuals = [[1.0], [0.0]]
      precision, recall = ML::Metrics.precision_recall(predictions, actuals)
      precision.should be_close(0.0, 0.01)
    end
  end

  describe ".f1_score" do
    it "returns high score for good predictions" do
      predictions = [[0.9], [0.1], [0.8]]
      actuals = [[1.0], [0.0], [1.0]]
      f1 = ML::Metrics.f1_score(predictions, actuals)
      f1.should be > 0.5
    end

    it "returns low score for poor predictions" do
      predictions = [[0.1], [0.9], [0.2]]
      actuals = [[1.0], [0.0], [1.0]]
      f1 = ML::Metrics.f1_score(predictions, actuals)
      f1.should be < 0.5
    end
  end
end

describe ML::AtomSpaceIntegration do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  describe ".atoms_to_features" do
    it "converts atoms to feature vector" do
      atomspace = AtomSpace::AtomSpace.new
      atom = atomspace.add_concept_node("test")
      features = ML::AtomSpaceIntegration.atoms_to_features([atom])
      features.size.should be > 0
    end

    it "returns empty for no atoms" do
      features = ML::AtomSpaceIntegration.atoms_to_features([] of AtomSpace::Atom)
      features.empty?.should be_true
    end

    it "includes truth value features" do
      atomspace = AtomSpace::AtomSpace.new
      tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
      atom = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "test", tv)
      features = ML::AtomSpaceIntegration.atoms_to_features([atom])
      features.size.should be >= 4  # type, strength, confidence, name_hash, connectivity
    end
  end

  describe ".prediction_to_atom" do
    it "creates atom from prediction" do
      atomspace = AtomSpace::AtomSpace.new
      prediction = [1.0, 0.9, 0.8, 0.5, 0.2]
      atom = ML::AtomSpaceIntegration.prediction_to_atom(prediction, atomspace)
      atom.should_not be_nil
    end

    it "returns nil for too small prediction" do
      atomspace = AtomSpace::AtomSpace.new
      prediction = [1.0, 0.9]
      atom = ML::AtomSpaceIntegration.prediction_to_atom(prediction, atomspace)
      atom.should be_nil
    end
  end

  describe ".build_training_data" do
    it "builds training data from atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      atomspace.add_concept_node("test1")
      atomspace.add_concept_node("test2")
      atomspace.add_predicate_node("pred1")

      data = ML::AtomSpaceIntegration.build_training_data(
        atomspace,
        AtomSpace::AtomType::CONCEPT_NODE,
        AtomSpace::AtomType::PREDICATE_NODE
      )
      data.should be_a(ML::TrainingData)
    end
  end
end
