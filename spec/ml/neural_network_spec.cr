require "spec"
require "../../src/ml/neural_network"

describe ML::NeuralNetwork do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    ML.initialize
  end

  describe "initialization" do
    it "creates a network with given layer sizes" do
      nn = ML::NeuralNetwork.new([2, 3, 1])
      nn.layers.size.should eq(2)
    end

    it "uses default learning rate" do
      nn = ML::NeuralNetwork.new([4, 4])
      nn.learning_rate.should eq(0.01)
    end

    it "uses custom learning rate" do
      nn = ML::NeuralNetwork.new([4, 4], 0.001)
      nn.learning_rate.should eq(0.001)
    end

    it "creates a single-layer network" do
      nn = ML::NeuralNetwork.new([5, 1])
      nn.layers.size.should eq(1)
    end

    it "creates a deep network" do
      nn = ML::NeuralNetwork.new([3, 5, 5, 2])
      nn.layers.size.should eq(3)
    end
  end

  describe "predict" do
    it "produces output of correct size" do
      nn = ML::NeuralNetwork.new([3, 2])
      input = [0.5, 0.3, 0.8]
      output = nn.predict(input)
      output.size.should eq(2)
    end

    it "produces values in sigmoid output range (0, 1)" do
      nn = ML::NeuralNetwork.new([2, 3, 1])
      input = [1.0, -1.0]
      output = nn.predict(input)
      output.each { |v| v.should be > 0.0 }
      output.each { |v| v.should be < 1.0 }
    end

    it "returns deterministic output for same input" do
      nn = ML::NeuralNetwork.new([2, 2])
      input = [0.5, 0.7]
      out1 = nn.predict(input)
      out2 = nn.predict(input)
      out1.should eq(out2)
    end
  end

  describe "train" do
    it "trains without errors" do
      nn = ML::NeuralNetwork.new([2, 2, 1], 0.1)

      inputs = [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
      outputs = [[0.0], [1.0], [1.0], [0.0]]
      data = ML::TrainingData.new(inputs, outputs)

      nn.train(data, epochs: 5)
    end

    it "reduces loss over epochs for simple learnable function" do
      nn = ML::NeuralNetwork.new([1, 4, 1], 0.5)

      # Learn identity function: output ≈ input
      inputs = [[0.0], [0.25], [0.5], [0.75], [1.0]]
      outputs = [[0.0], [0.25], [0.5], [0.75], [1.0]]
      data = ML::TrainingData.new(inputs, outputs)

      # Measure initial loss
      initial_predictions = inputs.map { |inp| nn.predict(inp) }
      initial_loss = ML::Loss.mean_squared_error(
        initial_predictions.flatten,
        outputs.flatten
      )

      nn.train(data, epochs: 200)

      # Measure final loss
      final_predictions = inputs.map { |inp| nn.predict(inp) }
      final_loss = ML::Loss.mean_squared_error(
        final_predictions.flatten,
        outputs.flatten
      )

      # Training should have strictly improved (reduced) the loss
      final_loss.should be < initial_loss
    end
  end

  describe "train_online" do
    it "trains on a single example without errors" do
      nn = ML::NeuralNetwork.new([2, 1])
      nn.train_online([0.5, 0.5], [1.0])
    end
  end

  describe "save_weights and load_weights" do
    it "saves and restores weights preserving prediction" do
      nn = ML::NeuralNetwork.new([2, 3, 1])
      input = [0.4, 0.6]

      output_before = nn.predict(input)
      saved = nn.save_weights

      # Create a new network and load weights
      nn2 = ML::NeuralNetwork.new([2, 3, 1])
      nn2.load_weights(saved)

      output_after = nn2.predict(input)
      output_before.zip(output_after).each do |b, a|
        b.should be_close(a, 0.0001)
      end
    end

    it "raises when loading weights of wrong size" do
      nn = ML::NeuralNetwork.new([2, 3, 1])
      nn2 = ML::NeuralNetwork.new([3, 4, 2])
      saved = nn2.save_weights

      expect_raises(ML::MLException) do
        nn.load_weights(saved)
      end
    end
  end
end

describe ML::Layer do
  describe "initialization" do
    it "creates layer with correct weight dimensions" do
      layer = ML::Layer.new(3, 4)
      layer.weights.size.should eq(3)
      layer.weights[0].size.should eq(4)
    end

    it "initializes biases to zero" do
      layer = ML::Layer.new(2, 3)
      layer.biases.should eq([0.0, 0.0, 0.0])
    end
  end

  describe "forward" do
    it "produces output of correct size" do
      layer = ML::Layer.new(4, 2)
      output = layer.forward([0.1, 0.2, 0.3, 0.4])
      output.size.should eq(2)
    end

    it "applies sigmoid activation" do
      layer = ML::Layer.new(1, 1)
      output = layer.forward([0.0])
      # Output must be in (0, 1) due to sigmoid
      output[0].should be > 0.0
      output[0].should be < 1.0
    end
  end

  describe "update" do
    it "modifies weights when called" do
      layer = ML::Layer.new(2, 2)
      original_weights = layer.weights.map(&.dup)

      input = [1.0, 1.0]
      delta = [0.1, 0.1]
      layer.update(input, delta, 0.1)

      changed = original_weights.zip(layer.weights).any? do |orig_row, new_row|
        orig_row.zip(new_row).any? { |o, n| o != n }
      end
      changed.should be_true
    end
  end

  describe "get_weights and set_weights" do
    it "round-trips weight data" do
      layer = ML::Layer.new(3, 2)
      saved = layer.get_weights

      layer2 = ML::Layer.new(3, 2)
      layer2.set_weights(saved)

      layer.weights.should eq(layer2.weights)
    end
  end
end

describe ML::RecurrentLayer do
  describe "initialization" do
    it "creates layer with correct dimensions" do
      rnn = ML::RecurrentLayer.new(4, 3)
      rnn.weights_input.size.should eq(4)
      rnn.weights_recurrent.size.should eq(3)
      rnn.biases.size.should eq(3)
    end
  end

  describe "forward" do
    it "produces hidden state of correct size" do
      rnn = ML::RecurrentLayer.new(2, 4)
      output = rnn.forward([0.5, 0.3])
      output.size.should eq(4)
    end

    it "applies tanh activation (output in (-1, 1))" do
      rnn = ML::RecurrentLayer.new(2, 3)
      output = rnn.forward([1.0, 1.0])
      output.each do |v|
        v.should be > -1.0
        v.should be < 1.0
      end
    end

    it "produces different outputs for consecutive calls (recurrence)" do
      rnn = ML::RecurrentLayer.new(2, 3)
      out1 = rnn.forward([1.0, 0.0])
      out2 = rnn.forward([1.0, 0.0])
      # Recurrent connection means second output differs from first
      out1.should_not eq(out2)
    end
  end

  describe "reset_state" do
    it "resets hidden state to zeros" do
      rnn = ML::RecurrentLayer.new(2, 3)
      rnn.forward([1.0, 1.0])
      rnn.reset_state
      rnn.get_state.should eq([0.0, 0.0, 0.0])
    end
  end

  describe "get_state and set_state" do
    it "round-trips the hidden state" do
      rnn = ML::RecurrentLayer.new(2, 3)
      rnn.forward([0.5, 0.5])
      saved_state = rnn.get_state

      rnn.reset_state
      rnn.set_state(saved_state)

      rnn.get_state.should eq(saved_state)
    end
  end
end
