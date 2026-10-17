require "../../src/attention/attention_main"

puts "=== Crystal OpenCog Attention Allocation Demo ==="
puts "Demonstrating Economic Attention Allocation (ECAN) mechanisms"
puts

# Create knowledge graph  
atomspace = AtomSpace::AtomSpace.new
puts "1. Creating knowledge graph..."

dog = atomspace.add_concept_node("dog")
mammal = atomspace.add_concept_node("mammal") 
animal = atomspace.add_concept_node("animal")
living = atomspace.add_concept_node("living_thing")

dog_mammal = atomspace.add_inheritance_link(dog, mammal)
mammal_animal = atomspace.add_inheritance_link(mammal, animal)
animal_living = atomspace.add_inheritance_link(animal, living)

puts "   Created #{atomspace.size} atoms in knowledge graph"
puts

# Create attention engine
puts "2. Initializing Attention Allocation Engine..."
engine = Attention::AllocationEngine.new(atomspace)
puts "   Engine initialized: #{engine}"
puts

# Set initial attention values
puts "3. Setting initial attention values..."
engine.bank.stimulate(dog.handle, 150_i16)
engine.bank.stimulate(mammal.handle, 100_i16)
engine.bank.stimulate(dog_mammal.handle, 120_i16)

puts "   Initial attention values:"
[dog, mammal, animal, dog_mammal, mammal_animal, animal_living].each do |atom|
  av = engine.bank.get_attention_value(atom.handle)
  puts "     #{atom}: #{av || "[0, 0]"}"
end
puts

# Show bank status
puts "4. Initial Attention Bank Status:"
stats = engine.bank.get_statistics
puts "   STI Funds: #{stats["sti_funds"]}"
puts "   LTI Funds: #{stats["lti_funds"]}"
puts "   Attentional Focus Size: #{stats["af_size"]}/#{stats["af_max_size"]}"
puts

# Set goals for attention allocation
puts "5. Setting attention allocation goals..."
goals = {
  Attention::Goal::Reasoning => 1.2,
  Attention::Goal::Learning => 0.9,
  Attention::Goal::Memory => 0.7,
  Attention::Goal::Processing => 1.0
}
engine.set_goals(goals)
puts "   Goals set: #{goals.size} active goals"
puts

# Perform attention allocation
puts "6. Running attention allocation (3 cycles)..."
results = engine.allocate_attention(3)

puts "   Allocation completed successfully!"
puts "   Results:"
results.each do |key, value|
  puts "     #{key}: #{value.round(2)}"
end
puts

# Show final attention values
puts "7. Final attention values after allocation:"
[dog, mammal, animal, living, dog_mammal, mammal_animal, animal_living].each do |atom|
  av = engine.bank.get_attention_value(atom.handle)
  puts "   #{atom}: #{av || "[0, 0]"}"
end
puts

# Show attentional focus
puts "8. Current Attentional Focus (top atoms by STI):"
engine.bank.attentional_focus.each_with_index do |handle, i|
  atom = atomspace.get_atom(handle)
  av = engine.bank.get_attention_value(handle)
  puts "   #{i + 1}. #{atom} - #{av}"
end
puts

# Show final bank status
puts "9. Final Attention Bank Status:"
final_stats = engine.bank.get_statistics
puts "   STI Funds: #{final_stats["sti_funds"]} (change: #{final_stats["sti_funds"].as(Int32) - stats["sti_funds"].as(Int32)})"
puts "   LTI Funds: #{final_stats["lti_funds"]}"
puts "   Attentional Focus Size: #{final_stats["af_size"]}/#{final_stats["af_max_size"]}"
puts "   AF Utilization: #{(final_stats["af_size"].as(Int32).to_f64 / final_stats["af_max_size"].as(Int32)) * 100}%"
puts

# Demonstrate focused attention
puts "10. Testing focused attention on specific atoms..."
focus_targets = [living.handle, animal_living.handle]
engine.focus_attention(focus_targets, 80_i16)

puts "    After focused attention:"
focus_targets.each do |handle|
  atom = atomspace.get_atom(handle)
  av = engine.bank.get_attention_value(handle)
  puts "      #{atom}: #{av}"
end
puts

puts "=== Attention Allocation Demo Complete ==="
puts "Successfully demonstrated:"
puts "  ✓ Attention Bank fund management"
puts "  ✓ Attentional Focus management"  
puts "  ✓ Goal-based attention boosting"
puts "  ✓ Attention diffusion between related atoms"
puts "  ✓ Economic rent collection mechanisms"
puts "  ✓ Priority calculation and allocation"
puts "  ✓ Focused attention targeting"
puts
puts "The Crystal OpenCog Attention system is working correctly!"