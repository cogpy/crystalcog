require "spec"
require "../../src/ai_integration/ai_bridge"

describe "AI Integration - Milestone 5" do
  before_each do
    # Initialize fresh systems for each test
    @atomspace = AtomSpace::AtomSpace.new
    @integration = AIIntegration::CognitiveAIIntegration.new(@atomspace)
    @integration.setup_cognitive_engines
  end
  
  # Helper method to access atomspace instance
  def atomspace
    @atomspace
  end

  describe "AI Manager Core Functionality" do
    it "initializes AI manager successfully" do
      ai_manager = AIIntegration::CrystalAIManager.new
      ai_manager.should_not be_nil
      ai_manager.list_models.should be_empty
    end

    it "loads and manages AI models" do
      ai_manager = AIIntegration::CrystalAIManager.new
      config = AIIntegration::ModelConfig.new("/models/test_model", AIIntegration::ModelType::CUSTOM)

      ai_manager.load_model("test_model", config).should be_true
      ai_manager.is_model_loaded?("test_model").should be_true
      ai_manager.list_models.should contain("test_model")

      ai_manager.unload_model("test_model").should be_true
      ai_manager.is_model_loaded?("test_model").should be_false
    end

    it "manages inference sessions" do
      ai_manager = AIIntegration::CrystalAIManager.new

      ai_manager.create_session("test_session")
      ai_manager.has_session?("test_session").should be_true
      ai_manager.list_sessions.should contain("test_session")

      ai_manager.destroy_session("test_session")
      ai_manager.has_session?("test_session").should be_false
    end

    it "performs AI inference" do
      ai_manager = AIIntegration::CrystalAIManager.new
      config = AIIntegration::ModelConfig.new("/models/demo_model", AIIntegration::ModelType::CUSTOM)

      ai_manager.load_model("demo_model", config)
      ai_manager.create_session("inference_test")

      response = ai_manager.infer_simple("demo_model", "Hello AI", "inference_test")
      response.success.should be_true
      response.text.should_not be_empty
      response.session_id.should eq("inference_test")
      response.confidence_score.should be > 0.0
    end

    it "handles batch inference" do
      ai_manager = AIIntegration::CrystalAIManager.new
      config = AIIntegration::ModelConfig.new("/models/demo_model", AIIntegration::ModelType::CUSTOM)
      ai_manager.load_model("demo_model", config)

      requests = [
        AIIntegration::InferenceRequest.new("Query 1", "batch_1"),
        AIIntegration::InferenceRequest.new("Query 2", "batch_2"),
        AIIntegration::InferenceRequest.new("Query 3", "batch_3"),
      ]

      responses = ai_manager.batch_infer("demo_model", requests)
      responses.size.should eq(3)
      responses.all?(&.success).should be_true
    end
  end

  describe "Cognitive AI Integration" do
    it "initializes cognitive AI integration" do
      @integration.should_not be_nil
      status = @integration.get_integration_status
      status["atomspace_size"].should eq("0")
      status["pln_engine"].should eq("active")
      status["ure_engine"].should eq("active")
    end

    it "sets up AI workbench successfully" do
      config = @integration.create_default_workbench
      config.name.should eq("crystal_cognitive_workbench")
      config.models.size.should eq(2)

      result = @integration.setup_ai_workbench(config)
      result.should be_true

      status = @integration.get_integration_status
      status["integration_active"].should eq("true")
      status["ai_models"].should contain("demo_model")
    end

    it "performs knowledge enrichment" do
      config = @integration.create_default_workbench
      @integration.setup_ai_workbench(config)

      enrichments = @integration.knowledge_enrichment("machine_learning")
      enrichments.size.should be > 1
      enrichments.should_not contain("AI integration not active")

      # Should have different types of enrichments
      ai_insights = enrichments.select { |e| e.starts_with?("AI Insight:") }
      atomspace_additions = enrichments.select { |e| e.starts_with?("Added concept") }

      ai_insights.size.should eq(1)
      atomspace_additions.size.should eq(1)
    end

    it "performs cognitive-AI reasoning cycles" do
      config = @integration.create_default_workbench
      @integration.setup_ai_workbench(config)

      results = @integration.cognitive_ai_reasoning("What is artificial intelligence?", 3)

      results.should_not have_key("error")
      results.should have_key("ai_analysis")
      results.should have_key("synthesis")
      results.should have_key("status")

      results["status"].should eq("Complete cognitive-AI reasoning cycle")
      results["ai_analysis"].should_not be_empty
      results["synthesis"].should_not be_empty
    end

    it "handles interactive reasoning sessions" do
      config = @integration.create_default_workbench
      @integration.setup_ai_workbench(config)

      response = @integration.interactive_reasoning_session("Explain cognitive architectures")

      response.should contain("AI Response:")
      response.should contain("Knowledge Base:")
      response.should_not contain("AI integration not active")
    end
  end

  describe "Error Handling and Edge Cases" do
    it "handles inference with unloaded model" do
      ai_manager = AIIntegration::CrystalAIManager.new

      response = ai_manager.infer_simple("nonexistent_model", "Test prompt", "test_session")
      response.success.should be_false
      response.error_message.should contain("not loaded")
    end

    it "handles cognitive reasoning without AI integration" do
      # Don't setup workbench
      results = @integration.cognitive_ai_reasoning("Test query")
      results.should have_key("error")
      results["error"].should eq("AI integration not active")
    end

    it "handles knowledge enrichment without AI integration" do
      # Don't setup workbench
      enrichments = @integration.knowledge_enrichment("test_concept")
      enrichments.should eq(["AI integration not active"])
    end
  end

  describe "Module-level Functions" do
    it "creates integration from atomspace" do
      integration = AIIntegration.create_integration(atomspace)

      integration.should_not be_nil
      status = integration.get_integration_status
      status["pln_engine"].should eq("active")
      status["ure_engine"].should eq("active")
    end

    it "creates demo setup successfully" do
      demo_integration = AIIntegration.create_demo_setup

      demo_integration.should_not be_nil
      status = demo_integration.get_integration_status
      status["integration_active"].should eq("true")
      status["ai_models"].should contain("demo_model")
    end
  end
end
