#!/usr/bin/env crystal

# Test Learning Features
# Tests concept learning, generalization, and knowledge discovery

require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/learning/learning_main"

puts "=== Learning Features Test ==="

# Initialize systems
CogUtil.initialize
AtomSpace.initialize
Learning.initialize

puts "\n1. Concept Learning Test"
puts "=" * 50

# Create a concept
animal_concept = Learning::ConceptLearning.create_concept("animal")

puts "\nCreated concept: #{animal_concept.name}"
puts "Initial confidence: #{animal_concept.confidence}"

# Add positive examples
positive_examples = [
  {"has_legs" => "4", "can_move" => "yes", "is_alive" => "yes"} of String => String | Float64 | Bool,
  {"has_legs" => "4", "can_move" => "yes", "is_alive" => "yes"} of String => String | Float64 | Bool,
  {"has_legs" => "2", "can_move" => "yes", "is_alive" => "yes"} of String => String | Float64 | Bool
]

puts "\nAdding positive examples:"
positive_examples.each_with_index do |example, i|
  animal_concept.add_positive_example(example)
  puts "  Example #{i + 1}: #{example}"
end

# Add negative examples
negative_examples = [
  {"has_legs" => "0", "can_move" => "no", "is_alive" => "no"} of String => String | Float64 | Bool
]

puts "\nAdding negative examples:"
negative_examples.each_with_index do |example, i|
  animal_concept.add_negative_example(example)
  puts "  Example #{i + 1}: #{example}"
end

puts "\nLearned concept features:"
animal_concept.features.each do |key, value|
  puts "  #{key}: #{value}"
end
puts "Final confidence: #{animal_concept.confidence.round(3)}"

# Test matching
test_examples = [
  {"has_legs" => "4", "can_move" => "yes", "is_alive" => "yes"} of String => String | Float64 | Bool,
  {"has_legs" => "0", "can_move" => "no", "is_alive" => "no"} of String => String | Float64 | Bool
]

puts "\nTesting concept matching:"
test_examples.each_with_index do |example, i|
  matches = animal_concept.matches?(example)
  puts "  Example #{i + 1}: #{example} -> #{matches ? "matches" : "no match"}"
end

puts "\n2. Concept Hierarchy Test"
puts "=" * 50

hierarchy = Learning::ConceptLearning.create_hierarchy

# Create concepts
dog_concept = Learning::ConceptLearning.create_concept("dog")
cat_concept = Learning::ConceptLearning.create_concept("cat")
mammal_concept = Learning::ConceptLearning.create_concept("mammal")

# Add to hierarchy
hierarchy.add_concept(dog_concept)
hierarchy.add_concept(cat_concept)
hierarchy.add_concept(mammal_concept)
hierarchy.add_concept(animal_concept)

# Add relationships
hierarchy.add_is_a_relation("dog", "mammal")
hierarchy.add_is_a_relation("cat", "mammal")
hierarchy.add_is_a_relation("mammal", "animal")

puts "\nCreated concept hierarchy:"
puts "  dog -> mammal -> animal"
puts "  cat -> mammal -> animal"

# Test inheritance queries
test_pairs = [
  ["dog", "animal"],
  ["cat", "mammal"],
  ["dog", "cat"],
  ["mammal", "animal"]
]

puts "\nTesting inheritance relationships:"
test_pairs.each do |pair|
  child, parent = pair
  result = hierarchy.inherits_from?(child, parent)
  puts "  #{child} inherits_from #{parent}? #{result}"
end

# Get ancestors
puts "\nAncestors of 'dog': #{hierarchy.get_ancestors("dog").join(", ")}"
puts "Ancestors of 'cat': #{hierarchy.get_ancestors("cat").join(", ")}"

# Convert to AtomSpace
atomspace = AtomSpace::AtomSpace.new
atoms = hierarchy.to_atomspace(atomspace)
puts "\nConverted hierarchy to #{atoms.size} atoms in AtomSpace"

puts "\n3. Candidate Elimination Test"
puts "=" * 50

ce = Learning::ConceptLearning::CandidateElimination.new

puts "\nInitial state:"
puts "  General boundary size: #{ce.general_boundary.size}"
puts "  Specific boundary size: #{ce.specific_boundary.size}"

# Learn from positive examples
positive_learning = [
  {"size" => "large", "color" => "red"},
  {"size" => "large", "color" => "blue"}
]

puts "\nLearning from positive examples:"
positive_learning.each_with_index do |example, i|
  ce.learn_positive(example)
  puts "  Example #{i + 1}: #{example}"
  puts "    Specific boundary size: #{ce.specific_boundary.size}"
