# Pattern Matching integration test
# This demonstrates the basic pattern matching functionality

require "../../src/pattern_matching/pattern_matching_main"

puts "Starting Pattern Matching integration test..."

# Create an atomspace and populate it with some knowledge
atomspace = AtomSpace::AtomSpace.new

# Add some animals and their relationships
dog = atomspace.add_concept_node("dog")
cat = atomspace.add_concept_node("cat")
animal = atomspace.add_concept_node("animal")
mammal = atomspace.add_concept_node("mammal")

# Add inheritance relationships
atomspace.add_inheritance_link(dog, mammal)
atomspace.add_inheritance_link(cat, mammal)
atomspace.add_inheritance_link(mammal, animal)

puts "Created knowledge base:"
puts "  dog isa mammal"
puts "  cat isa mammal"
puts "  mammal isa animal"
puts "  Total atoms: #{atomspace.size}"

# Test 1: Simple pattern matching with Utils
puts "\n=== Test 1: Simple inheritance matching ==="
results = PatternMatching::Utils.match_inheritance(atomspace, "dog", nil)
puts "What does dog inherit from?"
results.each do |result|
  if result.success?
    result.bindings.each do |var, atom|
      puts "  #{var.name} = #{atom}"
    end
  end
end

# Test 2: Using the QueryBuilder for more complex queries
puts "\n=== Test 2: QueryBuilder pattern matching ==="
builder = PatternMatching::QueryBuilder.new(atomspace)

# Find all animals that are mammals
var_x = builder.variable("X")
pattern = builder.inheritance(var_x, mammal)

results = builder.execute(pattern)
puts "What are mammals?"
results.each do |result|
  if result.success?
    result.bindings.each do |var, atom|
      if var.name == "$X"
        puts "  #{atom.name} is a mammal"
      end
    end
  end
end

# Test 3: More complex pattern with type constraints
puts "\n=== Test 3: Pattern with type constraints ==="
builder2 = PatternMatching::QueryBuilder.new(atomspace)
builder2.constrain_type("Y", AtomSpace::AtomType::CONCEPT_NODE)

var_y = builder2.variable("Y")
pattern2 = builder2.inheritance(var_y, animal)

results2 = builder2.execute(pattern2)
puts "What inherits from animal?"
results2.each do |result|
  if result.success?
    result.bindings.each do |var, atom|
      if var.name == "$Y"
        puts "  #{atom.name} inherits from animal"
      end
    end
  end
end

# Test 4: Direct pattern matcher usage
puts "\n=== Test 4: Direct PatternMatcher usage ==="
matcher = PatternMatching::PatternMatcher.new(atomspace)

# Create a pattern to find inheritance links
var_child = AtomSpace::VariableNode.new("$child")
var_parent = AtomSpace::VariableNode.new("$parent")
inheritance_pattern = AtomSpace::InheritanceLink.new(var_child, var_parent)

pattern = PatternMatching::Pattern.new(inheritance_pattern)
results3 = matcher.match(pattern)

puts "All inheritance relationships:"
results3.each do |result|
  if result.success?
    child_atom = result.bindings[var_child]?
    parent_atom = result.bindings[var_parent]?
    if child_atom && parent_atom
      puts "  #{child_atom.name} isa #{parent_atom.name}"
    end
  end
end

puts "\n✓ Pattern Matching integration test completed successfully!"
puts "Found #{results3.size} total pattern matches"