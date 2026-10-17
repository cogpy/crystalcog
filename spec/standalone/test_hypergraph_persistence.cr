# Comprehensive test for hypergraph state persistence functionality
# Tests the cognitive kernel and hypergraph state storage implementations

require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"
require "json"
require "file_utils"

# Initialize modules
CogUtil.initialize
AtomSpace.initialize

puts "=== Hypergraph State Persistence Test Suite ==="
puts

# Create test cognitive kernel with sample hypergraph
def create_test_cognitive_kernel : AtomSpace::CognitiveKernel
  kernel = AtomSpace::CognitiveKernel.new([64, 32], 0.8, 1, "reasoning")
  
  # Add some cognitive knowledge to the atomspace
  concept_agent = kernel.add_concept_node("agent-zero")
  concept_cognitive = kernel.add_concept_node("cognitive-function")
  concept_reasoning = kernel.add_concept_node("reasoning")
  concept_memory = kernel.add_concept_node("memory")
  
  # Add inheritance relationships
  kernel.add_inheritance_link(concept_agent, concept_cognitive)
  kernel.add_inheritance_link(concept_reasoning, concept_cognitive)
  kernel.add_inheritance_link(concept_memory, concept_cognitive)
  
  # Add evaluation with reasoning predicate
  predicate_performs = kernel.add_predicate_node("performs")
  list_agent_reasoning = kernel.atomspace.add_list_link([concept_agent, concept_reasoning])
  kernel.add_evaluation_link(predicate_performs, list_agent_reasoning)
  
  puts "Created test cognitive kernel with #{kernel.atomspace.size} atoms"
  kernel
end

# Test basic cognitive kernel functionality
def test_cognitive_kernel_basic
  puts "--- Testing Basic Cognitive Kernel ---"
  
  begin
    kernel = create_test_cognitive_kernel
    
    # Test tensor field encoding
    encoding = kernel.tensor_field_encoding("prime", include_attention: true)
    if encoding.size > 0
      puts "✓ Tensor field encoding generated: size=#{encoding.size}"
      puts "  Sample values: #{encoding[0..2]}"
    else
      puts "✗ Failed to generate tensor field encoding"
      return false
    end
    
    # Test hypergraph tensor encoding
    hypergraph_encoding = kernel.hypergraph_tensor_encoding
    if hypergraph_encoding.size > encoding.size
      puts "✓ Hypergraph tensor encoding includes connectivity: size=#{hypergraph_encoding.size}"
    else
      puts "✗ Failed to generate hypergraph tensor encoding"
      return false
    end
    
    # Test cognitive operation-specific encoding
    reasoning_encoding = kernel.cognitive_tensor_field_encoding("reasoning")
    if reasoning_encoding.size > 0
      puts "✓ Cognitive operation encoding generated for reasoning"
      puts "  Operation set to: #{kernel.cognitive_operation}"
    else
      puts "✗ Failed to generate cognitive operation encoding"
      return false
    end
    
    # Test hypergraph state extraction
    state = kernel.hypergraph_state
    if state.tensor_shape == [64, 32] && state.attention == 0.8
      puts "✓ Hypergraph state extracted correctly"
      puts "  Shape: #{state.tensor_shape}, Attention: #{state.attention}"
      puts "  Meta-level: #{state.meta_level}, Operation: #{state.cognitive_operation}"
    else
      puts "✗ Failed to extract correct hypergraph state"
      return false
    end
    
    true
  rescue ex
    puts "✗ Basic cognitive kernel test failed: #{ex.message}"
    false
  end
end

