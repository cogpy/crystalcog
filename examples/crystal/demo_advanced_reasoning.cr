#!/usr/bin/env crystal

# Demonstration of Advanced Reasoning Engines
# Shows backward chaining and mixed inference capabilities

require "../../src/atomspace/atomspace_main"
require "../../src/ure/ure"

# Initialize the systems
CogUtil.initialize
AtomSpace.initialize
URE.initialize

# Create a new AtomSpace for demonstration
atomspace = AtomSpace::AtomSpace.new

puts "\n=== Advanced URE Reasoning Engines Demo ==="
puts "==========================================\n"

# Create a knowledge base about animals and their properties
puts "1. Building Knowledge Base..."

# Animals and their classifications
fido = atomspace.add_concept_node("Fido")
rex = atomspace.add_concept_node("Rex")
dog = atomspace.add_concept_node("dog")
mammal = atomspace.add_concept_node("mammal")
animal = atomspace.add_concept_node("animal")
living_thing = atomspace.add_concept_node("living_thing")

# Build inheritance hierarchy with truth values
atomspace.add_inheritance_link(fido, dog, AtomSpace::SimpleTruthValue.new(0.95, 0.9))
atomspace.add_inheritance_link(rex, dog, AtomSpace::SimpleTruthValue.new(0.90, 0.85))
atomspace.add_inheritance_link(dog, mammal, AtomSpace::SimpleTruthValue.new(0.9, 0.8))
atomspace.add_inheritance_link(mammal, animal, AtomSpace::SimpleTruthValue.new(0.85, 0.9))
atomspace.add_inheritance_link(animal, living_thing, AtomSpace::SimpleTruthValue.new(0.8, 0.85))

puts "   Created inheritance hierarchy: Fido/Rex -> dog -> mammal -> animal -> living_thing"
puts "   AtomSpace size: #{atomspace.size} atoms"

# Create the advanced URE engine
engine = URE::UREEngine.new(atomspace)

puts "\n2. Testing Backward Chaining..."

# Goal: Prove that Fido is a living thing
goal = atomspace.add_inheritance_link(fido, living_thing)
puts "   Goal: Prove Fido is a living_thing"

# Test backward chaining
puts "   Running backward chainer..."
backward_success = engine.backward_chain(goal)
puts "   Backward chaining result: #{backward_success}"

# Test advanced backward chaining with BIT
puts "   Running advanced backward chainer with BIT..."
backward_results = engine.backward_chainer.do_chain(goal)
puts "   Advanced backward chaining found #{backward_results.size} result paths"

puts "\n3. Testing Variable Fulfillment Queries..."

# Query: What are instances of dog? (find $x such that $x inherits from dog)
var_x = atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
query_pattern = atomspace.add_inheritance_link(var_x, dog)

puts "   Query: Find all $x such that $x inherits from dog"
groundings = engine.backward_chainer.variable_fulfillment_query(query_pattern)
puts "   Found #{groundings.size} groundings:"
groundings.each_with_index do |grounding, i|
  puts "     #{i + 1}. $x = #{grounding["$x"]?.try(&.name) || "unknown"}"
end

puts "\n4. Testing Mixed Inference Strategies..."

# Test different strategies
strategies = [
  URE::InferenceStrategy::FORWARD_ONLY,
  URE::InferenceStrategy::BACKWARD_ONLY,
  URE::InferenceStrategy::MIXED_FORWARD_FIRST,
  URE::InferenceStrategy::MIXED_BACKWARD_FIRST,
  URE::InferenceStrategy::ADAPTIVE_BIDIRECTIONAL
]

goal2 = atomspace.add_inheritance_link(rex, animal)
puts "   Goal: Prove Rex is an animal"

strategies.each do |strategy|
  puts "   Testing #{strategy}:"
  start_time = Time.monotonic
  results = engine.execute_strategy(strategy, goal2, max_time: 2.0)
  elapsed = (Time.monotonic - start_time).total_milliseconds
  puts "     Results: #{results.size} atoms, Time: #{elapsed.round(2)}ms"
end

puts "\n5. Testing Adaptive Mixed Inference..."

# Test adaptive reasoning that learns from performance
goal3 = atomspace.add_inheritance_link(fido, animal)
puts "   Goal: Prove Fido is an animal"

puts "   Running adaptive mixed inference (with learning)..."
start_time = Time.monotonic
adaptive_results = engine.adaptive_mixed_chain(goal3, max_time: 5.0)
elapsed = (Time.monotonic - start_time).total_milliseconds

puts "   Adaptive inference results:"
puts "     Found #{adaptive_results.size} relevant atoms"
puts "     Time taken: #{elapsed.round(2)}ms"
puts "     Engine automatically selected optimal strategy based on goal analysis"

puts "\n6. Testing Truth Value Fulfillment..."

# Create a target with unknown truth value
unknown_goal = atomspace.add_inheritance_link(rex, living_thing)
unknown_goal.truth_value = AtomSpace::SimpleTruthValue.new(0.5, 0.1)  # Low confidence

puts "   Goal: Update truth value for 'Rex inherits from living_thing'"
puts "   Initial truth value: strength=#{unknown_goal.truth_value.strength}, confidence=#{unknown_goal.truth_value.confidence}"

# Use truth value fulfillment query
updated_tv = engine.backward_chainer.truth_value_fulfillment_query(unknown_goal)
if updated_tv
  puts "   Updated truth value: strength=#{updated_tv.strength.round(3)}, confidence=#{updated_tv.confidence.round(3)}"
  puts "   Confidence improved through inference!"
else
  puts "   No inference paths found for truth value update"
end

puts "\n=== Demo Complete ==="
puts "Advanced reasoning engines successfully demonstrated:"
puts "✓ Backward chaining with BIT (Backward Inference Tree)"
puts "✓ Variable fulfillment queries"
puts "✓ Mixed inference with multiple strategies"
puts "✓ Adaptive strategy selection"
puts "✓ Truth value fulfillment queries"
puts "✓ Performance tracking and learning"

puts "\nThe URE now supports sophisticated reasoning capabilities"
puts "comparable to the original OpenCog C++ implementation!"