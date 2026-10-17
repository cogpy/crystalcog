#!/usr/bin/env crystal

# Basic test of the CrystalCog system
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/opencog/opencog"

puts "Testing CrystalCog basic functionality..."

# Initialize the systems
CogUtil.initialize
AtomSpace.initialize
OpenCog.initialize

# Create an AtomSpace
atomspace = AtomSpace::AtomSpace.new

# Create some basic atoms
puts "Creating atoms..."
dog = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "dog")
animal = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "animal")
inheritance = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [dog, animal])

puts "Created atoms:"
puts "  Dog: #{dog}"
puts "  Animal: #{animal}"
puts "  Inheritance: #{inheritance}"
puts "AtomSpace size: #{atomspace.size}"

# Test AtomSpace operations
puts "\nTesting AtomSpace operations..."
puts "Contains dog? #{atomspace.contains?(dog)}"
puts "Contains animal? #{atomspace.contains?(animal)}"

# Get all concept nodes
concept_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
puts "Concept nodes: #{concept_nodes.size}"

# Test OpenCog functionality
puts "\nTesting OpenCog functionality..."
reasoner = OpenCog.create_reasoner(atomspace)

# Add more knowledge for reasoning
cat = atomspace.add_concept_node("Cat")
mammal = atomspace.add_concept_node("Mammal")
atomspace.add_inheritance_link(dog, mammal)
atomspace.add_inheritance_link(cat, mammal)
atomspace.add_inheritance_link(mammal, animal)

puts "Added mammal hierarchy"
puts "AtomSpace size before reasoning: #{atomspace.size}"

# Perform reasoning
reasoning_results = reasoner.reason(3)
puts "Generated #{reasoning_results.size} new inferences"
puts "AtomSpace size after reasoning: #{atomspace.size}"

# Test AtomUtils
puts "\nTesting AtomUtils..."
hierarchy = {
  "Fish" => ["Animal", "Pet"],
  "Bird" => ["Animal", "Flying"]
}

created = OpenCog::AtomUtils.create_hierarchy(atomspace, hierarchy)
puts "Created #{created.size} atoms from hierarchy"

# Test similarity
if dog && cat
  similarity = OpenCog::Reasoning.similarity(atomspace, dog, cat)
  puts "Dog-Cat similarity: #{similarity}"
end

puts "\nCrystalCog OpenCog test completed successfully!"
puts "Final AtomSpace size: #{atomspace.size}"