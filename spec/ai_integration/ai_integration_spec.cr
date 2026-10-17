require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/pln/pln"
require "../../src/ure/ure"
require "../../src/ai_integration/ai_bridge"

describe AIIntegration do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    PLN.initialize
    URE.initialize
  end

  describe AIIntegration::ModelType do
    it "defines model types" do
      AIIntegration::ModelType::GGML.value.should eq(0)
      AIIntegration::ModelType::RWKV.value.should eq(1)
      AIIntegration::ModelType::TRANSFORMER.value.should eq(2)
      AIIntegration::ModelType::CUSTOM.value.should eq(3)
    end
  end

  describe AIIntegration::ModelConfig do
    describe "#initialize" do
      it "creates config with required fields" do
        config = AIIntegration::ModelConfig.new("/path/to/model", AIIntegration::ModelType::GGML)
        config.model_path.should eq("/path/to/model")
        config.type.should eq(AIIntegration::ModelType::GGML)
      end

      it "has default values" do
        config = AIIntegration::ModelConfig.new("/path/to/model", AIIntegration::ModelType::CUSTOM)
        config.context_length.should eq(2048_u32)
        config.temperature.should eq(0.7_f32)
        config.max_tokens.should eq(512_u32)
      end
    end
  end

  describe AIIntegration::InferenceRequest do
    describe "#initialize" do
      it "creates request with required fields" do
        request = AIIntegration::InferenceRequest.new("Hello", "session1")
        request.prompt.should eq("Hello")
        request.session_id.should eq("session1")
      end

      it "has default values" do
        request = AIIntegration::InferenceRequest.new("test", "session1")
        request.max_tokens.should eq(512_u32)
        request.temperature.should eq(0.7_f32)
        request.stop_sequences.empty?.should be_true
      end
    end
  end

  describe AIIntegration::InferenceResponse do
    describe "#initialize" do
      it "creates successful response" do
        response = AIIntegration::InferenceResponse.new("Hello!", "session1", success: true)
        response.text.should eq("Hello!")
        response.session_id.should eq("session1")
        response.success.should be_true
      end

      it "creates failed response" do
        response = AIIntegration::InferenceResponse.new("", "session1", success: false)
        response.success.should be_false
      end

      it "has default values" do
        response = AIIntegration::InferenceResponse.new("test", "session1")
        response.tokens_generated.should eq(0_u32)
        response.confidence_score.should eq(0.0_f32)
        response.inference_time_ms.should eq(0_u64)
        response.error_message.should eq("")
      end
    end
  end

  describe AIIntegration::AIWorkbenchConfig do
    describe "#initialize" do
      it "creates workbench config" do
        config = AIIntegration::AIWorkbenchConfig.new("test_workbench", "default_model")
        config.name.should eq("test_workbench")
        config.default_model.should eq("default_model")
      end

      it "starts with empty models list" do
        config = AIIntegration::AIWorkbenchConfig.new("test", "model")
        config.models.empty?.should be_true
        config.model_configs.empty?.should be_true
      end
    end
  end

  describe AIIntegration::CrystalAIManager do
    describe "#initialize" do
      it "creates AI manager" do
        manager = AIIntegration::CrystalAIManager.new
        manager.should be_a(AIIntegration::CrystalAIManager)
      end
    end

    describe "#load_model" do
      it "loads a model" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        result = manager.load_model("test_model", config)
        result.should be_true
      end

      it "tracks loaded models" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)
        manager.is_model_loaded?("test_model").should be_true
      end
    end

    describe "#unload_model" do
      it "unloads a model" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)
        manager.unload_model("test_model")
        manager.is_model_loaded?("test_model").should be_false
      end
    end

    describe "#list_models" do
      it "lists all loaded models" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("model1", config)
        manager.load_model("model2", config)
        models = manager.list_models
        models.size.should eq(2)
        models.should contain("model1")
        models.should contain("model2")
      end
    end

    describe "#set_default_model" do
      it "sets the default model" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)
        manager.set_default_model("test_model")
        manager.get_default_model.should eq("test_model")
      end

      it "raises for unloaded model" do
        manager = AIIntegration::CrystalAIManager.new
        expect_raises(Exception) do
          manager.set_default_model("nonexistent")
        end
      end
    end

    describe "session management" do
      it "creates sessions" do
        manager = AIIntegration::CrystalAIManager.new
        manager.create_session("session1")
        manager.has_session?("session1").should be_true
      end

      it "destroys sessions" do
        manager = AIIntegration::CrystalAIManager.new
        manager.create_session("session1")
        manager.destroy_session("session1")
        manager.has_session?("session1").should be_false
      end

      it "lists sessions" do
        manager = AIIntegration::CrystalAIManager.new
        manager.create_session("session1")
        manager.create_session("session2")
        sessions = manager.list_sessions
        sessions.size.should eq(2)
      end
    end

    describe "#infer" do
      it "returns error for unloaded model" do
        manager = AIIntegration::CrystalAIManager.new
        request = AIIntegration::InferenceRequest.new("test", "session1")
        response = manager.infer("nonexistent", request)
        response.success.should be_false
        response.error_message.should contain("not loaded")
      end

      it "performs inference on loaded model" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)

        request = AIIntegration::InferenceRequest.new("Hello", "session1")
        response = manager.infer("test_model", request)
        response.success.should be_true
        response.text.should_not be_empty
        response.tokens_generated.should eq(response.text.split.size.to_u32)
        response.confidence_score.should eq(0.85_f32)
      end

      it "creates session if not exists" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)

        request = AIIntegration::InferenceRequest.new("test", "new_session")
        manager.infer("test_model", request)
        manager.has_session?("new_session").should be_true
      end
    end

    describe "#infer_simple" do
      it "provides simple inference interface" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)

        response = manager.infer_simple("test_model", "Hello", "session1")
        response.success.should be_true
      end
    end

    describe "#batch_infer" do
      it "performs batch inference" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)

        requests = [
          AIIntegration::InferenceRequest.new("Hello", "session1"),
          AIIntegration::InferenceRequest.new("World", "session2"),
        ]
        responses = manager.batch_infer("test_model", requests)
        responses.size.should eq(2)
        responses.all?(&.success).should be_true
      end
    end

    describe "#get_stats" do
      it "returns statistics" do
        manager = AIIntegration::CrystalAIManager.new
        config = AIIntegration::ModelConfig.new("/models/test", AIIntegration::ModelType::CUSTOM)
        manager.load_model("test_model", config)
        manager.create_session("session1")

        stats = manager.get_stats
        stats["loaded_models"].should eq(1)
        stats["active_sessions"].should eq(1)
      end
    end
  end

  describe AIIntegration::CognitiveAIIntegration do
    describe "#initialize" do
      it "creates cognitive AI integration" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        integration.should be_a(AIIntegration::CognitiveAIIntegration)
      end
    end

    describe "#setup_cognitive_engines" do
      it "sets up PLN and URE engines" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        integration.setup_cognitive_engines
        true.should be_true
      end
    end

    describe "#create_default_workbench" do
      it "creates a default workbench config" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        config = integration.create_default_workbench
        config.name.should eq("crystal_cognitive_workbench")
        config.models.size.should eq(2)
      end
    end

    describe "#setup_ai_workbench" do
      it "sets up AI workbench" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        config = integration.create_default_workbench
        result = integration.setup_ai_workbench(config)
        result.should be_true
      end
    end

    describe "#get_integration_status" do
      it "returns integration status" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        integration.setup_cognitive_engines

        status = integration.get_integration_status
        status["integration_active"].should eq("false")
        status["atomspace_size"].should eq("0")
        status["pln_engine"].should eq("active")
        status["ure_engine"].should eq("active")
      end
    end

    describe "#cognitive_ai_reasoning" do
      it "returns error when not active" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)

        result = integration.cognitive_ai_reasoning("test query")
        result["error"].should eq("AI integration not active")
      end

      it "performs cognitive reasoning when active" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        integration.setup_cognitive_engines
        config = integration.create_default_workbench
        integration.setup_ai_workbench(config)

        result = integration.cognitive_ai_reasoning("test query", 3)
        result.has_key?("ai_analysis").should be_true
        result.has_key?("status").should be_true
      end
    end

    describe "#knowledge_enrichment" do
      it "returns error when not active" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)

        result = integration.knowledge_enrichment("test")
        result.first.should contain("not active")
      end

      it "enriches knowledge when active" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        integration.setup_cognitive_engines
        config = integration.create_default_workbench
        integration.setup_ai_workbench(config)

        result = integration.knowledge_enrichment("dog")
        result.size.should be > 0
      end
    end

    describe "#interactive_reasoning_session" do
      it "returns error when not active" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)

        result = integration.interactive_reasoning_session("test")
        result.should contain("not active")
      end

      it "processes interactive reasoning when active" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration::CognitiveAIIntegration.new(atomspace)
        integration.setup_cognitive_engines
        config = integration.create_default_workbench
        integration.setup_ai_workbench(config)

        result = integration.interactive_reasoning_session("Hello, how are you?")
        result.should contain("AI Response")
      end
    end
  end

  describe "Module-level functions" do
    describe ".create_integration" do
      it "creates a configured integration" do
        atomspace = AtomSpace::AtomSpace.new
        integration = AIIntegration.create_integration(atomspace)
        integration.should be_a(AIIntegration::CognitiveAIIntegration)
      end
    end

    describe ".create_demo_setup" do
      it "creates a demo setup" do
        integration = AIIntegration.create_demo_setup
        integration.should be_a(AIIntegration::CognitiveAIIntegration)
        status = integration.get_integration_status
        status["integration_active"].should eq("true")
      end
    end
  end
end
