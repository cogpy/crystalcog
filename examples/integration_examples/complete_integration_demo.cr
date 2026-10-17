# Integration Example - Complete demonstration of all integrations with cognitive agency
#
# This example demonstrates how to use all CrystalCog integration components
# including the Galatea frontend (github.com/9cog/galatea-frontend) and
# Paphos backend (github.com/9cog/paphos-backend) with optimal cognitive agency grip.

require "../../src/integrations/integration"
require "../../src/atomspace/atomspace"
require "../../src/cogutil/logger"

# Initialize logging
CogUtil::Logger.set_level(CogUtil::LogLevel::INFO)

puts "="*70
puts "CrystalCog Integration Example with Cognitive Agency"
puts "="*70
puts ""
puts "External Repository Integrations:"
puts "  - Galatea Frontend: #{CrystalCogIntegration::EXTERNAL_REPOS["galatea"]}"
puts "  - Paphos Backend:   #{CrystalCogIntegration::EXTERNAL_REPOS["paphos"]}"
puts ""

# Create AtomSpace
puts "1. Creating AtomSpace..."
atomspace = AtomSpace::AtomSpace.new

# Add some initial knowledge
dog = atomspace.add_concept_node("dog")
animal = atomspace.add_concept_node("animal")
atomspace.add_inheritance_link(dog, animal)

cat = atomspace.add_concept_node("cat")
atomspace.add_inheritance_link(cat, animal)

intelligence = atomspace.add_concept_node("intelligence")
cognition = atomspace.add_concept_node("cognition")
atomspace.add_inheritance_link(intelligence, cognition)

puts "   Added concepts: dog, cat, animal, intelligence, cognition"
puts ""

# Quick setup - creates and initializes all integrations with optimal cognitive grip
puts "2. Quick Setup - Initializing All Integrations with Cognitive Agency..."
manager = CrystalCogIntegration.quick_setup(atomspace)
puts "   All integrations initialized with cognitive agency coordination!"
puts ""

# Check integration status including cognitive agency
puts "3. Checking Integration Status..."
status = manager.get_integration_status

puts "   COGNITIVE AGENCY:"
if agency_status = status["cognitive_agency"]?
  puts "     - Agency Strength: #{agency_status["agency_strength"]?}"
  puts "     - Optimal: #{agency_status["optimal"]?}"
  puts "     - Grip Strength: #{agency_status["grip_grip_strength"]?}"
  puts "     - Linked Components: #{agency_status["linked_components"]?}"
end
puts ""

puts "   GALATEA FRONTEND (#{GalateaFrontend::EXTERNAL_REPO}):"
if galatea_status = status["galatea"]?
  puts "     - Status: #{galatea_status["interface_status"]?}"
  puts "     - Host: #{galatea_status["host"]?}:#{galatea_status["port"]?}"
  puts "     - Cognitive Agency Mode: #{galatea_status["cognitive_agency_mode"]?}"
  puts "     - Grip Strength: #{galatea_status["grip_strength"]?}"
  puts "     - React Bridge Connected: #{galatea_status["react_bridge_connected"]?}"
end
puts ""

puts "   PAPHOS BACKEND (#{PaphosBackend::EXTERNAL_REPO}):"
if paphos_status = status["paphos"]?
  puts "     - Status: #{paphos_status["connector_status"]?}"
  puts "     - API Prefix: #{paphos_status["api_prefix"]?}"
  puts "     - Coordination Mode: #{paphos_status["grip_coordination_mode"]?}"
  puts "     - Stream Connected: #{paphos_status["stream_connected"]?}"
end
puts ""

# Execute cognitive pipeline with full agency coordination
puts "4. Executing Integrated Cognitive Pipeline with Agency..."
input = "What is the relationship between dogs and animals? Explain cognitive architectures."
puts "   Input: #{input}"
puts ""

result = manager.execute_cognitive_pipeline(input)

puts "   Pipeline Results:"
puts "     - Status: #{result["status"]}"
puts "     - Agency Processed: #{result["agency_processed"]?}"
puts "     - Agency Strength: #{result["agency_strength"]?}"
puts "     - Coherence: #{result["coherence"]?}"
puts "     - Galatea Pipeline: #{result["galatea_pipeline"]?}"
puts "     - Paphos Coordination: #{result["paphos_coordination"]?}"
puts "     - Paphos Sync: #{result["paphos_sync"]?}"
puts ""

# Demonstrate cognitive grip coordination
puts "5. Coordinating Cognitive Grip Across All Integrations..."
grip_result = manager.coordinate_cognitive_grip("Focus on intelligence and cognition")

