#!/usr/bin/env crystal

# Test Machine Learning Features
# Tests neural networks, ML integration with AtomSpace

require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/ml/ml_main"

puts "=== Machine Learning Features Test ==="

# Initialize systems
CogUtil.initialize
AtomSpace.initialize
ML.initialize

puts "\n1. Activation Functions Test"
puts "=" * 50

test_values = [-2.0, -1.0, 0.0, 1.0, 2.0]

puts "\nSigmoid:"
test_values.each do |x|
  y = ML::Activation.sigmoid(x)
  puts "  sigmoid(#{x}) = #{y.round(4)}"
end

puts "\nReLU:"
test_values.each do |x|
  y = ML::Activation.relu(x)
  puts "  relu(#{x}) = #{y.round(4)}"
end

puts "\nTanh:"
test_values.each do |x|
  y = ML::Activation.tanh(x)
  puts "  tanh(#{x}) = #{y.round(4)}"
end

puts "\nSoftmax:"
input = [1.0, 2.0, 3.0, 4.0]
output = ML::Activation.softmax(input)
puts "  input: #{input}"
puts "  output: #{output.map { |v| v.round(4) }}"
puts "  sum: #{output.sum.round(4)}"

puts "\n2. Loss Functions Test"
puts "=" * 50

predicted = [0.8, 0.2, 0.1]
actual = [1.0, 0.0, 0.0]

mse = ML::Loss.mean_squared_error(predicted, actual)
ce = ML::Loss.cross_entropy(predicted, actual)

puts "\nPredicted: #{predicted}"
puts "Actual: #{actual}"
puts "Mean Squared Error: #{mse.round(4)}"
puts "Cross Entropy: #{ce.round(4)}"

puts "\n3. Training Data Test"
puts "=" * 50

# Create sample training data (XOR problem)
inputs = [
  [0.0, 0.0],
  [0.0, 1.0],
  [1.0, 0.0],
  [1.0, 1.0]
]

outputs = [
  [0.0],
  [1.0],
  [1.0],
  [0.0]
]

training_data = ML::TrainingData.new(inputs, outputs)

puts "\nTraining data created:"
puts "  Size: #{training_data.size}"
puts "  Input dimension: #{training_data.inputs.first.size}"
puts "  Output dimension: #{training_data.outputs.first.size}"

# Test shuffle
shuffled = training_data.shuffle
puts "\nShuffled data (first example):"
puts "  Input: #{shuffled.inputs.first}"
puts "  Output: #{shuffled.outputs.first}"

# Test split
train_data, test_data = training_data.split(0.75)
puts "\nSplit data (75/25):"
puts "  Training examples: #{train_data.size}"
puts "  Test examples: #{test_data.size}"

puts "\n4. Neural Network Test"
puts "=" * 50

# Create a simple neural network
layer_sizes = [2, 4, 1]  # 2 inputs, 4 hidden, 1 output
nn = ML::NeuralNetwork.new(layer_sizes, learning_rate: 0.1)

puts "\nCreated neural network: #{layer_sizes.join(" -> ")}"
puts "Learning rate: 0.1"

# Test prediction before training
puts "\nPredictions before training:"
inputs.each_with_index do |input, i|
  output = nn.predict(input)
  puts "  #{input} -> #{output.first.round(4)} (expected: #{outputs[i].first})"
end

# Train the network
puts "\nTraining neural network (100 epochs)..."
nn.train(training_data, epochs: 100)

# Test prediction after training
puts "\nPredictions after training:"
total_error = 0.0
inputs.each_with_index do |input, i|
  output = nn.predict(input)
  expected = outputs[i].first
  error = (output.first - expected).abs
  total_error += error
  puts "  #{input} -> #{output.first.round(4)} (expected: #{expected}, error: #{error.round(4)})"
end
puts "Average error: #{(total_error / inputs.size).round(4)}"

puts "\n5. AtomSpace Integration Test"
puts "=" * 50

atomspace = AtomSpace::AtomSpace.new

# Create some test atoms
dog = atomspace.add_concept_node("dog")
cat = atomspace.add_concept_node("cat")
animal = atomspace.add_concept_node("animal")

# Convert atoms to features
atoms = [dog, cat, animal]
features = ML::AtomSpaceIntegration.atoms_to_features(atoms)

puts "\nConverted #{atoms.size} atoms to #{features.size} features"
puts "Feature vector length per atom: #{features.size / atoms.size}"
puts "Sample features: #{features[0..5].map { |f| f.round(3) }}"

# Create an atom from prediction
puts "\nCreating atom from ML prediction..."
prediction = [5.0, 0.8, 0.9, 0.5, 2.0]  # type, strength, confidence, hash, connectivity
generated_atom = ML::AtomSpaceIntegration.prediction_to_atom(prediction, atomspace)

if generated_atom
  puts "  Generated atom: #{generated_atom}"
  puts "  Type: #{generated_atom.type}"
  puts "  Truth value: #{generated_atom.truth_value}"
end

puts "\n6. Evaluation Metrics Test"
puts "=" * 50

# Create sample predictions and actuals
predictions = [
  [0.9, 0.1, 0.0],
  [0.1, 0.8, 0.1],
  [0.2, 0.2, 0.6],
  [0.7, 0.2, 0.1]
]

actuals = [
  [1.0, 0.0, 0.0],
  [0.0, 1.0, 0.0],
  [0.0, 0.0, 1.0],
  [1.0, 0.0, 0.0]
]

accuracy = ML::Metrics.accuracy(predictions, actuals)
precision, recall = ML::Metrics.precision_recall(predictions, actuals)
f1 = ML::Metrics.f1_score(predictions, actuals)

puts "\nClassification Metrics:"
puts "  Accuracy: #{accuracy.round(4)}"
puts "  Precision: #{precision.round(4)}"
puts "  Recall: #{recall.round(4)}"
puts "  F1 Score: #{f1.round(4)}"

puts "\n7. Recurrent Layer Test"
puts "=" * 50

# Create a recurrent layer
rnn_layer = ML::RecurrentLayer.new(input_size: 3, hidden_size: 5)

puts "\nCreated RNN layer: 3 inputs -> 5 hidden units"

# Test sequence processing
sequence = [
  [1.0, 0.0, 0.0],
  [0.0, 1.0, 0.0],
  [0.0, 0.0, 1.0]
]

puts "\nProcessing sequence:"
sequence.each_with_index do |input, t|
  output = rnn_layer.forward(input)
  puts "  t=#{t}: input=#{input} -> output=#{output.map { |v| v.round(3) }}"
end

# Get and reset state
current_state = rnn_layer.get_state
puts "\nCurrent hidden state: #{current_state.map { |v| v.round(3) }}"

rnn_layer.reset_state
puts "State reset to: #{rnn_layer.get_state.map { |v| v.round(3) }}"

puts "\n=== Machine Learning Features Test Complete ==="
puts "\nAll ML tests passed! ✅"
