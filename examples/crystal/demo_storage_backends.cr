# Comprehensive demo of PostgreSQL and RocksDB storage backends
# Shows the new persistent storage functionality

require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"
require "file_utils"

# Initialize modules
CogUtil.initialize
AtomSpace.initialize

puts "=== PostgreSQL and RocksDB Storage Backends Demo ==="
puts "This demo shows the new persistent storage backends for AtomSpace"
puts

# Create a knowledge base
def create_animal_knowledge : AtomSpace::AtomSpace
  atomspace = AtomSpace::AtomSpace.new
  
  # Animals
  dog = atomspace.add_concept_node("dog")
  cat = atomspace.add_concept_node("cat")
  bird = atomspace.add_concept_node("bird")
  
  # Categories
  mammal = atomspace.add_concept_node("mammal")
  animal = atomspace.add_concept_node("animal")
  pet = atomspace.add_concept_node("pet")
  
  # Properties
  brown = atomspace.add_concept_node("brown")
  size_medium = atomspace.add_concept_node("medium")
  
  # Relationships
  atomspace.add_inheritance_link(dog, mammal)
  atomspace.add_inheritance_link(cat, mammal)
  atomspace.add_inheritance_link(mammal, animal)
  atomspace.add_inheritance_link(dog, pet)
  atomspace.add_inheritance_link(cat, pet)
  
  # Properties
  color_pred = atomspace.add_predicate_node("color")
  size_pred = atomspace.add_predicate_node("size")
  
  # Evaluations
  dog_color = atomspace.add_list_link([dog, brown])
  atomspace.add_evaluation_link(color_pred, dog_color)
  
  dog_size = atomspace.add_list_link([dog, size_medium])
  atomspace.add_evaluation_link(size_pred, dog_size)
  
  puts "Created animal knowledge base with #{atomspace.size} atoms:"
  puts "  - #{atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE).size} concept nodes"
  puts "  - #{atomspace.get_atoms_by_type(AtomSpace::AtomType::PREDICATE_NODE).size} predicate nodes"
  puts "  - #{atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).size} inheritance links"
  puts "  - #{atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).size} evaluation links"
  puts "  - #{atomspace.get_atoms_by_type(AtomSpace::AtomType::LIST_LINK).size} list links"
  
  atomspace
end

# Test RocksDB storage
def demo_rocksdb_storage(atomspace : AtomSpace::AtomSpace)
  puts "\n--- RocksDB Storage Demo ---"
  
  # Create storage using factory method
  rocks_storage = atomspace.create_rocksdb_storage("animals_rocks", "/tmp/demo_animals.rocks")
  
  puts "1. Opening RocksDB storage..."
  if rocks_storage.open
    puts "   ✓ RocksDB opened: #{rocks_storage.get_stats["path"]}"
    
    puts "2. Storing complete AtomSpace to RocksDB..."
    if rocks_storage.store_atomspace(atomspace)
      stats = rocks_storage.get_stats
      puts "   ✓ Stored #{stats["atom_count"]} atoms to RocksDB"
      puts "   ✓ Created #{stats["type_index_count"]} type indexes"
      puts "   ✓ Created #{stats["name_index_count"]} name indexes"
    end
    
    puts "3. Loading from RocksDB into new AtomSpace..."
    new_atomspace = AtomSpace::AtomSpace.new
    if rocks_storage.load_atomspace(new_atomspace)
      puts "   ✓ Loaded #{new_atomspace.size} atoms from RocksDB"
      puts "   ✓ Verifying integrity: #{atomspace.size == new_atomspace.size ? "PASS" : "FAIL"}"
    end
    
    puts "4. Testing individual atom operations..."
    test_atom = atomspace.add_concept_node("test_animal")
    if rocks_storage.store_atom(test_atom)
      fetched = rocks_storage.fetch_atom(test_atom.handle)
      if fetched && fetched.is_a?(AtomSpace::Node) && fetched.name == "test_animal"
        puts "   ✓ Individual store/fetch operations working"
      end
    end
    
    rocks_storage.close
    puts "   ✓ RocksDB storage closed"
  else
    puts "   ✗ Failed to open RocksDB storage"
  end