# Test hypergraph state storage
def test_hypergraph_state_storage
  puts "--- Testing Hypergraph State Storage ---"
  
  begin
    # Create test directory
    test_dir = "/tmp/crystalcog_hypergraph_test"
    Dir.mkdir_p(test_dir)
    
    # Create cognitive kernel with test data
    kernel = create_test_cognitive_kernel
    original_state = kernel.hypergraph_state
    
    # Test file-based hypergraph storage
    file_storage_path = "#{test_dir}/hypergraph_state.scm"
    file_storage = AtomSpace::HypergraphStateStorageNode.new("test_hypergraph_file", file_storage_path, "file")
    
    if file_storage.open
      puts "✓ File-based hypergraph storage opened"
    else
      puts "✗ Failed to open file-based hypergraph storage"
      return false
    end
    
    # Store hypergraph state
    if file_storage.store_hypergraph_state(original_state)
      puts "✓ Hypergraph state stored to file"
      
      # Check that both atomspace file and metadata file exist
      metadata_path = file_storage_path.sub(".scm", "_metadata.json")
      if File.exists?(file_storage_path) && File.exists?(metadata_path)
        puts "✓ Both atomspace and metadata files created"
        puts "  Atomspace file size: #{File.size(file_storage_path)} bytes"
        puts "  Metadata file size: #{File.size(metadata_path)} bytes"
      else
        puts "✗ Missing required storage files"
        return false
      end
    else
      puts "✗ Failed to store hypergraph state"
      return false
    end
    
    # Test loading into new kernel
    new_kernel = AtomSpace::CognitiveKernel.new([32, 16], 0.5) # Different initial state
    
    if new_kernel.load_hypergraph_state(file_storage)
      puts "✓ Hypergraph state loaded successfully"
      
      # Verify loaded state matches original
      if new_kernel.tensor_shape == original_state.tensor_shape &&
         new_kernel.attention_weight == original_state.attention &&
         new_kernel.meta_level == original_state.meta_level &&
         new_kernel.cognitive_operation == original_state.cognitive_operation
        puts "✓ Loaded state matches original state"
        puts "  Shape: #{new_kernel.tensor_shape} -> #{original_state.tensor_shape}"
        puts "  Attention: #{new_kernel.attention_weight} -> #{original_state.attention}"
      else
        puts "✗ Loaded state does not match original"
        return false
      end
      
      # Verify atomspace content was loaded
      if new_kernel.atomspace.size == original_state.atomspace.size
        puts "✓ AtomSpace content loaded: #{new_kernel.atomspace.size} atoms"
      else
        puts "✗ AtomSpace content mismatch: expected #{original_state.atomspace.size}, got #{new_kernel.atomspace.size}"
        return false
      end
      
    else
      puts "✗ Failed to load hypergraph state"
      return false
    end
    
    file_storage.close
    true
  rescue ex
    puts "✗ Hypergraph state storage test failed: #{ex.message}"
    false
  end
end

# Test SQLite-based hypergraph storage
def test_hypergraph_sqlite_storage
  puts "--- Testing SQLite Hypergraph State Storage ---"
  
  begin
    # Create test directory
    test_dir = "/tmp/crystalcog_hypergraph_test"
    Dir.mkdir_p(test_dir)
    
    # Create cognitive kernel with test data
    kernel = create_test_cognitive_kernel
    original_state = kernel.hypergraph_state
    
    # Test SQLite-based hypergraph storage
    sqlite_storage_path = "#{test_dir}/hypergraph_state.db"
    sqlite_storage = AtomSpace::HypergraphStateStorageNode.new("test_hypergraph_sqlite", sqlite_storage_path, "sqlite")
    
    if sqlite_storage.open
      puts "✓ SQLite-based hypergraph storage opened"
    else
      puts "✗ Failed to open SQLite-based hypergraph storage"
      return false
    end
    
    # Store hypergraph state
    if sqlite_storage.store_hypergraph_state(original_state)
      puts "✓ Hypergraph state stored to SQLite"
      
      # Check storage stats
      stats = sqlite_storage.get_stats
      puts "  Storage stats: #{stats["backend_type"]}, connected: #{stats["backend_connected"]}"
      
    else
      puts "✗ Failed to store hypergraph state to SQLite"
      return false
    end
    
    # Test loading from SQLite
    new_kernel = AtomSpace::CognitiveKernel.new([16, 8], 0.3) # Different initial state
    
    if new_kernel.load_hypergraph_state(sqlite_storage)  
      puts "✓ Hypergraph state loaded from SQLite"
      
      # Verify loaded state
      if new_kernel.tensor_shape == original_state.tensor_shape &&
         new_kernel.attention_weight == original_state.attention
        puts "✓ SQLite loaded state matches original"
      else
        puts "✗ SQLite loaded state does not match original"
        return false
      end
      
    else
      puts "✗ Failed to load hypergraph state from SQLite"
      return false
    end
    
    sqlite_storage.close
    true
  rescue ex
    puts "✗ SQLite hypergraph storage test failed: #{ex.message}"
    false
  end
end

