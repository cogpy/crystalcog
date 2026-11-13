require "spec"
require "file_utils"
require "../../src/ai_integration/ai_bridge"
require "../integrations/platform/support/tiny_qwen3"

describe "AIIntegration model backends" do
  it "answers from the AtomSpace with the knowledge model" do
    space = AtomSpace::AtomSpace.new
    cat = space.add_concept_node("cat")
    space.add_inheritance_link(cat, space.add_concept_node("mammal"), AtomSpace::SimpleTruthValue.new(0.9, 0.8))
    space.add_inheritance_link(cat, space.add_concept_node("pet"), AtomSpace::SimpleTruthValue.new(0.6, 0.5))
    space.add_concept_node("lonely")

    manager = AIIntegration::CrystalAIManager.new(space)
    manager.load_model("kb", AIIntegration::ModelConfig.new("/models/none", AIIntegration::ModelType::CUSTOM)).should be_true
    manager.describe_model("kb").not_nil!.should contain("knowledge model")

    about_cat = manager.infer_simple("kb", "What is a Cat?", "s1")
    about_cat.success.should be_true
    about_cat.text.should contain(%((INHERITANCELINK (CONCEPTNODE "cat") (CONCEPTNODE "mammal")) (strength 0.9, confidence 0.8)))
    about_cat.text.index("mammal").not_nil!.should be < about_cat.text.index("pet").not_nil!
    # Mean of strength x confidence over the two facts used: (0.72 + 0.30) / 2.
    about_cat.confidence_score.should be_close(0.51, 0.001)

    manager.infer_simple("kb", "lonely", "s1").text.should contain("no relationships")
    unknown = manager.infer_simple("kb", "zebra", "s1")
    unknown.text.should contain("holds nothing about: zebra")
    unknown.confidence_score.should eq(0.0_f32)

    manager.session_history("s1").size.should eq(6)
    manager.session_history("s1")[0].should eq({"user", "What is a Cat?"})
    manager.get_stats["total_inferences"].should eq(3)
    manager.destroy_session("s1")
    manager.session_history("s1").should be_empty
  end

  it "refuses models nothing can serve" do
    manager = AIIntegration::CrystalAIManager.new
    manager.load_model("gguf", AIIntegration::ModelConfig.new("/models/missing.gguf", AIIntegration::ModelType::GGML)).should be_false
    manager.last_error.should contain("not a server URL or a Qwen3 model directory")
    manager.is_model_loaded?("gguf").should be_false
    manager.unload_model("gguf").should be_false
  end

  it "runs a Qwen3 directory in-process and a server by URL, with session history" do
    dir = TinyQwen3.write(File.tempname("tiny-qwen3"))
    begin
      manager = AIIntegration::CrystalAIManager.new
      local = AIIntegration::ModelConfig.new(dir, AIIntegration::ModelType::TRANSFORMER)
      local.context_length = 256_u32
      manager.load_model("local", local).should be_true
      manager.describe_model("local").not_nil!.should contain("Qwen3 in-process")

      request = AIIntegration::InferenceRequest.new("hello", "chat")
      request.max_tokens = 5_u32
      request.temperature = 0.0_f32
      first = manager.infer("local", request)
      first.success.should be_true
      first.tokens_generated.should be > 0
      # A real model reports how sure it was of the tokens it chose.
      first.confidence_score.should be > 0.0_f32
      first.confidence_score.should be <= 1.0_f32
      manager.session_history("chat").size.should eq(2)
      manager.infer("local", request).success.should be_true
      manager.session_history("chat").map(&.[0]).should eq(["user", "assistant", "user", "assistant"])

      server = AphroditeJax::Server.new(AphroditeJax::Generator.load(dir, 256), "tiny", requested_port: 0).start
      begin
        manager.load_model("remote", AIIntegration::ModelConfig.new(server.url, AIIntegration::ModelType::TRANSFORMER)).should be_true
        manager.describe_model("remote").should eq("tiny at #{server.url}")
        remote_request = AIIntegration::InferenceRequest.new("hello", "other")
        remote_request.max_tokens = 5_u32
        remote_request.temperature = 0.0_f32
        remote = manager.infer("remote", remote_request)
        remote.success.should be_true
        remote.text.should eq(first.text)
      ensure
        server.stop
      end

      # A server that is gone is an inference failure, not an exception.
      gone = manager.infer("remote", AIIntegration::InferenceRequest.new("hello", "other"))
      gone.success.should be_false
      gone.error_message.should contain("Inference failed")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "gives the cognitive integration a knowledge model over its own AtomSpace" do
    space = AtomSpace::AtomSpace.new
    space.add_inheritance_link(space.add_concept_node("dog"), space.add_concept_node("animal"),
      AtomSpace::SimpleTruthValue.new(0.95, 0.9))
    integration = AIIntegration.create_integration(space)
    integration.setup_ai_workbench(integration.create_default_workbench).should be_true

    integration.interactive_reasoning_session("dog").should contain(%((INHERITANCELINK (CONCEPTNODE "dog") (CONCEPTNODE "animal"))))
    integration.knowledge_enrichment("dog").first.should contain("AI Insight: About")
    integration.ai_manager.get_stats["total_inferences"].should be >= 3
  end
end