puts "   Grip Coordination Results:"
puts "     - Coordination Complete: #{grip_result["coordination_complete"]?}"
puts "     - Galatea Grip Applied: #{grip_result["galatea_grip"]?}"
puts "     - Paphos Grip Consensus: #{grip_result["paphos_grip"]?}"
puts ""

# Demonstrate agency modulation
puts "6. Modulating Cognitive Agency..."
manager.modulate_agency("focus", 0.8)
puts "   Applied 'focus' modulation (intensity: 0.8)"

manager.modulate_agency("engage", 0.7)
puts "   Applied 'engage' modulation (intensity: 0.7)"

manager.modulate_agency("cohere", 0.9)
puts "   Applied 'cohere' modulation (intensity: 0.9)"
puts ""

# Get thought stream
puts "7. Recent Thoughts from Cognitive Stream..."
thoughts = manager.get_thought_stream(5)
puts "   Captured #{thoughts.size} thoughts:"
thoughts.each_with_index do |thought, idx|
  content = thought["content"]? || ""
  content_preview = content.size > 50 ? "#{content[0, 50]}..." : content
  puts "     #{idx + 1}. [#{thought["type"]?}] #{content_preview}"
end
puts ""

# Get attention focuses
puts "8. Top Attention Focuses..."
focuses = manager.get_attention_focuses(5)
puts "   Top #{focuses.size} focus items:"
focuses.each_with_index do |(word, weight), idx|
  puts "     #{idx + 1}. '#{word}' (weight: #{weight.round(3)})"
end
puts ""

# Store cognitive snapshot
puts "9. Storing Cognitive Snapshot to Paphos..."
snapshot_id = "demo_snapshot_#{Time.utc.to_unix}"
if manager.store_cognitive_snapshot(snapshot_id)
  puts "   Snapshot stored: #{snapshot_id}"
else
  puts "   Failed to store snapshot"
end
puts ""

# Load cognitive snapshot
puts "10. Loading Cognitive Snapshot from Paphos..."
if snapshot = manager.load_cognitive_snapshot(snapshot_id)
  puts "    Snapshot loaded:"
  puts "      - ID: #{snapshot["snapshot_id"]?}"
  puts "      - Status: #{snapshot["status"]?}"
end
puts ""

# Demonstrate individual component usage with cognitive grip
puts "11. Individual Component Usage with Cognitive Agency..."
puts ""

# Galatea Frontend with cognitive grip
if frontend = manager.galatea_frontend
  puts "   Galatea Frontend:"
  grip_result = frontend.apply_cognitive_grip("Analyze intelligence patterns")
  puts "     Grip Applied: #{grip_result["grip_applied"]?}"
  puts "     Coherence Maintained: #{grip_result["coherence_maintained"]?}"
  puts ""
end

# Paphos Backend with cognitive coordination
if connector = manager.paphos_connector
  puts "   Paphos Backend:"
  command_result = connector.send_command("analyze", {"target" => "cognition"})
  puts "     Command Status: #{command_result["status"]?}"
  puts "     Coherence: #{command_result["coherence"]?}"
  puts ""
end

# Pygmalion Agent
if agent = manager.pygmalion_agent
  puts "   Pygmalion Agent:"
  chat_response = agent.chat("Explain how cognitive agency works")
  puts "     Chat response: #{chat_response[0..80]}..."
  puts ""
end

# Crystal Accelerator
if accelerator = manager.crystal_accelerator
  puts "   Crystal Accelerator:"
  accelerator_status = accelerator.status
  puts "     Status: #{accelerator_status["engine_status"]}"
  puts "     Optimization level: #{accelerator_status["optimization_level"]}"
  puts ""
end

# Final status check
puts "12. Final Integration Status Check..."
final_status = manager.get_integration_status

if agency = final_status["cognitive_agency"]?
  puts "    Cognitive Agency Final State:"
  puts "      - Agency Strength: #{agency["agency_strength"]?}"
  puts "      - Optimal: #{agency["optimal"]?}"
  puts "      - Thoughts Count: #{agency["thoughts_total_thoughts"]?}"
  puts "      - Attention Focus Count: #{agency["attention_focus_count"]?}"
end
puts ""

# Shutdown
puts "13. Shutting Down Integrations..."
manager.shutdown_all
puts "    All integrations shut down successfully"
puts ""

puts "="*70
puts "Integration Example with Cognitive Agency Complete!"
puts "="*70
puts ""
puts "Summary:"
puts "  - Integrated Galatea frontend with React bridge and cognitive grip"
puts "  - Integrated Paphos backend with Lucky API and grip coordination"
puts "  - Unified cognitive agency controller coordinated all components"
puts "  - Attention mechanism tracked focus across inputs"
puts "  - Thought stream captured cognitive processing"
puts "  - Cognitive snapshots stored/loaded via Paphos persistence"
puts ""