# Test AtomSpace hypergraph persistence integration
def test_atomspace_hypergraph_integration
  puts "--- Testing AtomSpace Hypergraph Integration ---"
  
  begin
    # Create test directory
    test_dir = "/tmp/crystalcog_hypergraph_test"
    Dir.mkdir_p(test_dir)
    
    # Create AtomSpace with hypergraph storage
    atomspace = AtomSpace::AtomSpace.new
    
    # Add test content
    concept_kernel = atomspace.add_concept_node("cognitive-kernel")
    concept_tensor = atomspace.add_concept_node("tensor-field")
    atomspace.add_inheritance_link(concept_kernel, concept_tensor)
    
    # Create and attach hypergraph storage
    storage_path = "#{test_dir}/atomspace_hypergraph.scm"
    hypergraph_storage = atomspace.create_hypergraph_storage("main_hypergraph", storage_path)
    
    if hypergraph_storage.open
      puts "✓ AtomSpace hypergraph storage attached and opened"
    else
      puts "✗ Failed to open AtomSpace hypergraph storage"
      return false
    end
    
    # Store hypergraph state using AtomSpace methods
    tensor_shape = [128, 64, 32]
    attention = 0.9
    meta_level = 2
    
    if atomspace.store_hypergraph_state(tensor_shape, attention, meta_level, "learning")
      puts "✓ Hypergraph state stored via AtomSpace interface"
    else
      puts "✗ Failed to store hypergraph state via AtomSpace"
      return false
    end
    
    # Load into new AtomSpace
    new_atomspace = AtomSpace::AtomSpace.new
    new_hypergraph_storage = new_atomspace.create_hypergraph_storage("load_hypergraph", storage_path)
    new_hypergraph_storage.open
    
    loaded_state = new_atomspace.load_hypergraph_state
    if loaded_state
      puts "✓ Hypergraph state loaded via AtomSpace interface"
      puts "  Loaded shape: #{loaded_state.tensor_shape}"
      puts "  Loaded attention: #{loaded_state.attention}"
      puts "  Loaded operation: #{loaded_state.cognitive_operation}"
      
      if loaded_state.tensor_shape == tensor_shape && loaded_state.attention == attention
        puts "✓ Loaded hypergraph state matches stored state"
      else
        puts "✗ Loaded hypergraph state does not match"
      end
    else
      puts "✗ Failed to load hypergraph state via AtomSpace"
      return false
    end
    
    true
  rescue ex
    puts "✗ AtomSpace hypergraph integration test failed: #{ex.message}"
    false
  end
end

# Test cognitive kernel manager
def test_cognitive_kernel_manager
  puts "--- Testing Cognitive Kernel Manager ---"
  
  begin
    manager = AtomSpace::CognitiveKernelManager.new
    
    # Create multiple kernels for different cognitive functions
    reasoning_kernel = manager.create_kernel([128, 64], 0.9)
    learning_kernel = manager.create_kernel([64, 32], 0.7)
    memory_kernel = manager.create_kernel([256, 128], 0.8)
    
    if manager.size == 3
      puts "✓ Cognitive kernel manager created 3 kernels"
    else
      puts "✗ Unexpected number of kernels: #{manager.size}"
      return false
    end
    
    # Test adaptive attention allocation
    goals = ["reasoning", "learning", "memory"]
    allocations = manager.adaptive_attention_allocation(goals)
    
    if allocations.size == 3
      puts "✓ Attention allocation computed for all kernels"
      
      allocations.each_with_index do |allocation, i|
        puts "  Kernel #{i+1}: #{allocation[:goal]} -> score=#{allocation[:attention_score]}, priority=#{allocation[:activation_priority]}"
      end
      
      # Verify reasoning has highest attention score
      reasoning_allocation = allocations.find { |a| a[:goal] == "reasoning" }
      if reasoning_allocation && reasoning_allocation[:attention_score] == 0.9
        puts "✓ Reasoning kernel has correct attention score"
      else
        puts "✗ Reasoning kernel attention score incorrect"
        return false
      end
    else
      puts "✗ Attention allocation failed"
      return false
    end
    
    true
  rescue ex
    puts "✗ Cognitive kernel manager test failed: #{ex.message}"
    false
  end
end

# Run complete test suite
def run_hypergraph_persistence_tests : Bool
  tests_passed = 0
  total_tests = 5
  
  tests = [
    {"Cognitive Kernel Basic", ->{ test_cognitive_kernel_basic }},
    {"Hypergraph State Storage", ->{ test_hypergraph_state_storage }},
    {"SQLite Hypergraph Storage", ->{ test_hypergraph_sqlite_storage }},
    {"AtomSpace Hypergraph Integration", ->{ test_atomspace_hypergraph_integration }},
    {"Cognitive Kernel Manager", ->{ test_cognitive_kernel_manager }}
  ]
  
  tests.each do |name, test_proc|
    puts
    if test_proc.call
      puts "✓ #{name} test PASSED"
      tests_passed += 1
    else
      puts "✗ #{name} test FAILED"
    end
  end
  
  puts
  puts "=== Hypergraph State Persistence Test Results ==="
  puts "Passed: #{tests_passed}/#{total_tests}"
  puts "Success rate: #{(tests_passed * 100 / total_tests).round(1)}%"
  
  if tests_passed == total_tests
    puts "🎉 All hypergraph state persistence tests passed!"
    true
  else
    puts "❌ Some hypergraph state persistence tests failed"
    false
  end
end

# Run the test suite
begin
  success = run_hypergraph_persistence_tests
  puts
  exit(success ? 0 : 1)
rescue ex
  puts "💥 Hypergraph persistence test suite crashed: #{ex.message}"
  puts ex.backtrace.join("\n")
  exit(1)
end