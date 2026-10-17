# Test atomspace iteration issue
require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"

CogUtil.initialize
AtomSpace.initialize

puts "=== AtomSpace Iteration Debug ==="

# Create simple test with fewer atoms
atomspace = AtomSpace::AtomSpace.new
puts "Empty atomspace size: #{atomspace.size}"

dog = atomspace.add_concept_node("dog")
puts "After adding 'dog', size: #{atomspace.size}"
puts "Dog handle: #{dog.handle}, name: #{dog.name}"

animal = atomspace.add_concept_node("animal")
puts "After adding 'animal', size: #{atomspace.size}"
puts "Animal handle: #{animal.handle}, name: #{animal.name}"

inheritance = atomspace.add_inheritance_link(dog, animal)
puts "After adding inheritance link, size: #{atomspace.size}"
puts "Link handle: #{inheritance.handle}, arity: #{inheritance.arity}"
puts "Link outgoing handles: #{inheritance.outgoing.map(&.handle)}"

puts "\nAll atoms via get_all_atoms:"
all_atoms = atomspace.get_all_atoms
puts "get_all_atoms returned #{all_atoms.size} atoms"
all_atoms.each_with_index do |atom, i|
  puts "#{i+1}. Handle: #{atom.handle}, Type: #{atom.type}, Class: #{atom.class.name}"
  if atom.is_a?(AtomSpace::Node)
    puts "   Name: #{atom.name}"
  elsif atom.is_a?(AtomSpace::Link)
    puts "   Arity: #{atom.arity}, Outgoing: #{atom.outgoing.map(&.handle)}"
  end
end

puts "\nDirect access test:"
puts "get_atom(dog.handle): #{atomspace.get_atom(dog.handle)}"
puts "get_atom(animal.handle): #{atomspace.get_atom(animal.handle)}"
puts "get_atom(inheritance.handle): #{atomspace.get_atom(inheritance.handle)}"