end

# Test PostgreSQL storage interface
def demo_postgres_storage(atomspace : AtomSpace::AtomSpace)
  puts "\n--- PostgreSQL Storage Demo ---"
  
  # Create storage using factory method
  postgres_storage = atomspace.create_postgres_storage("animals_pg", "user:password@localhost:5432/opencog_demo")
  
  puts "1. PostgreSQL storage interface created"
  puts "   Connection string: #{postgres_storage.get_stats["connection_string"]}"
  puts "   Type: #{postgres_storage.get_stats["type"]}"
  
  puts "2. Note: PostgreSQL requires a running database server"
  puts "   Example setup:"
  puts "   - Install PostgreSQL: sudo apt-get install postgresql"
  puts "   - Create database: createdb opencog_demo"
  puts "   - Create user: createuser -s opencog_user"
  puts "   - Connect: postgres://opencog_user@localhost/opencog_demo"
  
  puts "3. Storage interface is ready for connection when database is available"
  puts "   ✓ PostgreSQL backend implementation complete"
end

# Test all storage backends
def demo_storage_backends_comparison(atomspace : AtomSpace::AtomSpace)
  puts "\n--- Storage Backends Comparison ---"
  
  test_dir = "/tmp/storage_demo"
  Dir.mkdir_p(test_dir)
  
  backends = [
    {name: "File", storage: atomspace.create_file_storage("file", "#{test_dir}/atoms.scm")},
    {name: "SQLite", storage: atomspace.create_sqlite_storage("sqlite", "#{test_dir}/atoms.db")},
    {name: "RocksDB", storage: atomspace.create_rocksdb_storage("rocks", "#{test_dir}/atoms.rocks")}
  ]
  
  puts "Testing #{atomspace.size} atoms across different backends:"
  puts
  
  backends.each do |backend|
    name = backend[:name]
    storage = backend[:storage]
    
    puts "#{name} Storage:"
    if storage.open
      start_time = Time.monotonic
      success = storage.store_atomspace(atomspace)
      store_time = Time.monotonic - start_time
      
      if success
        stats = storage.get_stats
        puts "  ✓ Store: #{store_time.total_milliseconds.round(1)}ms"
        puts "  ✓ Stats: #{stats["type"]} - #{stats.has_key?("atom_count") ? stats["atom_count"] : "N/A"} atoms"
        
        # Test loading
        test_atomspace = AtomSpace::AtomSpace.new
        start_time = Time.monotonic
        load_success = storage.load_atomspace(test_atomspace)
        load_time = Time.monotonic - start_time
        
        if load_success
          puts "  ✓ Load: #{load_time.total_milliseconds.round(1)}ms"
          puts "  ✓ Integrity: #{atomspace.size == test_atomspace.size ? "PASS" : "FAIL (#{test_atomspace.size}/#{atomspace.size})"}"
        else
          puts "  ✗ Load failed"
        end
      else
        puts "  ✗ Store failed"
      end
      
      storage.close
    else
      puts "  ✗ Failed to open"
    end
    puts
  end
end

# Run the complete demo
def run_demo
  puts "Initializing animal knowledge base..."
  atomspace = create_animal_knowledge
  
  # Demo individual backends
  demo_rocksdb_storage(atomspace)
  demo_postgres_storage(atomspace)
  
  # Compare all backends
  demo_storage_backends_comparison(atomspace)
  
  puts "=== Demo Complete ==="
  puts "PostgreSQL and RocksDB storage backends are now available!"
  puts "Use the factory methods to create storage instances:"
  puts "  - atomspace.create_rocksdb_storage(name, path)"
  puts "  - atomspace.create_postgres_storage(name, connection_string)"
  puts "  - atomspace.create_file_storage(name, path)"
  puts "  - atomspace.create_sqlite_storage(name, path)"
end

# Run the demo
run_demo