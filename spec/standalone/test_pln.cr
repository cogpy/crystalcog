#!/usr/bin/env crystal

# Test PLN (Probabilistic Logic Networks) functionality
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/pln/pln"

puts "Testing PLN (Probabilistic Logic Networks) functionality..."

# Initialize the systems
CogUtil.initialize
AtomSpace.initialize
PLN.initialize

# Create an AtomSpace
atomspace = AtomSpace::AtomSpace.new

# Create a knowledge base
puts "\nCreating knowledge base..."

# Add some concepts
mammal = atomspace.add_concept_node("mammal")
animal = atomspace.add_concept_node("animal")
dog = atomspace.add_concept_node("dog")
fido = atomspace.add_concept_node("Fido")

# Add inheritance relationships with truth values
puts "Adding inheritance relationships..."

# Dog is a mammal (high confidence)
dog_mammal = atomspace.add_inheritance_link(
  dog, mammal, 
  AtomSpace::SimpleTruthValue.new(0.95, 0.9)
)

# Mammal is an animal (very high confidence)
mammal_animal = atomspace.add_inheritance_link(
  mammal, animal,
  AtomSpace::SimpleTruthValue.new(0.98, 0.95)
)

# Fido is a dog (certain)
fido_dog = atomspace.add_inheritance_link(
  fido, dog,
  AtomSpace::SimpleTruthValue.new(1.0, 1.0)
)

puts "Initial knowledge base:"
puts "  #{dog_mammal}"
puts "  #{mammal_animal}"
puts "  #{fido_dog}"
puts "AtomSpace size: #{atomspace.size}"

# Create PLN reasoning engine
puts "\nCreating PLN reasoning engine..."
pln_engine = PLN.create_engine(atomspace)

# Perform reasoning
puts "\nPerforming PLN reasoning..."
new_atoms = pln_engine.reason(3)

puts "\nReasoning results:"
puts "Generated #{new_atoms.size} new atoms:"
new_atoms.each do |atom|
  puts "  #{atom}"
end

puts "\nFinal AtomSpace size: #{atomspace.size}"

# Look for specific inferred relationships
puts "\nLooking for specific inferences..."

# Should have inferred: Fido -> mammal, dog -> animal, Fido -> animal
inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

puts "All inheritance relationships:"
inheritance_links.each do |link|
  puts "  #{link}"
end

# Test forward chaining for a specific target
puts "\nTesting forward chaining for inheritance links..."
inheritance_results = pln_engine.forward_chain(AtomSpace::AtomType::INHERITANCE_LINK, 3)
puts "Forward chaining found #{inheritance_results.size} inheritance links"

puts "\nPLN test completed successfully!"