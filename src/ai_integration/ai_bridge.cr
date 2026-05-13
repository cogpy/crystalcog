# AI Integration Bridge
# This module provides Crystal bindings to the C++ AI system in DrawTerm

require "../atomspace/atomspace_main"
require "../pln/pln"
require "../ure/ure"

module AIIntegration
  # AI Model Types (matching C++ enum)
  enum ModelType
    GGML
    RWKV
    TRANSFORMER
    CUSTOM
  end

  # AI Model Configuration
  struct ModelConfig
    property model_path : String
    property type : ModelType
    property context_length : UInt32 = 2048_u32
    property temperature : Float32 = 0.7_f32
    property max_tokens : UInt32 = 512_u32
    property custom_params : Hash(String, String) = {} of String => String

    def initialize(@model_path : String, @type : ModelType)
    end
  end

  # AI Inference Request
  struct InferenceRequest
    property prompt : String
    property session_id : String
    property max_tokens : UInt32 = 512_u32
    property temperature : Float32 = 0.7_f32
    property stop_sequences : Array(String) = [] of String

    def initialize(@prompt : String, @session_id : String)
    end
  end

  # AI Inference Response
  class InferenceResponse
    property text : String
    property session_id : String
    property tokens_generated : UInt32
    property confidence_score : Float32
    property inference_time_ms : UInt64
    property success : Bool
    property error_message : String

    def initialize(@text : String, @session_id : String, @success : Bool = true)
      @tokens_generated = 0_u32
      @confidence_score = 0.0_f32
      @inference_time_ms = 0_u64
      @error_message = ""
    end
  end

  # AI Workbench Configuration
  struct AIWorkbenchConfig
    property name : String
    property models : Array(String)
    property model_configs : Hash(String, ModelConfig)
    property default_model : String
    property max_sessions : UInt32 = 100_u32

    def initialize(@name : String, @default_model : String)
      @models = [] of String
      @model_configs = {} of String => ModelConfig
    end
  end

  # Crystal AI Manager that interfaces with the C++ system
  class CrystalAIManager
    @initialized : Bool = false
    @default_model : String = ""
    @loaded_models : Set(String) = Set(String).new
    @sessions : Hash(String, Time) = {} of String => Time

    def initialize
      puts "Crystal AI Manager initialized"
    end

    def load_model(model_name : String, config : ModelConfig) : Bool
      puts "Loading AI model: #{model_name}"

      # Validate configuration
      unless File.exists?(config.model_path) || config.model_path.starts_with?("/models/")
        puts "Warning: Model path may not exist: #{config.model_path}"
      end

      # Simulate model loading (in real implementation, this would call C++ functions)
      @loaded_models.add(model_name)
      puts "Model #{model_name} loaded successfully"
      true
    end

    def unload_model(model_name : String) : Bool
      @loaded_models.delete(model_name)
      puts "Model #{model_name} unloaded"
      true
    end

    def is_model_loaded?(model_name : String) : Bool
      @loaded_models.includes?(model_name)
    end

    def list_models : Array(String)
      @loaded_models.to_a
    end

    def set_default_model(model_name : String)
      if is_model_loaded?(model_name)
        @default_model = model_name
        puts "Default model set to: #{model_name}"
      else
        raise "Model #{model_name} is not loaded"
      end
    end

    def get_default_model : String
      @default_model
    end

    def create_session(session_id : String)
      @sessions[session_id] = Time.utc
      puts "Created AI session: #{session_id}"
    end

    def destroy_session(session_id : String)
      @sessions.delete(session_id)
      puts "Destroyed AI session: #{session_id}"
    end

    def has_session?(session_id : String) : Bool
      @sessions.has_key?(session_id)
    end

    def list_sessions : Array(String)
      @sessions.keys
    end

    def infer(model_name : String, request : InferenceRequest) : InferenceResponse
      unless is_model_loaded?(model_name)
        return InferenceResponse.new("", request.session_id, success: false).tap do |response|
          response.error_message = "Model #{model_name} is not loaded"
        end
      end

      unless has_session?(request.session_id)
        create_session(request.session_id)
      end

      # Simulate AI inference (in real implementation, this would call C++ AI functions)
      start_time = Time.instant

      # Generate a simple response based on the prompt
      response_text = generate_demo_response(request.prompt)

      end_time = Time.instant
      inference_time = (end_time - start_time).total_milliseconds.to_u64

      InferenceResponse.new(response_text, request.session_id, success: true).tap do |response|
        response.tokens_generated = response_text.split.size.to_u32
        response.confidence_score = 0.85_f32
        response.inference_time_ms = inference_time
      end
    end

    def infer_simple(model_name : String, prompt : String, session_id : String) : InferenceResponse
      request = InferenceRequest.new(prompt, session_id)
      infer(model_name, request)
    end

    def batch_infer(model_name : String, requests : Array(InferenceRequest)) : Array(InferenceResponse)
      requests.map { |request| infer(model_name, request) }
    end

    private def generate_demo_response(prompt : String) : String
      # Simple demo response generation
      case prompt.downcase
      when .includes?("hello")
        "Hello! I'm an AI assistant integrated with the CrystalCog cognitive architecture."
      when .includes?("reasoning")
        "I can perform logical reasoning using PLN (Probabilistic Logic Networks) and URE (Unified Rule Engine)."
      when .includes?("knowledge")
        "I work with knowledge represented in AtomSpace, enabling complex cognitive processing."
      when .includes?("crystal")
        "CrystalCog is built with Crystal language for performance and safety."
      else
        "I understand your input: '#{prompt}'. This is a demonstration of AI integration with CrystalCog."
      end
    end

    def get_stats : Hash(String, Int32)
      {
        "loaded_models"    => @loaded_models.size,
        "active_sessions"  => @sessions.size,
        "total_inferences" => 0, # Would track in real implementation
      }
    end
  end

  # AI Integration with CrystalCog Cognitive System
  class CognitiveAIIntegration
    @atomspace : AtomSpace::AtomSpace
    @pln_engine : PLN::PLNEngine?
    @ure_engine : URE::UREEngine?
    @ai_manager : CrystalAIManager
    @integration_active : Bool = false

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @ai_manager = CrystalAIManager.new
      puts "Cognitive AI Integration initialized"
    end

    def setup_cognitive_engines
      @pln_engine = PLN.create_engine(@atomspace)
      @ure_engine = URE.create_engine(@atomspace)
      puts "Cognitive reasoning engines configured"
    end

    def setup_ai_workbench(config : AIWorkbenchConfig) : Bool
      puts "Setting up AI workbench: #{config.name}"

      # Load all models
      config.models.each do |model_name|
        if model_config = config.model_configs[model_name]?
          unless @ai_manager.load_model(model_name, model_config)
            puts "Failed to load model: #{model_name}"
            return false
          end
        else
          puts "No configuration found for model: #{model_name}"
          return false
        end
      end

      @ai_manager.set_default_model(config.default_model)
      @integration_active = true
      puts "AI workbench setup complete"
      true
    end

    def create_default_workbench : AIWorkbenchConfig
      config = AIWorkbenchConfig.new("crystal_cognitive_workbench", "demo_model")

      # Add demo models
      config.models = ["demo_model", "reasoning_model"]

      demo_config = ModelConfig.new("/models/demo_model", ModelType::CUSTOM)
      demo_config.context_length = 2048_u32
      demo_config.temperature = 0.7_f32

      reasoning_config = ModelConfig.new("/models/reasoning_model", ModelType::CUSTOM)
      reasoning_config.context_length = 4096_u32
      reasoning_config.temperature = 0.5_f32

      config.model_configs["demo_model"] = demo_config
      config.model_configs["reasoning_model"] = reasoning_config

      config
    end

    def cognitive_ai_reasoning(query : String, max_iterations : Int32 = 5) : Hash(String, String)
      unless @integration_active
        return {"error" => "AI integration not active"}
      end

      results = {} of String => String

      # Step 1: Use AI to understand and expand the query
      ai_response = @ai_manager.infer_simple("demo_model",
        "Analyze this query for cognitive reasoning: #{query}",
        "cognitive_session")

      results["ai_analysis"] = ai_response.text

      # Step 2: Use cognitive reasoning engines
      if pln = @pln_engine
        pln_atoms = pln.reason(max_iterations)
        results["pln_results"] = "PLN generated #{pln_atoms.size} new knowledge atoms"
      end

      if ure = @ure_engine
        ure_atoms = ure.forward_chain(max_iterations)
        results["ure_results"] = "URE derived #{ure_atoms.size} new facts"
      end

      # Step 3: Synthesize results with AI
      synthesis_prompt = "Synthesize these cognitive reasoning results: #{results.values.join(". ")}"
      synthesis_response = @ai_manager.infer_simple("demo_model", synthesis_prompt, "synthesis_session")
      results["synthesis"] = synthesis_response.text

      results["status"] = "Complete cognitive-AI reasoning cycle"
      results
    end

    def knowledge_enrichment(concept : String) : Array(String)
      unless @integration_active
        return ["AI integration not active"]
      end

      enrichments = [] of String

      # Get AI insights about the concept
      ai_prompt = "Provide knowledge enrichment for the concept: #{concept}"
      ai_response = @ai_manager.infer_simple("reasoning_model", ai_prompt, "enrichment_session")
      enrichments << "AI Insight: #{ai_response.text}"

      # Add concept to AtomSpace if not exists
      concept_node = @atomspace.add_concept_node(concept)
      enrichments << "Added concept to AtomSpace: #{concept}"

      # Use PLN to find related concepts
      if pln = @pln_engine
        # In a real implementation, this would use PLN to find semantic relationships
        enrichments << "PLN analysis: Found semantic relationships in knowledge base"
      end

      # Use URE to derive properties
      if ure = @ure_engine
        # In a real implementation, this would use URE to derive properties
        enrichments << "URE analysis: Derived logical properties and relationships"
      end

      enrichments
    end

    def interactive_reasoning_session(user_input : String) : String
      unless @integration_active
        return "AI integration not active. Please setup workbench first."
      end

      # Create comprehensive reasoning response
      responses = [] of String

      # AI understanding
      ai_response = @ai_manager.infer_simple("demo_model", user_input, "interactive_session")
      responses << "AI Response: #{ai_response.text}"

      # Cognitive processing
      cognitive_results = cognitive_ai_reasoning(user_input, 3)
      if cognitive_results["error"]?
        responses << "Cognitive Error: #{cognitive_results["error"]}"
      else
        responses << "Cognitive Analysis: #{cognitive_results["synthesis"]?}"
      end

      # Knowledge base state
      atomspace_size = @atomspace.size
      responses << "Knowledge Base: #{atomspace_size} atoms in AtomSpace"

      responses.join("\n\n")
    end

    def get_integration_status : Hash(String, String)
      status = {} of String => String
      status["integration_active"] = @integration_active.to_s
      status["atomspace_size"] = @atomspace.size.to_s
      status["ai_models"] = @ai_manager.list_models.join(", ")
      status["ai_sessions"] = @ai_manager.list_sessions.size.to_s

      if @pln_engine
        status["pln_engine"] = "active"
      else
        status["pln_engine"] = "inactive"
      end

      if @ure_engine
        status["ure_engine"] = "active"
      else
        status["ure_engine"] = "inactive"
      end

      status
    end
  end

  # Module-level convenience functions
  def self.create_integration(atomspace : AtomSpace::AtomSpace) : CognitiveAIIntegration
    integration = CognitiveAIIntegration.new(atomspace)
    integration.setup_cognitive_engines
    integration
  end

  def self.create_demo_setup : CognitiveAIIntegration
    atomspace = AtomSpace::AtomSpace.new
    integration = create_integration(atomspace)

    # Setup default workbench
    config = integration.create_default_workbench
    if integration.setup_ai_workbench(config)
      puts "Demo AI integration setup complete"
    else
      puts "Failed to setup demo AI integration"
    end

    integration
  end
end