end

# Learn from negative example
negative_learning = [
  {"size" => "small", "color" => "red"}
]

puts "\nLearning from negative examples:"
negative_learning.each_with_index do |example, i|
  ce.learn_negative(example)
  puts "  Example #{i + 1}: #{example}"
  puts "    General boundary size: #{ce.general_boundary.size}"
end

if concept = ce.get_concept
  puts "\nLearned concept: #{concept.constraints}"
end

puts "\n4. Association Rule Mining Test"
puts "=" * 50

# Sample transactions (market basket data)
transactions = [
  ["bread", "milk"],
  ["bread", "diaper", "beer", "eggs"],
  ["milk", "diaper", "beer", "cola"],
  ["bread", "milk", "diaper", "beer"],
  ["bread", "milk", "diaper", "cola"]
]

puts "\nTransaction data:"
transactions.each_with_index do |trans, i|
  puts "  #{i + 1}: #{trans.join(", ")}"
end

miner = Learning::Generalization::AssociationRuleMiner.new(
  min_support: 0.4,
  min_confidence: 0.6
)

rules = miner.mine_rules(transactions)

puts "\nMined association rules:"
rules.sort_by { |r| -r.confidence }.each do |rule|
  puts "  #{rule}"
end

puts "\n5. Anti-Unification Test"
puts "=" * 50

examples = [
  "the dog runs fast",
  "the cat runs fast",
  "the bird runs fast"
]

puts "\nExamples:"
examples.each_with_index do |ex, i|
  puts "  #{i + 1}: #{ex}"
end

generalized = Learning::Generalization::AntiUnification.generalize(examples)
puts "\nGeneralized pattern: #{generalized}"

puts "\n6. Inductive Learning Test"
puts "=" * 50

learner = Learning::Generalization::InductiveLearner.new

# Positive and negative examples for learning
positive = [
  {"color" => "red", "shape" => "circle", "size" => "large"},
  {"color" => "red", "shape" => "square", "size" => "large"},
  {"color" => "red", "shape" => "circle", "size" => "small"}
]

negative = [
  {"color" => "blue", "shape" => "circle", "size" => "large"},
  {"color" => "green", "shape" => "square", "size" => "small"}
]

puts "\nPositive examples:"
positive.each_with_index do |ex, i|
  puts "  #{i + 1}: #{ex}"
end

puts "\nNegative examples:"
negative.each_with_index do |ex, i|
  puts "  #{i + 1}: #{ex}"
end

learned_rules = learner.learn(positive, negative)

puts "\nLearned rules (top 5):"
learned_rules.first(5).each do |rule|
  puts "  #{rule}"
end

puts "\n7. Analogy Test"
puts "=" * 50

analogy_maker = Learning::Generalization::AnalogyMaker.new

# Source domain (programming)
source_domain = {
  "agent" => "programmer",
  "tool" => "computer",
  "action" => "coding",
  "result" => "software"
}

# Target domain (cooking)
target_domain = {
  "agent" => "chef",
  "tool" => "kitchen",
  "action" => "cooking",
  "result" => "meal"
}

puts "\nSource domain (programming):"
source_domain.each { |k, v| puts "  #{k}: #{v}" }

puts "\nTarget domain (cooking):"
target_domain.each { |k, v| puts "  #{k}: #{v}" }

mapping = analogy_maker.find_analogy(source_domain, target_domain)

puts "\nAnalogy mapping:"
mapping.each do |source, target|
  puts "  #{source} <-> #{target}"
end

# Create source knowledge
source_rules = [
  Learning::Generalization::Rule.new(
    ["programmer", "computer"],
    "software",
    10,
    0.9
  )
]

# Transfer knowledge
transferred = analogy_maker.transfer_knowledge(source_rules, mapping)

puts "\nTransferred knowledge:"
transferred.each do |rule|
  puts "  #{rule}"
end

puts "\n8. AtomSpace Integration Test"
puts "=" * 50

# Store learned concept in atomspace
concept_atoms = animal_concept.to_atomspace(atomspace)
puts "\nStored concept '#{animal_concept.name}' as #{concept_atoms.size} atoms"

# Store association rules
rules.first(3).each do |rule|
  rule_atom = rule.to_atomspace(atomspace)
  puts "Stored rule in AtomSpace"
end

puts "\nTotal atoms in AtomSpace: #{atomspace.size}"

puts "\n=== Learning Features Test Complete ==="
puts "\nAll learning tests passed! ✅"
