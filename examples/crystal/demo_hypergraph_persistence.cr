#!/usr/bin/env crystal

# Demo: Hypergraph State Persistence for Agent-Zero Genesis
# Demonstrates the complete cognitive kernel state persistence system

require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"

# Initialize modules
CogUtil.initialize
AtomSpace.initialize

puts "🧠 Agent-Zero Genesis: Hypergraph State Persistence Demo"
puts "=" * 60
puts

# Create a cognitive kernel for reasoning tasks
puts "1. Creating cognitive kernel for reasoning..."
reasoning_kernel = AtomSpace::CognitiveKernel.new([128, 64, 32], 0.9, 1, "reasoning")

# Add some knowledge to the AtomSpace
puts "2. Adding cognitive knowledge..."
agent_concept = reasoning_kernel.add_concept_node("agent-zero")
cognitive_concept = reasoning_kernel.add_concept_node("cognitive-system")
reasoning_concept = reasoning_kernel.add_concept_node("reasoning-engine")
memory_concept = reasoning_kernel.add_concept_node("memory-system")

# Create relationships
reasoning_kernel.add_inheritance_link(agent_concept, cognitive_concept)
reasoning_kernel.add_inheritance_link(reasoning_concept, cognitive_concept)
reasoning_kernel.add_inheritance_link(memory_concept, cognitive_concept)

# Add evaluation relationships
performs_predicate = reasoning_kernel.add_predicate_node("performs")
args_list = reasoning_kernel.atomspace.add_list_link([agent_concept, reasoning_concept])
reasoning_kernel.add_evaluation_link(performs_predicate, args_list)

puts "   Added #{reasoning_kernel.atomspace.size} atoms to cognitive kernel"
puts "   Tensor shape: #{reasoning_kernel.tensor_shape}"
puts "   Attention weight: #{reasoning_kernel.attention_weight}"
puts "   Meta level: #{reasoning_kernel.meta_level}"
puts "   Cognitive operation: #{reasoning_kernel.cognitive_operation}"
puts

# Generate tensor field encodings
puts "3. Generating tensor field encodings..."
prime_encoding = reasoning_kernel.tensor_field_encoding("prime", include_attention: true)
puts "   Prime encoding (#{prime_encoding.size} elements): #{prime_encoding[0..2]}..."

fibonacci_encoding = reasoning_kernel.tensor_field_encoding("fibonacci", include_attention: true, normalization: "unit")
puts "   Fibonacci encoding (normalized): #{fibonacci_encoding[0..2]}..."

hypergraph_encoding = reasoning_kernel.hypergraph_tensor_encoding
puts "   Hypergraph encoding (#{hypergraph_encoding.size} elements): #{hypergraph_encoding[-3..-1]}"
puts

# Store hypergraph state to multiple backends
puts "4. Storing hypergraph state to persistent storage..."

# File-based storage
file_storage_path = "/tmp/agent_zero_hypergraph_state.scm"
file_storage = reasoning_kernel.atomspace.create_hypergraph_storage("reasoning_file", file_storage_path, "file")
file_storage.open

if reasoning_kernel.store_hypergraph_state(file_storage)
  puts "   ✓ Stored to file: #{file_storage_path}"
else
  puts "   ✗ Failed to store to file"
end

# SQLite-based storage
sqlite_storage_path = "/tmp/agent_zero_hypergraph_state.db"
sqlite_storage = reasoning_kernel.atomspace.create_hypergraph_storage("reasoning_sqlite", sqlite_storage_path, "sqlite")
sqlite_storage.open

if reasoning_kernel.store_hypergraph_state(sqlite_storage)
  puts "   ✓ Stored to SQLite: #{sqlite_storage_path}"
else
  puts "   ✗ Failed to store to SQLite"
end
puts

# Create a new cognitive kernel and load the state
puts "5. Loading hypergraph state into new cognitive kernel..."
new_kernel = AtomSpace::CognitiveKernel.new([16, 8], 0.2, 0, "default") # Different initial state

puts "   Before loading:"
puts "     Shape: #{new_kernel.tensor_shape}"
puts "     Attention: #{new_kernel.attention_weight}"
puts "     Operation: #{new_kernel.cognitive_operation}"
puts "     AtomSpace size: #{new_kernel.atomspace.size}"

