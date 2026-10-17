require "../../src/attention/attention_main"

# Simple test of attention system
puts "Testing Attention System..."

# Create atomspace
atomspace = AtomSpace::AtomSpace.new
puts "Created atomspace with #{atomspace.size} atoms"

# Create some atoms
dog = atomspace.add_concept_node("dog")
puts "Created dog concept: #{dog}"

# Create attention engine  
engine = Attention::AllocationEngine.new(atomspace)
puts "Created attention engine: #{engine}"

# Test stimulation
engine.bank.stimulate(dog.handle, 100_i16)
av = engine.bank.get_attention_value(dog.handle)
puts "Dog attention after stimulation: #{av}"

# Test statistics
stats = engine.get_allocation_statistics
puts "Engine statistics: #{stats.size} entries"
stats.each { |k, v| puts "  #{k}: #{v}" }

puts "Test completed successfully!"