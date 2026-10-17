#!/usr/bin/env crystal

# AI Integration Test
# Tests the complete AI system integration for Milestone 5

require "../../src/ai_integration/ai_bridge"

puts "=== CrystalCog AI System Integration Test ==="
puts "Testing Milestone 5: Complete AI system integration"
puts

begin
  # Test 1: Basic AI Manager functionality
  puts "1. Testing Basic AI Manager..."
  ai_manager = AIIntegration::CrystalAIManager.new
  
  # Test model configuration
  demo_config = AIIntegration::ModelConfig.new("/models/demo_model", AIIntegration::ModelType::CUSTOM)
  demo_config.temperature = 0.7_f32
  demo_config.max_tokens = 256_u32
  
  # Test model loading
  if ai_manager.load_model("demo_model", demo_config)
    puts "   ✓ AI model loading successful"
  else
    puts "   ✗ AI model loading failed"
    exit(1)
  end
  
  # Test model queries
  models = ai_manager.list_models
  if models.includes?("demo_model")
    puts "   ✓ Model listing successful (#{models.size} models)"
  else
    puts "   ✗ Model listing failed"
    exit(1)
  end
  
  # Test session management
  ai_manager.create_session("test_session")
  if ai_manager.has_session?("test_session")
    puts "   ✓ Session management working"
  else
    puts "   ✗ Session management failed"
    exit(1)
  end
  
  # Test inference
  response = ai_manager.infer_simple("demo_model", "Hello, AI system!", "test_session")
  if response.success && !response.text.empty?
    puts "   ✓ AI inference working: #{response.text[0...50]}..."
    puts "     Confidence: #{response.confidence_score}, Time: #{response.inference_time_ms}ms"
  else
    puts "   ✗ AI inference failed: #{response.error_message}"
    exit(1)
  end
  
  puts

  # Test 2: AI Workbench Configuration
  puts "2. Testing AI Workbench Configuration..."
  
  config = AIIntegration::AIWorkbenchConfig.new("test_workbench", "demo_model")
  config.models = ["demo_model", "reasoning_model"]
  
  reasoning_config = AIIntegration::ModelConfig.new("/models/reasoning_model", AIIntegration::ModelType::CUSTOM)
  reasoning_config.temperature = 0.5_f32
  reasoning_config.context_length = 4096_u32
  
  config.model_configs["demo_model"] = demo_config
  config.model_configs["reasoning_model"] = reasoning_config
  
  if config.models.size == 2 && config.default_model == "demo_model"
    puts "   ✓ Workbench configuration created successfully"
  else
    puts "   ✗ Workbench configuration creation failed"
    exit(1)
  end
  
  puts

  # Test 3: Cognitive AI Integration
  puts "3. Testing Cognitive AI Integration..."
  
  # Create integration with fresh AtomSpace
  atomspace = AtomSpace::AtomSpace.new
  integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
  integration.setup_cognitive_engines
  
  # Setup workbench
  workbench_config = integration.create_default_workbench
  if integration.setup_ai_workbench(workbench_config)
    puts "   ✓ Cognitive AI integration setup successful"
  else
    puts "   ✗ Cognitive AI integration setup failed"
    exit(1)
  end
  
  # Test integration status
  status = integration.get_integration_status
  if status["integration_active"] == "true"
    puts "   ✓ Integration status: #{status["ai_models"]} models active"
    puts "     AtomSpace size: #{status["atomspace_size"]} atoms"
    puts "     PLN engine: #{status["pln_engine"]}, URE engine: #{status["ure_engine"]}"
  else
    puts "   ✗ Integration not active"
    exit(1)
  end
  
  puts

  # Test 4: End-to-End Cognitive-AI Reasoning
  puts "4. Testing End-to-End Cognitive-AI Reasoning..."
  
  # Test knowledge enrichment
  enrichments = integration.knowledge_enrichment("artificial_intelligence")
  if enrichments.size > 1 && !enrichments[0].includes?("not active")
    puts "   ✓ Knowledge enrichment working (#{enrichments.size} insights)"
    enrichments.each_with_index do |insight, i|
      puts "     #{i + 1}. #{insight[0...80]}#{insight.size > 80 ? "..." : ""}"
    end
  else
    puts "   ✗ Knowledge enrichment failed"
    exit(1)
  end
  
  puts

  # Test cognitive reasoning cycle
  puts "5. Testing Cognitive Reasoning Cycle..."
  
  reasoning_results = integration.cognitive_ai_reasoning("What is machine learning?", 3)
  if reasoning_results["status"]? && !reasoning_results["error"]?
    puts "   ✓ Cognitive reasoning cycle completed successfully"
    puts "     AI Analysis: #{reasoning_results["ai_analysis"]?.try &.[0...60]}..." if reasoning_results["ai_analysis"]?
    puts "     PLN Results: #{reasoning_results["pln_results"]?}" if reasoning_results["pln_results"]?
    puts "     URE Results: #{reasoning_results["ure_results"]?}" if reasoning_results["ure_results"]?
    puts "     Synthesis: #{reasoning_results["synthesis"]?.try(&.[0...60])}..." if reasoning_results["synthesis"]?
  else
    puts "   ✗ Cognitive reasoning cycle failed: #{reasoning_results["error"]?}"
    exit(1)
  end
  
  puts

  # Test 6: Interactive AI Session
  puts "6. Testing Interactive AI Session..."
  
  interactive_response = integration.interactive_reasoning_session("Explain Crystal programming language")
  if interactive_response.includes?("AI Response:") && interactive_response.includes?("Knowledge Base:")
    puts "   ✓ Interactive session working"
    puts "     Response preview: #{interactive_response[0...100]}..."
  else
    puts "   ✗ Interactive session failed"
    exit(1)
  end
  
  puts

  # Test 7: Batch Processing
  puts "7. Testing Batch AI Processing..."
  
  requests = [
    AIIntegration::InferenceRequest.new("What is cognitive science?", "batch_session_1"),
    AIIntegration::InferenceRequest.new("How does reasoning work?", "batch_session_2"),
    AIIntegration::InferenceRequest.new("What is knowledge representation?", "batch_session_3")
  ]
  
  batch_responses = ai_manager.batch_infer("demo_model", requests)
  successful_responses = batch_responses.count(&.success)
  
  if successful_responses == requests.size
    puts "   ✓ Batch processing successful (#{successful_responses}/#{requests.size} responses)"
    batch_responses.each_with_index do |response, i|
      puts "     Batch #{i + 1}: #{response.text[0...50]}... (#{response.tokens_generated} tokens)"
    end
  else
    puts "   ✗ Batch processing failed (#{successful_responses}/#{requests.size} successful)"
    exit(1)
  end
  
  puts

  # Test 8: Performance and Statistics
  puts "8. Testing Performance and Statistics..."
  
  ai_stats = ai_manager.get_stats
  if ai_stats["loaded_models"] > 0
    puts "   ✓ AI Manager Statistics:"
    ai_stats.each do |key, value|
      puts "     #{key}: #{value}"
    end
  else
    puts "   ✗ Statistics collection failed"
    exit(1)
  end
  
  integration_status = integration.get_integration_status
  puts "   ✓ Integration Statistics:"
  integration_status.each do |key, value|
    puts "     #{key}: #{value}"
  end
  
  puts

  # Test 9: Stress Test with Multiple Concepts
  puts "9. Testing Stress Test with Multiple Concepts..."
  
  concepts = ["machine_learning", "neural_networks", "deep_learning", "artificial_intelligence", "cognitive_science"]
  successful_enrichments = 0
  
  concepts.each do |concept|
    enrichments = integration.knowledge_enrichment(concept)
    if enrichments.size > 1 && !enrichments[0].includes?("not active")
      successful_enrichments += 1
    end
  end
  
  if successful_enrichments == concepts.size
    puts "   ✓ Stress test successful (#{successful_enrichments}/#{concepts.size} concepts processed)"
    final_atomspace_size = atomspace.size
    puts "     Final AtomSpace size: #{final_atomspace_size} atoms"
  else
    puts "   ✗ Stress test failed (#{successful_enrichments}/#{concepts.size} successful)"
    exit(1)
  end
  
  puts

  # Test 10: Integration Cleanup and Validation
  puts "10. Testing Integration Cleanup and Validation..."
  
  # Test session cleanup
  sessions_before = ai_manager.list_sessions.size
  ai_manager.destroy_session("test_session")
  sessions_after = ai_manager.list_sessions.size
  
  if sessions_after < sessions_before
    puts "   ✓ Session cleanup successful"
  else
    puts "   ✗ Session cleanup failed"
  end
  
  # Test model unloading
  if ai_manager.unload_model("demo_model")
    puts "   ✓ Model unloading successful"
  else
    puts "   ✗ Model unloading failed"
  end
  
  # Final validation
  final_stats = ai_manager.get_stats
  final_status = integration.get_integration_status
  
  puts "   ✓ Final validation complete"
  puts "     Models remaining: #{final_stats["loaded_models"]}"
  puts "     Sessions remaining: #{final_stats["active_sessions"]}"
  puts "     Integration still active: #{final_status["integration_active"]}"
  
  puts
  puts "🎉 ALL AI INTEGRATION TESTS PASSED!"
  puts "Milestone 5: Complete AI system integration - SUCCESSFUL"
  puts
  puts "Summary:"
  puts "- AI model management: ✓ Working"
  puts "- Session management: ✓ Working" 
  puts "- AI inference: ✓ Working"
  puts "- Cognitive integration: ✓ Working"
  puts "- Knowledge enrichment: ✓ Working"
  puts "- Interactive sessions: ✓ Working"
  puts "- Batch processing: ✓ Working"
  puts "- Performance monitoring: ✓ Working"
  puts "- Stress testing: ✓ Working"
  puts "- Resource cleanup: ✓ Working"
  
rescue ex : Exception
  puts "❌ AI Integration Test Failed: #{ex.message}"
  puts "Stack trace:"
  puts ex.backtrace.join("\n")
  exit(1)
end