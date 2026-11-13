# AI Integration Bridge
#
# Runs language models for the cognitive system. A model's path decides
# what serves it:
#
#   http://host:port     an OpenAI-compatible server (aphrodite_jax_server,
#                        Aphrodite, llama.cpp, ...)
#   a model directory    a Qwen3 snapshot (or cached repo id), run in this
#                        process by the native Crystal engine
#   anything else, with  the knowledge model: answers from the AtomSpace
#   ModelType::CUSTOM    itself, with no neural network involved

require "../atomspace/atomspace_main"
require "../pln/pln"
require "../ure/ure"
require "../tools/cog_chat"
require "../integrations/platform/aphrodite_jax_server"

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

  # What a backend produced for one request.
  record ModelOutput, text : String, confidence : Float32, tokens : UInt32

  # Something that can answer a prompt: a language model, or the knowledge base.
  abstract class ModelBackend
    # `history` holds the session's earlier turns as {role, text}.
    abstract def generate(request : InferenceRequest, config : ModelConfig, history : Array({String, String})) : ModelOutput
    abstract def describe : String
  end

  # A language model behind a CogChat engine (in-process or remote).
  class EngineBackend < ModelBackend
    def initialize(@engine : CrystalCog::CogChat::Engine)
    end

    def generate(request : InferenceRequest, config : ModelConfig, history : Array({String, String})) : ModelOutput
      messages = (history + [{"user", request.prompt}]).map do |(role, text)|
        JSON::Any.new({"role" => JSON::Any.new(role), "content" => JSON::Any.new(text)})
      end
      params = AphroditeJax::SamplingParams.new(temperature: request.temperature.to_f64,
        max_tokens: Math.min(request.max_tokens, config.max_tokens).to_i32, stop: request.stop_sequences)
      reply = @engine.chat(messages, nil, params) { }
      tokens = begin
        @engine.tokenize(reply.content).size
      rescue
        reply.content.split.size
      end
      ModelOutput.new(reply.content, reply.confidence.to_f32, tokens.to_u32)
    end

    def describe : String
      @engine.describe
    end
  end

  # The knowledge model: it answers from what the AtomSpace holds about the
  # words in the prompt. Its confidence is that of the facts it used.
  class KnowledgeBackend < ModelBackend
    MAX_FACTS = 8

    def initialize(@atomspace : AtomSpace::AtomSpace)
    end

    def generate(request : InferenceRequest, config : ModelConfig, history : Array({String, String})) : ModelOutput
      words = request.prompt.scan(/[\p{L}\p{N}_'-]+/).map(&.[0]).uniq
      facts = [] of AtomSpace::Atom
      known = [] of String
      words.each do |word|
        nodes = @atomspace.get_nodes_by_name(word)
        nodes = @atomspace.get_nodes_by_name(word.downcase) if nodes.empty?
        next if nodes.empty?
        known << word
        nodes.each { |node| facts.concat(@atomspace.get_incoming(node)) }
      end
      facts = facts.uniq(&.handle).sort_by { |fact| -(fact.truth_value.strength * fact.truth_value.confidence) }

      text = if facts.empty? && known.empty?
               "The knowledge base holds nothing about: #{words.first(6).join(", ")}."
             elsif facts.empty?
               "The knowledge base knows #{known.join(", ")}, but no relationships involving #{known.size == 1 ? "it" : "them"}."
             else
               lines = facts.first(MAX_FACTS).map do |fact|
                 "#{fact} (strength #{fact.truth_value.strength.round(2)}, confidence #{fact.truth_value.confidence.round(2)})"
               end
               more = facts.size > MAX_FACTS ? "\n... and #{facts.size - MAX_FACTS} more." : ""
               "About #{known.join(", ")}, the knowledge base holds:\n#{lines.join("\n")}#{more}"
             end
      used = facts.first(MAX_FACTS)
      confidence = used.empty? ? 0.0 : used.sum { |fact| fact.truth_value.strength * fact.truth_value.confidence } / used.size
      ModelOutput.new(text, confidence.to_f32, text.split.size.to_u32)
    end

    def describe : String
      "knowledge model over an AtomSpace of #{@atomspace.size} atoms"
    end
  end

  # Loads models, keeps sessions (each with its own conversation history)
  # and runs inference on them.
  class CrystalAIManager
    @default_model : String = ""
    @backends = {} of String => ModelBackend
    @configs = {} of String => ModelConfig
    @sessions : Hash(String, Time) = {} of String => Time
    @histories = {} of String => Array({String, String})
    @total_inferences : Int32 = 0
    getter atomspace : AtomSpace::AtomSpace
    getter last_error : String = ""

    # Session turns kept as context for the next request.
    HISTORY_TURNS = 16

    def initialize(@atomspace : AtomSpace::AtomSpace = AtomSpace::AtomSpace.new)
    end

    # Load a model. Returns false, with the reason in `last_error`, when
    # nothing can serve it.
    def load_model(model_name : String, config : ModelConfig) : Bool
      backend = build_backend(config)
      unless backend
        CogUtil::Logger.error("Cannot load AI model #{model_name}: #{@last_error}")
        return false
      end
      @backends[model_name] = backend
      @configs[model_name] = config
      CogUtil::Logger.info("AI model #{model_name} loaded: #{backend.describe}")
      true
    end

    private def build_backend(config : ModelConfig) : ModelBackend?
      path = config.model_path
      if path.starts_with?("http://") || path.starts_with?("https://")
        return EngineBackend.new(CrystalCog::CogChat::RemoteEngine.new(path, config.custom_params["model"]?))
      end

      model_dir = begin
        AphroditeJax.resolve_model_dir(path)
      rescue ArgumentError
        nil
      end
      if model_dir && File.exists?(File.join(model_dir, "config.json"))
        generator = AphroditeJax::Generator.load(model_dir, config.context_length.to_i32)
        return EngineBackend.new(CrystalCog::CogChat::LocalEngine.new(generator, path))
      end

      return KnowledgeBackend.new(@atomspace) if config.type.custom?

      @last_error = "#{path} is not a server URL or a Qwen3 model directory (only ModelType::CUSTOM falls back to the knowledge model)"
      nil
    rescue ex
      @last_error = ex.message || ex.class.name
      nil
    end

    def unload_model(model_name : String) : Bool
      @configs.delete(model_name)
      @default_model = "" if @default_model == model_name
      !@backends.delete(model_name).nil?
    end

    def is_model_loaded?(model_name : String) : Bool
      @backends.has_key?(model_name)
    end

    def list_models : Array(String)
      @backends.keys
    end

    def describe_model(model_name : String) : String?
      @backends[model_name]?.try(&.describe)
    end

    def set_default_model(model_name : String)
      if is_model_loaded?(model_name)
        @default_model = model_name
      else
        raise "Model #{model_name} is not loaded"
      end
    end

    def get_default_model : String
      @default_model
    end

    def create_session(session_id : String)
      @sessions[session_id] = Time.utc
      @histories[session_id] = [] of {String, String}
    end

    def destroy_session(session_id : String)
      @sessions.delete(session_id)
      @histories.delete(session_id)
    end

    def has_session?(session_id : String) : Bool
      @sessions.has_key?(session_id)
    end

    def list_sessions : Array(String)
      @sessions.keys
    end

    # The session's conversation so far, as {role, text} turns.
    def session_history(session_id : String) : Array({String, String})
      @histories[session_id]? || [] of {String, String}
    end

    def infer(model_name : String, request : InferenceRequest) : InferenceResponse
      backend = @backends[model_name]?
      unless backend
        response = InferenceResponse.new("", request.session_id, success: false)
        response.error_message = "Model #{model_name} is not loaded"
        return response
      end

      create_session(request.session_id) unless has_session?(request.session_id)
      history = @histories[request.session_id]

      start_time = Time.monotonic
      output = begin
        backend.generate(request, @configs[model_name], history)
      rescue ex
        response = InferenceResponse.new("", request.session_id, success: false)
        response.error_message = "Inference failed: #{ex.message}"
        return response
      end
      @total_inferences += 1
      history << {"user", request.prompt} << {"assistant", output.text}
      history.shift(history.size - HISTORY_TURNS) if history.size > HISTORY_TURNS

      response = InferenceResponse.new(output.text, request.session_id, success: true)
      response.tokens_generated = output.tokens
      response.confidence_score = output.confidence
      response.inference_time_ms = (Time.monotonic - start_time).total_milliseconds.to_u64
      response
    end

    def infer_simple(model_name : String, prompt : String, session_id : String) : InferenceResponse
      request = InferenceRequest.new(prompt, session_id)
      infer(model_name, request)
    end

    def batch_infer(model_name : String, requests : Array(InferenceRequest)) : Array(InferenceResponse)
      requests.map { |request| infer(model_name, request) }
    end

    def get_stats : Hash(String, Int32)
      {
        "loaded_models"    => @backends.size,
        "active_sessions"  => @sessions.size,
        "total_inferences" => @total_inferences,
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
      # The knowledge model answers from this same AtomSpace.
      @ai_manager = CrystalAIManager.new(@atomspace)
    end

    getter ai_manager : CrystalAIManager

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
      ai_response = @ai_manager.infer_simple(@ai_manager.get_default_model,
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
      synthesis_response = @ai_manager.infer_simple(@ai_manager.get_default_model, synthesis_prompt, "synthesis_session")
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
      enrichment_model = @ai_manager.is_model_loaded?("reasoning_model") ? "reasoning_model" : @ai_manager.get_default_model
      ai_response = @ai_manager.infer_simple(enrichment_model, ai_prompt, "enrichment_session")
      enrichments << "AI Insight: #{ai_response.text}"

      # Add concept to AtomSpace if not exists
      concept_node = @atomspace.add_concept_node(concept)
      enrichments << "Added concept to AtomSpace: #{concept}"

      # Use PLN to find related concepts
      if pln = @pln_engine
        derived = pln.forward_chain(AtomSpace::AtomType::INHERITANCE_LINK, 2)
        related = concept_relations(concept_node)
        enrichments << "PLN analysis: #{derived.size} new inference(s); #{related.size} relationship(s) involve #{concept}"
        related.first(5).each { |rel| enrichments << "  PLN: #{rel}" }
      end

      # Use URE to derive properties
      if ure = @ure_engine
        derived = ure.forward_chain(3)
        touching = derived.select { |atom| mentions?(atom, concept_node) }
        enrichments << "URE analysis: #{derived.size} derivation(s), #{touching.size} about #{concept}"
        touching.first(5).each { |atom| enrichments << "  URE: #{atom}" }
      end

      enrichments
    end

    # Links that have `concept` anywhere in their outgoing tree, with their truth values.
    private def concept_relations(concept : AtomSpace::Atom) : Array(String)
      @atomspace.get_incoming(concept).map do |link|
        "#{link} (s=#{link.truth_value.strength.round(3)}, c=#{link.truth_value.confidence.round(3)})"
      end
    end

    private def mentions?(atom : AtomSpace::Atom, target : AtomSpace::Atom, depth : Int32 = 0) : Bool
      return true if atom.handle == target.handle
      return false if depth > 16 || !atom.link?
      atom.outgoing.any? { |child| mentions?(child, target, depth + 1) }
    end

    def interactive_reasoning_session(user_input : String) : String
      unless @integration_active
        return "AI integration not active. Please setup workbench first."
      end

      # Create comprehensive reasoning response
      responses = [] of String

      # AI understanding
      ai_response = @ai_manager.infer_simple(@ai_manager.get_default_model, user_input, "interactive_session")
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
