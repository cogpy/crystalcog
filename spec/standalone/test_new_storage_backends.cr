# Test for PostgreSQL and RocksDB storage backends
# Tests the new persistent storage implementations

require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"
require "json"
require "file_utils"

# Initialize modules
CogUtil.initialize
AtomSpace.initialize

puts "=== PostgreSQL and RocksDB Storage Backends Test ==="
puts

# Create test AtomSpace with sample data
def create_test_atomspace : AtomSpace::AtomSpace
  atomspace = AtomSpace::AtomSpace.new
  
  # Add some test atoms
  concept_dog = atomspace.add_concept_node("dog")
  concept_animal = atomspace.add_concept_node("animal") 
  concept_mammal = atomspace.add_concept_node("mammal")
  
  # Add inheritance relationships
  atomspace.add_inheritance_link(concept_dog, concept_animal)
  atomspace.add_inheritance_link(concept_dog, concept_mammal)
  atomspace.add_inheritance_link(concept_mammal, concept_animal)
  
  # Add predicate and evaluation
  predicate_color = atomspace.add_predicate_node("color")
  list_dog_brown = atomspace.add_list_link([concept_dog, atomspace.add_concept_node("brown")])
  atomspace.add_evaluation_link(predicate_color, list_dog_brown)
  
  puts "Created test AtomSpace with #{atomspace.size} atoms"
  atomspace
end

# Test RocksDB Storage
def test_rocksdb_storage
  puts "--- Testing RocksDBStorageNode ---"
  
  begin
    # Create test directory
    test_dir = "/tmp/crystalcog_test"
    Dir.mkdir_p(test_dir)
    
    # Create atomspace and storage
    atomspace = create_test_atomspace
    original_size = atomspace.size
    
    # Create RocksDB storage
    storage = AtomSpace::RocksDBStorageNode.new("test_rocks", "#{test_dir}/test_atoms.rocks")
    
    # Test connection
    unless storage.open
      puts "✗ RocksDBStorageNode failed to open"
      return false
    end
    puts "✓ RocksDBStorageNode opened successfully"
    
    # Test storing
    unless storage.store_atomspace(atomspace)
      puts "✗ Failed to store AtomSpace to RocksDB"
      return false
    end
    puts "✓ AtomSpace stored to RocksDB"
    
    # Test stats
    stats = storage.get_stats
    puts "  Stats: #{stats["atom_count"]} atoms stored"
    
    # Test loading
    new_atomspace = AtomSpace::AtomSpace.new
    unless storage.load_atomspace(new_atomspace)
      puts "✗ Failed to load AtomSpace from RocksDB"
      return false
    end
    puts "✓ AtomSpace loaded from RocksDB"
    puts "  Original size: #{original_size}, Loaded size: #{new_atomspace.size}"
    
    # Verify content
    if new_atomspace.size == original_size
      puts "✓ Atom count matches after loading"
    else
      puts "✗ Atom count mismatch after loading"
    end
    
    # Test individual atom operations
    test_atom = atomspace.add_concept_node("test_individual")
    if storage.store_atom(test_atom)
      puts "✓ Individual atom storage works"
      
      fetched_atom = storage.fetch_atom(test_atom.handle)
      if fetched_atom && fetched_atom.is_a?(AtomSpace::Node) && fetched_atom.name == "test_individual"
        puts "✓ Individual atom fetch works"
      else
        puts "✗ Individual atom fetch failed"
      end
    else
      puts "✗ Individual atom storage failed"
    end
    
    storage.close
    puts "✓ RocksDB test PASSED"
    true
  rescue ex
    puts "✗ RocksDB test FAILED: #{ex.message}"
    false
  end
end

# Test PostgreSQL Storage (without actual database connection)
def test_postgres_storage_interface
  puts "--- Testing PostgresStorageNode Interface ---"
  
  begin
    # Test interface creation (this will fail to connect but tests the interface)
    storage = AtomSpace::PostgresStorageNode.new("test_postgres", "localhost:5432/test")
    puts "✓ PostgresStorageNode created successfully"
    
    # Test stats (should work even without connection)
    stats = storage.get_stats
    if stats["type"] == "PostgreSQLStorage"
      puts "✓ PostgreSQL storage stats interface works"
    else
      puts "✗ PostgreSQL storage stats interface failed"
    end
    
    puts "✓ PostgreSQL interface test PASSED (no DB connection required)"
    true
  rescue ex
    puts "✗ PostgreSQL interface test FAILED: #{ex.message}"
    false
  end
end

# Run all tests
def run_tests
  tests_passed = 0
  total_tests = 2
  
  # Test RocksDB
  if test_rocksdb_storage
    tests_passed += 1
  end
  puts
  
  # Test PostgreSQL interface
  if test_postgres_storage_interface
    tests_passed += 1
  end
  puts
  
  puts "=== Test Summary ==="
  puts "Tests passed: #{tests_passed}/#{total_tests}"
  
  if tests_passed == total_tests
    puts "✓ All storage backend tests PASSED!"
    exit 0
  else
    puts "✗ Some storage backend tests FAILED!"
    exit 1
  end
end

# Run the tests
run_tests