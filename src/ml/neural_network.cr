# Neural Network Implementation for CrystalCog
#
# This module provides a basic feedforward neural network implementation
# for integration with the CogPrime cognitive architecture.

require "../cogutil/cogutil"
require "./ml_integration"

module ML
  # Simple feedforward neural network
  class NeuralNetwork
    include Predictor

    getter layers : Array(Layer)
    getter learning_rate : Float64

    def initialize(layer_sizes : Array(Int32), @learning_rate : Float64 = 0.01)
      @layers = [] of Layer

      # Create layers
      (0...layer_sizes.size - 1).each do |i|
        @layers << Layer.new(layer_sizes[i], layer_sizes[i + 1])
      end

      CogUtil::Logger.info("Neural network created with architecture: #{layer_sizes.join(" -> ")}")
    end

    # Forward propagation
    def predict(input : Array(Float64)) : Array(Float64)
      activation = input

      @layers.each do |layer|
        activation = layer.forward(activation)
      end

      activation
    end

    # Train the network
    def train(data : TrainingData, epochs : Int32 = 100)
      CogUtil::Logger.info("Training neural network for #{epochs} epochs...")

      epochs.times do |epoch|
        total_loss = 0.0

        data.inputs.zip(data.outputs).each do |input, target|
          # Forward pass
          output = predict(input)

          # Compute loss
          loss = Loss.mean_squared_error(output, target)
          total_loss += loss

          # Backward pass
          backpropagate(input, target)
        end

        avg_loss = total_loss / data.size

        if (epoch + 1) % 10 == 0
          CogUtil::Logger.debug("Epoch #{epoch + 1}/#{epochs}, Loss: #{avg_loss.round(6)}")
        end
      end

      CogUtil::Logger.info("Training complete")
    end

    # Train on single example (online learning)
    def train_online(input : Array(Float64), target : Array(Float64))
      # Forward pass
      predict(input)

      # Backward pass
      backpropagate(input, target)
    end

    # Backpropagation
    private def backpropagate(input : Array(Float64), target : Array(Float64))
      # Forward pass (save activations)
      activations = [input]
      current = input

      @layers.each do |layer|
        current = layer.forward(current)
        activations << current
      end

      # Backward pass
      delta = compute_output_delta(activations.last, target)

      (@layers.size - 1).downto(0) do |i|
        layer = @layers[i]
        input_activation = activations[i]

        # Update weights and biases
        layer.update(input_activation, delta, @learning_rate)

        # Propagate delta to previous layer
        if i > 0
          delta = layer.backward_delta(delta)
        end
      end
    end

    private def compute_output_delta(output : Array(Float64),
                                     target : Array(Float64)) : Array(Float64)
      output.zip(target).map do |o, t|
        # Derivative of MSE loss with sigmoid activation
        (o - t) * Activation.sigmoid_derivative(o)
      end
    end

    # Save network weights
    def save_weights : Array(Array(Array(Array(Float64))))
      @layers.map { |layer| layer.get_weights }
    end

    # Load network weights
    def load_weights(weights : Array(Array(Array(Array(Float64)))))
      if weights.size != @layers.size
        raise MLException.new("Weight array size mismatch")
      end

      weights.each_with_index do |layer_weights, i|
        @layers[i].set_weights(layer_weights)
      end
    end
  end

  # Single layer in neural network
  class Layer
    getter weights : Array(Array(Float64))
    getter biases : Array(Float64)
    @last_input : Array(Float64)?
    @last_output : Array(Float64)?

    def initialize(input_size : Int32, output_size : Int32)
      # Xavier initialization
      scale = Math.sqrt(2.0 / (input_size + output_size))

      @weights = Array.new(input_size) do
        Array.new(output_size) { (Random.rand * 2.0 - 1.0) * scale }
      end

      @biases = Array.new(output_size) { 0.0 }
    end

    # Forward pass
    def forward(input : Array(Float64)) : Array(Float64)
      @last_input = input

      output = Array.new(@biases.size) do |j|
        sum = @biases[j]

        input.each_with_index do |x, i|
          sum += x * @weights[i][j]
        end

        Activation.sigmoid(sum)
      end

      @last_output = output
      output
    end

    # Compute delta for previous layer
    def backward_delta(output_delta : Array(Float64)) : Array(Float64)
      input_delta = Array.new(@weights.size, 0.0)

      @weights.each_with_index do |weight_row, i|
        sum = 0.0
        weight_row.each_with_index do |w, j|
          sum += w * output_delta[j]
        end

        # Apply derivative of activation function
        if last_input = @last_input
          input_delta[i] = sum * Activation.sigmoid_derivative(last_input[i])
        end
      end

      input_delta
    end

    # Update weights and biases
    def update(input : Array(Float64), delta : Array(Float64), learning_rate : Float64)
      # Update weights
      @weights.each_with_index do |weight_row, i|
        weight_row.each_with_index do |w, j|
          gradient = input[i] * delta[j]
          @weights[i][j] -= learning_rate * gradient
        end
      end

      # Update biases
      @biases.each_with_index do |b, j|
        @biases[j] -= learning_rate * delta[j]
      end
    end

    # Get weights (for saving)
    def get_weights : Array(Array(Array(Float64)))
      [@weights.map(&.dup), [@biases.dup]]
    end

    # Set weights (for loading)
    def set_weights(weights : Array(Array(Array(Float64))))
      if weights.size >= 2
        new_weights = weights[0]
        new_biases = weights[1][0]
        if new_weights.size != @weights.size || new_biases.size != @biases.size
          raise MLException.new("Layer weight dimensions mismatch: expected #{@weights.size}x#{@biases.size}, got #{new_weights.size}x#{new_biases.size}")
        end
        new_weights.each_with_index do |row, i|
          if row.size != @weights[0].size
            raise MLException.new("Layer weight row size mismatch at row #{i}")
          end
        end
        @weights = new_weights.map(&.dup)
        @biases = new_biases.dup
      end
    end
  end

  # Recurrent neural network layer (simple RNN)
  class RecurrentLayer
    getter weights_input : Array(Array(Float64))
    getter weights_recurrent : Array(Array(Float64))
    getter biases : Array(Float64)
    @hidden_state : Array(Float64)

    def initialize(input_size : Int32, hidden_size : Int32)
      scale = Math.sqrt(1.0 / hidden_size)

      @weights_input = Array.new(input_size) do
        Array.new(hidden_size) { (Random.rand * 2.0 - 1.0) * scale }
      end

      @weights_recurrent = Array.new(hidden_size) do
        Array.new(hidden_size) { (Random.rand * 2.0 - 1.0) * scale }
      end

      @biases = Array.new(hidden_size) { 0.0 }
      @hidden_state = Array.new(hidden_size) { 0.0 }
    end

    # Forward pass with recurrence
    def forward(input : Array(Float64)) : Array(Float64)
      new_hidden = Array.new(@biases.size) do |j|
        sum = @biases[j]

        # Input contribution
        input.each_with_index do |x, i|
          sum += x * @weights_input[i][j]
        end

        # Recurrent contribution
        @hidden_state.each_with_index do |h, i|
          sum += h * @weights_recurrent[i][j]
        end

        Activation.tanh(sum)
      end

      @hidden_state = new_hidden
      new_hidden
    end

    # Reset hidden state
    def reset_state
      @hidden_state = Array.new(@biases.size) { 0.0 }
    end

    # Get current hidden state
    def get_state : Array(Float64)
      @hidden_state.dup
    end

    # Set hidden state
    def set_state(state : Array(Float64))
      @hidden_state = state.dup
    end
  end
end
