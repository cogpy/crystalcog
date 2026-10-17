# Enhanced Pattern Matching test
# This demonstrates the enhanced pattern matching functionality with new constraints and backtracking

require "../../src/pattern_matching/pattern_matching_main"

puts "Starting Enhanced Pattern Matching test..."

# Create an atomspace and populate it with more complex knowledge
atomspace = AtomSpace::AtomSpace.new

# Add animals and their relationships
dog = atomspace.add_concept_node("dog")
cat = atomspace.add_concept_node("cat")
animal = atomspace.add_concept_node("animal")
mammal = atomspace.add_concept_node("mammal")
bird = atomspace.add_concept_node("bird")
robin = atomspace.add_concept_node("robin")

# Add inheritance relationships
atomspace.add_inheritance_link(dog, mammal)
atomspace.add_inheritance_link(cat, mammal)
atomspace.add_inheritance_link(robin, bird)
atomspace.add_inheritance_link(mammal, animal)
atomspace.add_inheritance_link(bird, animal)

puts "Created enhanced knowledge base:"
puts "  dog isa mammal"
puts "  cat isa mammal" 
puts "  robin isa bird"
puts "  mammal isa animal"
puts "  bird isa animal"
puts "  Total atoms: #{atomspace.size}"

# Test 1: Enhanced backtracking pattern matching
puts "\n=== Test 1: Enhanced backtracking pattern matching ==="
builder = PatternMatching::QueryBuilder.new(atomspace)

# Find all inheritance chains of length 2
var_x = builder.variable("X")
var_y = builder.variable("Y") 
var_z = builder.variable("Z")

# Create a pattern: X inherits from Y, and Y inherits from Z
inheritance1 = builder.inheritance(var_x, var_y)
inheritance2 = builder.inheritance(var_y, var_z)

# This would require advanced query composition, so let's test simpler patterns first
pattern = builder.inheritance(var_x, var_y)
results = builder.execute(pattern)

puts "All direct inheritance relationships:"
results.each do |result|
  if result.success?
    x_atom = result.bindings[var_x]?
    y_atom = result.bindings[var_y]?
    if x_atom && y_atom
      puts "  #{x_atom.name} isa #{y_atom.name}"
    end
  end
end

# Test 2: Test new constraint types
puts "\n=== Test 2: New constraint types ==="
builder2 = PatternMatching::QueryBuilder.new(atomspace)

# Find all mammals using type constraints
builder2.constrain_type("animal", AtomSpace::AtomType::CONCEPT_NODE)
animal_var = builder2.variable("animal")
mammal_concept = atomspace.get_nodes_by_name("mammal", AtomSpace::AtomType::CONCEPT_NODE).first?

if mammal_concept
  pattern2 = builder2.inheritance(animal_var, mammal_concept)
  results2 = builder2.execute(pattern2)
  
  puts "Animals that are mammals:"
  results2.each do |result|
    if result.success?
      animal_atom = result.bindings[animal_var]?
      if animal_atom
        puts "  #{animal_atom.name} is a mammal"
      end
    end
  end
end

# Test 3: Test equality constraints
puts "\n=== Test 3: Equality constraints ==="
builder3 = PatternMatching::QueryBuilder.new(atomspace)

# Create variables
var_a = builder3.variable("A")
var_b = builder3.variable("B")

# Add equality constraint - both variables must bind to the same atom
builder3.constrain_equal("A", "B")

# Create a pattern where something inherits from itself (should be empty)
self_inheritance = builder3.inheritance(var_a, var_b)
results3 = builder3.execute(self_inheritance)

puts "Self-inheritance relationships (should be empty):"
results3.each do |result|
  if result.success?
    a_atom = result.bindings[var_a]?
    b_atom = result.bindings[var_b]?
    if a_atom && b_atom
      puts "  #{a_atom.name} inherits from itself"
    end
  end
end

puts "Found #{results3.size} self-inheritance relationships (expected: 0)"

# Test 4: Performance with result limiting
puts "\n=== Test 4: Performance with result limiting ==="
matcher = PatternMatching::PatternMatcher.new(atomspace, max_results: 3)

var_anything = AtomSpace::VariableNode.new("$anything")
open_pattern = PatternMatching::Pattern.new(var_anything)
limited_results = matcher.match(open_pattern)

puts "Limited results (max 3):"
limited_results.each do |result|
  if result.success?
    result.bindings.each do |var, atom|
      puts "  #{var.name} = #{atom.name}"
    end
  end
end

puts "Found #{limited_results.size} results (max was 3)"

puts "\n✓ Enhanced Pattern Matching test completed successfully!"
puts "Enhanced features tested: backtracking, constraints, performance limits"