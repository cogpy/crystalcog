require "spec"
require "../../src/ml/ml_main"

describe "ML Main" do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    ML.initialize
  end

  describe "initialization" do
    it "initializes the ML subsystem without errors" do
      ML.initialize
    end

    it "has correct version" do
      ML::VERSION.should eq("0.1.0")
    end
  end

  describe "module accessibility" do
    it "exposes Activation module" do
      ML::Activation.sigmoid(0.0).should be_close(0.5, 0.001)
    end

    it "exposes Loss module" do
      loss = ML::Loss.mean_squared_error([1.0], [1.0])
      loss.should eq(0.0)
    end

    it "exposes Metrics module" do
      predictions = [[1.0, 0.0], [0.0, 1.0]]
      actuals = [[1.0, 0.0], [0.0, 1.0]]
      acc = ML::Metrics.accuracy(predictions, actuals)
      acc.should eq(1.0)
    end

    it "exposes TrainingData struct" do
      data = ML::TrainingData.new([[1.0, 2.0]], [[3.0]])
      data.size.should eq(1)
    end
  end
end
