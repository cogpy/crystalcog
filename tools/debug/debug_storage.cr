# Debug test for storage issues
require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"

CogUtil.initialize
AtomSpace.initialize

puts "=== Storage Debug Test ==="

# Create simple test with fewer atoms
atomspace = AtomSpace::AtomSpace.new
dog = atomspace.add_concept_node("dog")
animal = atomspace.add_concept_node("animal")
inheritance = atomspace.add_inheritance_link(dog, animal)

puts "Original atomspace:"
puts "Size: #{atomspace.size}"
atomspace.get_all_atoms.each_with_index do |atom, i|
  puts "#{i+1}. #{atom.class.name}: #{atom.type} - Handle: #{atom.handle} - #{atom.is_a?(AtomSpace::Node) ? atom.name : "Link(#{atom.arity})"}"
  if atom.is_a?(AtomSpace::Link)
    puts "   Outgoing: #{atom.outgoing.map(&.handle)}"
  end
end

# Test RocksDB storage
storage = AtomSpace::RocksDBStorageNode.new("debug", "/tmp/debug_rocks")
storage.open

puts "\nStoring atoms individually..."
atomspace.get_all_atoms.each_with_index do |atom, i|
  result = storage.store_atom(atom)
  puts "#{i+1}. Stored #{atom.handle} (#{atom.is_a?(AtomSpace::Node) ? atom.name : "Link"}): #{result}"
end

puts "\nRocksDB Stats: #{storage.get_stats}"

# Test loading
new_atomspace = AtomSpace::AtomSpace.new
storage.load_atomspace(new_atomspace)

puts "\nLoaded atomspace:"
puts "Size: #{new_atomspace.size}"
new_atomspace.get_all_atoms.each_with_index do |atom, i|
  puts "#{i+1}. #{atom.class.name}: #{atom.type} - Handle: #{atom.handle} - #{atom.is_a?(AtomSpace::Node) ? atom.name : "Link(#{atom.arity})"}"
  if atom.is_a?(AtomSpace::Link)
    puts "   Outgoing: #{atom.outgoing.map(&.handle)}"
  end
end

storage.close