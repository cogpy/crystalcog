#!/usr/bin/env crystal

# Simple demonstration of the Crystal OpenCog AtomSpace implementation
# This shows the basic functionality without requiring the full Crystal compiler

require "../../src/crystalcog"

# Initialize the system
puts "=== CrystalCog Demo ==="
puts

CrystalCog.initialize

# Create an atomspace
puts "Creating AtomSpace..."
atomspace = AtomSpace.new_atomspace

# Create some basic concepts
puts "Adding concepts..."
dog = atomspace.add_concept_node("dog")
cat = atomspace.add_concept_node("cat")  
animal = atomspace.add_concept_node("animal")
mammal = atomspace.add_concept_node("mammal")

# Create inheritance relationships
puts "Adding inheritance relationships..."
dog_is_animal = atomspace.add_inheritance_link(dog, animal)
cat_is_animal = atomspace.add_inheritance_link(cat, animal)
dog_is_mammal = atomspace.add_inheritance_link(dog, mammal)
cat_is_mammal = atomspace.add_inheritance_link(cat, mammal)

# Create some facts
puts "Adding facts..."
likes_pred = atomspace.add_predicate_node("likes")
john = atomspace.add_concept_node("John")
mary = atomspace.add_concept_node("Mary")

# John likes dogs
john_likes_dogs_args = atomspace.add_list_link([john, dog])
john_likes_dogs = atomspace.add_evaluation_link(likes_pred, john_likes_dogs_args, 
  AtomSpace::SimpleTruthValue.new(0.9, 0.8))

# Mary likes cats  
mary_likes_cats_args = atomspace.add_list_link([mary, cat])
mary_likes_cats = atomspace.add_evaluation_link(likes_pred, mary_likes_cats_args,
  AtomSpace::SimpleTruthValue.new(0.85, 0.9))

# Show statistics
puts
puts "=== AtomSpace Statistics ==="
atomspace.print_statistics

# Demonstrate queries
puts
puts "=== Query Examples ==="

# Find all inheritance relationships
puts "All inheritance relationships:"
inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
inheritance_links.each do |link|
  if link.is_a?(AtomSpace::Link) && link.arity == 2
    child = link.outgoing[0]
    parent = link.outgoing[1]
    if child.is_a?(AtomSpace::Node) && parent.is_a?(AtomSpace::Node)
      puts "  #{child.name} -> #{parent.name} #{link.truth_value}"
    end
  end
end

# Find what John likes
puts
puts "What John likes:"
john_facts = AtomSpace::Query.find_facts(atomspace, "John")
john_facts.each do |fact|
  if fact.is_a?(AtomSpace::Link) && fact.evaluation_link?
    pred = fact.outgoing[0]
    args = fact.outgoing[1]
    if pred.is_a?(AtomSpace::Node) && args.is_a?(AtomSpace::Link)
      puts "  #{pred.name}: #{args.to_s} #{fact.truth_value}"
    end
  end
end

# Demonstrate truth value operations
puts
puts "=== Truth Value Operations ==="
tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
tv2 = AtomSpace::SimpleTruthValue.new(0.6, 0.7)

puts "TV1: #{tv1}"
puts "TV2: #{tv2}"
puts "AND: #{AtomSpace::TruthValueUtil.and_tv(tv1, tv2)}"
puts "OR:  #{AtomSpace::TruthValueUtil.or_tv(tv1, tv2)}"
puts "NOT TV1: #{AtomSpace::TruthValueUtil.not_tv(tv1)}"

# Factory method demonstration  
puts
puts "=== Factory Methods ==="
AtomSpace::Factory.create_taxonomy(atomspace, {
  "poodle" => ["dog"],
  "siamese" => ["cat"], 
  "persian" => ["cat"]
})

AtomSpace::Factory.create_fact(atomspace, "color", "poodle", "brown")
AtomSpace::Factory.create_numeric_fact(atomspace, "age", "John", 25.0)

puts "After adding taxonomy and facts:"
atomspace.print_statistics

# Pattern matching demonstration
puts
puts "=== Pattern Matching ==="
color_facts = AtomSpace::Query.match_pattern(atomspace, "color", nil, nil)
puts "All color facts: #{color_facts.size}"

age_facts = AtomSpace::Query.match_pattern(atomspace, "age", nil, nil)
puts "All age facts: #{age_facts.size}"

# Statistics
puts
puts "=== Advanced Statistics ==="
type_dist = AtomSpace::Statistics.type_distribution(atomspace)
puts "Type distribution:"
type_dist.each do |type, count|
  puts "  #{type}: #{count}"
end

tv_stats = AtomSpace::Statistics.truth_value_stats(atomspace)
puts
puts "Truth value statistics:"
puts "  Mean strength: #{tv_stats[:mean_strength].round(3)}"
puts "  Mean confidence: #{tv_stats[:mean_confidence].round(3)}"
puts "  Total atoms: #{tv_stats[:total_atoms]}"

puts
puts "=== Demo Complete ==="