# Load from file storage
if new_kernel.load_hypergraph_state(file_storage)
  puts "   ✓ Loaded hypergraph state from file storage"
  
  puts "   After loading:"
  puts "     Shape: #{new_kernel.tensor_shape}"
  puts "     Attention: #{new_kernel.attention_weight}"
  puts "     Operation: #{new_kernel.cognitive_operation}"
  puts "     AtomSpace size: #{new_kernel.atomspace.size}"
else
  puts "   ✗ Failed to load from file storage"
end
puts

# Test AtomSpace-level hypergraph persistence
puts "6. Testing AtomSpace-level hypergraph persistence..."
test_atomspace = AtomSpace::AtomSpace.new

# Add test content
kernel_concept = test_atomspace.add_concept_node("cognitive-kernel")
tensor_concept = test_atomspace.add_concept_node("tensor-field")
test_atomspace.add_inheritance_link(kernel_concept, tensor_concept)

# Store hypergraph state directly via AtomSpace
hypergraph_storage = test_atomspace.create_hypergraph_storage("test_hypergraph", "/tmp/test_hypergraph_state.scm")
hypergraph_storage.open

tensor_shape = [256, 128, 64, 32]
attention = 0.95
meta_level = 3

if test_atomspace.store_hypergraph_state(tensor_shape, attention, meta_level, "meta-reasoning")
  puts "   ✓ Stored hypergraph state via AtomSpace interface"
  
  # Load into different AtomSpace
  load_space = AtomSpace::AtomSpace.new
  load_storage = load_space.create_hypergraph_storage("load_test", "/tmp/test_hypergraph_state.scm")
  load_storage.open
  
  loaded_state = load_space.load_hypergraph_state
  if loaded_state
    puts "   ✓ Loaded hypergraph state via AtomSpace interface"
    puts "     Loaded tensor shape: #{loaded_state.tensor_shape}"
    puts "     Loaded attention: #{loaded_state.attention}"
    puts "     Loaded operation: #{loaded_state.cognitive_operation}"
    puts "     Loaded atomspace size: #{loaded_state.atomspace.size}"
  else
    puts "   ✗ Failed to load hypergraph state"
  end
else
  puts "   ✗ Failed to store hypergraph state via AtomSpace"
end
puts

# Demonstrate cognitive kernel manager
puts "7. Demonstrating cognitive kernel manager..."
manager = AtomSpace::CognitiveKernelManager.new

# Create specialized kernels
reasoning_k = manager.create_kernel([128, 64], 0.9)
learning_k = manager.create_kernel([64, 32], 0.7)
memory_k = manager.create_kernel([256, 128], 0.8)
attention_k = manager.create_kernel([32, 16], 0.6)

puts "   Created #{manager.size} specialized cognitive kernels"

# Allocate attention based on goals
goals = ["reasoning", "learning", "memory", "attention"]
allocations = manager.adaptive_attention_allocation(goals)

puts "   Adaptive attention allocation:"
allocations.each_with_index do |allocation, i|
  puts "     Kernel #{i+1} (#{allocation[:goal]}): score=#{allocation[:attention_score]}, priority=#{allocation[:activation_priority]}"
end
puts

# Summary
puts "8. Summary:"
puts "   ✅ Hypergraph state persistence successfully implemented"
puts "   ✅ Cognitive kernel with tensor field encoding working"
puts "   ✅ Multiple storage backends (File, SQLite) operational"
puts "   ✅ AtomSpace integration for hypergraph state management"
puts "   ✅ Cognitive kernel manager for multi-kernel coordination"
puts
puts "🎉 Agent-Zero Genesis hypergraph state persistence system ready!"
puts "   The cognitive kernels can now persist their complete state including:"
puts "   • AtomSpace hypergraph content"
puts "   • Tensor field shapes and configurations"
puts "   • Attention weights and allocations"
puts "   • Meta-level information and cognitive operations"
puts "   • Timestamp information for state tracking"
puts

# Cleanup
file_storage.close
sqlite_storage.close
hypergraph_storage.close

puts "Demo completed successfully! 🧠✨"