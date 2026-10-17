# Pygmalion Agent - Integration with Pygmalion AI / Aphrodite Engine
#
# This module provides comprehensive integration with Pygmalion AI and
# Aphrodite Engine for advanced conversational AI capabilities with
# deep cognitive architecture support.
#
# Features:
# - OpenAI-compatible API support
# - Full sampling parameter control (temperature, top_k, top_p, etc.)
# - Mirostat adaptive sampling
# - DRY/XTC anti-repetition samplers
# - LoRA adapter support
# - Guided decoding (JSON schema/regex)
# - Banned strings filtering (anti-slop)
# - Streaming responses
# - Token counting and context management
# - Character/persona formatting
# - Multimodal support (vision/images)
# - Tool/function calling
# - Speculative decoding
# - Embeddings API
# - Tokenization API
# - Prompt caching
# - Request priority scheduling

require "http/client"
require "json"
require "uri"
require "base64"
require "../cogutil/logger"
require "../atomspace/atomspace"

module PygmalionAgent
  VERSION = "0.3.0"

  # ==========================================================================
  # Sampling Configuration
  # ==========================================================================

  # Comprehensive sampling parameters matching Aphrodite Engine
  class SamplingConfig
    # Basic sampling
    property temperature : Float64
    property top_k : Int32
    property top_p : Float64
    property top_a : Float64
    property min_p : Float64
    property typical_p : Float64
    property tfs : Float64 # Tail-free sampling

    # Penalty controls
    property presence_penalty : Float64
    property frequency_penalty : Float64
    property repetition_penalty : Float64
    property repetition_penalty_range : Int32

    # Mirostat adaptive sampling
    property mirostat_mode : Int32 # 0=disabled, 2=Mirostat 2
    property mirostat_tau : Float64
    property mirostat_eta : Float64

    # DRY (Don't Repeat Yourself) sampler
    property dry_multiplier : Float64
    property dry_base : Float64
    property dry_allowed_length : Int32
    property dry_sequence_breakers : Array(String)

    # XTC (eXtreme Token Culling) sampler
    property xtc_threshold : Float64
    property xtc_probability : Float64

    # Dynamic temperature
    property dynatemp_enabled : Bool
    property dynatemp_min : Float64
    property dynatemp_max : Float64
    property dynatemp_exponent : Float64

    # Smoothing
    property smoothing_factor : Float64
    property smoothing_curve : Float64

    # Additional parameters (NEW)
    property seed : Int64?                        # Reproducibility seed
    property best_of : Int32                      # Beam search / best_of
    property length_penalty : Float64             # Length penalty for beam search
    property early_stopping : Bool                # Early stopping for beam search
    property skip_special_tokens : Bool           # Skip special tokens in output
    property spaces_between_special_tokens : Bool # Add spaces between special tokens
    property include_stop_str_in_output : Bool    # Include stop string in output
    property ignore_eos : Bool                    # Ignore end-of-sequence token
    property logit_bias : Hash(Int32, Float64)    # Token ID -> bias

    # NSFW/Content filtering
    property nsfw_allowed : Bool
    property profanity_filter : Bool

    def initialize(
      @temperature = 0.7,
      @top_k = 40,
      @top_p = 0.95,
      @top_a = 0.0,
      @min_p = 0.05,
      @typical_p = 1.0,
      @tfs = 1.0,
      @presence_penalty = 0.0,
      @frequency_penalty = 0.0,
      @repetition_penalty = 1.0,
      @repetition_penalty_range = 1024,
      @mirostat_mode = 0,
      @mirostat_tau = 5.0,
      @mirostat_eta = 0.1,
      @dry_multiplier = 0.0,
      @dry_base = 1.75,
      @dry_allowed_length = 2,
      @dry_sequence_breakers = ["\n", ":", "\"", "*"] of String,
      @xtc_threshold = 0.1,
      @xtc_probability = 0.0,
      @dynatemp_enabled = false,
      @dynatemp_min = 0.5,
      @dynatemp_max = 1.5,
      @dynatemp_exponent = 1.0,
      @smoothing_factor = 0.0,
      @smoothing_curve = 1.0,
      @seed = nil,
      @best_of = 1,
      @length_penalty = 1.0,
      @early_stopping = false,
      @skip_special_tokens = true,
      @spaces_between_special_tokens = true,
      @include_stop_str_in_output = false,
      @ignore_eos = false,
      @logit_bias = {} of Int32 => Float64,
      @nsfw_allowed = true,
      @profanity_filter = false
    )
    end

    # Preset: Creative writing
    def self.creative : SamplingConfig
      new(
        temperature: 1.0,
        top_k: 100,
        top_p: 0.95,
        min_p: 0.02,
        repetition_penalty: 1.15,
        dry_multiplier: 0.8
      )
    end

    # Preset: Precise/factual
    def self.precise : SamplingConfig
      new(
        temperature: 0.3,
        top_k: 20,
        top_p: 0.85,
        min_p: 0.1,
        repetition_penalty: 1.05
      )
    end

    # Preset: Roleplay optimized
    def self.roleplay : SamplingConfig
      new(
        temperature: 0.85,
        top_k: 60,
        top_p: 0.92,
        min_p: 0.05,
        repetition_penalty: 1.18,
        dry_multiplier: 0.5,
        xtc_probability: 0.1,
        xtc_threshold: 0.15
      )
    end

    # Preset: Mirostat adaptive
    def self.mirostat : SamplingConfig
      new(
        mirostat_mode: 2,
        mirostat_tau: 5.0,
        mirostat_eta: 0.1,
        temperature: 1.0
      )
    end

    # Preset: Deterministic (for testing)
    def self.deterministic(seed : Int64 = 42) : SamplingConfig
      new(
        temperature: 0.0,
        top_k: 1,
        seed: seed
      )
    end

    # Preset: Beam search
    def self.beam_search(num_beams : Int32 = 4) : SamplingConfig
      new(
        temperature: 0.0,
        best_of: num_beams,
        length_penalty: 1.0,
        early_stopping: true
      )
    end

    def to_api_params : Hash(String, JSON::Any)
      params = {} of String => JSON::Any

      params["temperature"] = JSON::Any.new(@temperature)
      params["top_k"] = JSON::Any.new(@top_k.to_i64)
      params["top_p"] = JSON::Any.new(@top_p)
      params["top_a"] = JSON::Any.new(@top_a)
      params["min_p"] = JSON::Any.new(@min_p)
      params["typical_p"] = JSON::Any.new(@typical_p)
      params["tfs"] = JSON::Any.new(@tfs)

      params["presence_penalty"] = JSON::Any.new(@presence_penalty)
      params["frequency_penalty"] = JSON::Any.new(@frequency_penalty)
      params["repetition_penalty"] = JSON::Any.new(@repetition_penalty)

      if @mirostat_mode > 0
        params["mirostat_mode"] = JSON::Any.new(@mirostat_mode.to_i64)
        params["mirostat_tau"] = JSON::Any.new(@mirostat_tau)
        params["mirostat_eta"] = JSON::Any.new(@mirostat_eta)
      end

      if @dry_multiplier > 0
        params["dry_multiplier"] = JSON::Any.new(@dry_multiplier)
        params["dry_base"] = JSON::Any.new(@dry_base)
        params["dry_allowed_length"] = JSON::Any.new(@dry_allowed_length.to_i64)
        params["dry_sequence_breakers"] = JSON::Any.new(@dry_sequence_breakers.map { |s| JSON::Any.new(s) })
      end

      if @xtc_probability > 0
        params["xtc_threshold"] = JSON::Any.new(@xtc_threshold)
        params["xtc_probability"] = JSON::Any.new(@xtc_probability)
      end

      if @dynatemp_enabled
        params["dynatemp_min"] = JSON::Any.new(@dynatemp_min)
        params["dynatemp_max"] = JSON::Any.new(@dynatemp_max)
        params["dynatemp_exponent"] = JSON::Any.new(@dynatemp_exponent)
      end

      # Additional parameters
      if s = @seed
        params["seed"] = JSON::Any.new(s)
      end

      if @best_of > 1
        params["best_of"] = JSON::Any.new(@best_of.to_i64)
        params["length_penalty"] = JSON::Any.new(@length_penalty)
        params["early_stopping"] = JSON::Any.new(@early_stopping)
      end

      params["skip_special_tokens"] = JSON::Any.new(@skip_special_tokens)
      params["spaces_between_special_tokens"] = JSON::Any.new(@spaces_between_special_tokens)
      params["include_stop_str_in_output"] = JSON::Any.new(@include_stop_str_in_output)

      if @ignore_eos
        params["ignore_eos"] = JSON::Any.new(true)
      end

      unless @logit_bias.empty?
        bias_obj = {} of String => JSON::Any
        @logit_bias.each { |k, v| bias_obj[k.to_s] = JSON::Any.new(v) }
        params["logit_bias"] = JSON::Any.new(bias_obj)
      end

      params
    end
  end

  # ==========================================================================
  # API Configuration
  # ==========================================================================

  # API connection and authentication settings
  class APIConfig
    property base_url : String
    property api_key : String?
    property timeout : Time::Span
    property max_retries : Int32
    property retry_delay : Time::Span
    property verify_ssl : Bool
    property api_type : APIType

    # Rate limiting
    property requests_per_minute : Int32?
    property tokens_per_minute : Int32?

    enum APIType
      OpenAI    # OpenAI-compatible API (default)
      KoboldAI  # KoboldAI API format
      Aphrodite # Native Aphrodite extensions
    end

    def initialize(
      @base_url = "http://localhost:2242",
      @api_key = nil,
      @timeout = 120.seconds,
      @max_retries = 3,
      @retry_delay = 1.second,
      @verify_ssl = true,
      @api_type = APIType::OpenAI,
      @requests_per_minute = nil,
      @tokens_per_minute = nil
    )
    end

    def headers : HTTP::Headers
      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      headers["Accept"] = "application/json"
      if key = @api_key
        headers["Authorization"] = "Bearer #{key}"
      end
      headers
    end

    # Endpoint URLs
    def chat_completions_endpoint : String
      case @api_type
      when .open_ai?, .aphrodite?
        "#{@base_url}/v1/chat/completions"
      when .kobold_ai?
        "#{@base_url}/api/v1/generate"
      else
        "#{@base_url}/v1/chat/completions"
      end
    end

    def completions_endpoint : String
      "#{@base_url}/v1/completions"
    end

    def models_endpoint : String
      "#{@base_url}/v1/models"
    end

    def lora_endpoint : String
      "#{@base_url}/v1/lora"
    end

    def embeddings_endpoint : String
      "#{@base_url}/v1/embeddings"
    end

    def tokenize_endpoint : String
      "#{@base_url}/v1/tokenize"
    end

    def detokenize_endpoint : String
      "#{@base_url}/v1/detokenize"
    end

    def health_endpoint : String
      "#{@base_url}/health"
    end

    def version_endpoint : String
      "#{@base_url}/version"
    end

    # Legacy alias
    def completions_endpoint_legacy : String
      chat_completions_endpoint
    end
  end

  # ==========================================================================
  # Multimodal Support (NEW)
  # ==========================================================================

  # Image content for multimodal models
  class ImageContent
    property type : ImageType
    property data : String # Base64 or URL
    property detail : ImageDetail

    enum ImageType
      Base64
      URL
    end

    enum ImageDetail
      Auto
      Low
      High
    end

    def initialize(@type : ImageType, @data : String, @detail : ImageDetail = ImageDetail::Auto)
    end

    # Create from file path
    def self.from_file(path : String, detail : ImageDetail = ImageDetail::Auto) : ImageContent
      content = File.read(path)
      encoded = Base64.strict_encode(content)
      mime_type = detect_mime_type(path)
      new(ImageType::Base64, "data:#{mime_type};base64,#{encoded}", detail)
    end

    # Create from URL
    def self.from_url(url : String, detail : ImageDetail = ImageDetail::Auto) : ImageContent
      new(ImageType::URL, url, detail)
    end

    # Create from raw bytes
    def self.from_bytes(bytes : Bytes, mime_type : String = "image/png", detail : ImageDetail = ImageDetail::Auto) : ImageContent
      encoded = Base64.strict_encode(bytes)
      new(ImageType::Base64, "data:#{mime_type};base64,#{encoded}", detail)
    end

    private def self.detect_mime_type(path : String) : String
      ext = File.extname(path).downcase
      case ext
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".png"          then "image/png"
      when ".gif"          then "image/gif"
      when ".webp"         then "image/webp"
      when ".bmp"          then "image/bmp"
      else                      "image/png"
      end
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "type", "image_url"
        json.field "image_url" do
          json.object do
            json.field "url", @data
            json.field "detail", @detail.to_s.downcase
          end
        end
      end
    end
  end

  # Multimodal message content (text + images)
  class MultimodalContent
    property parts : Array(ContentPart)

    def initialize
      @parts = [] of ContentPart
    end

    def add_text(text : String)
      @parts << ContentPart.new(:text, text)
    end

    def add_image(image : ImageContent)
      @parts << ContentPart.new(:image, image)
    end

    def add_image_url(url : String, detail : ImageContent::ImageDetail = ImageContent::ImageDetail::Auto)
      @parts << ContentPart.new(:image, ImageContent.from_url(url, detail))
    end

    def add_image_file(path : String, detail : ImageContent::ImageDetail = ImageContent::ImageDetail::Auto)
      @parts << ContentPart.new(:image, ImageContent.from_file(path, detail))
    end

    def to_json(json : JSON::Builder)
      json.array do
        @parts.each do |part|
          case part.type
          when :text
            json.object do
              json.field "type", "text"
              json.field "text", part.text_content.not_nil!
            end
          when :image
            part.image_content.not_nil!.to_json(json)
          end
        end
      end
    end
  end

  struct ContentPart
    property type : Symbol
    property text_content : String?
    property image_content : ImageContent?

    def initialize(@type : Symbol, content : String | ImageContent)
      case content
      when String
        @text_content = content
        @image_content = nil
      when ImageContent
        @text_content = nil
        @image_content = content
      end
    end
  end

  # ==========================================================================
  # Tool/Function Calling (NEW)
  # ==========================================================================

  # Function/Tool definition
  class ToolDefinition
    property name : String
    property description : String
    property parameters : ToolParameters
    property strict : Bool

    def initialize(
      @name : String,
      @description : String,
      @parameters : ToolParameters = ToolParameters.new,
      @strict : Bool = false
    )
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "type", "function"
        json.field "function" do
          json.object do
            json.field "name", @name
            json.field "description", @description
            json.field "strict", @strict
            json.field "parameters" do
              @parameters.to_json(json)
            end
          end
        end
      end
    end
  end

  # Tool parameters (JSON Schema)
  class ToolParameters
    property type : String
    property properties : Hash(String, ParameterProperty)
    property required : Array(String)
    property additional_properties : Bool

    def initialize(
      @type : String = "object",
      @properties : Hash(String, ParameterProperty) = {} of String => ParameterProperty,
      @required : Array(String) = [] of String,
      @additional_properties : Bool = false
    )
    end

    def add_property(name : String, prop : ParameterProperty, required : Bool = false)
      @properties[name] = prop
      @required << name if required && !@required.includes?(name)
    end

    def add_string(name : String, description : String, required : Bool = false, enum_values : Array(String)? = nil)
      add_property(name, ParameterProperty.string(description, enum_values), required)
    end

    def add_number(name : String, description : String, required : Bool = false)
      add_property(name, ParameterProperty.number(description), required)
    end

    def add_integer(name : String, description : String, required : Bool = false)
      add_property(name, ParameterProperty.integer(description), required)
    end

    def add_boolean(name : String, description : String, required : Bool = false)
      add_property(name, ParameterProperty.boolean(description), required)
    end

    def add_array(name : String, description : String, item_type : String, required : Bool = false)
      add_property(name, ParameterProperty.array(description, item_type), required)
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "type", @type
        json.field "properties" do
          json.object do
            @properties.each do |name, prop|
              json.field name do
                prop.to_json(json)
              end
            end
          end
        end
        unless @required.empty?
          json.field "required" do
            json.array do
              @required.each { |r| json.string(r) }
            end
          end
        end
        json.field "additionalProperties", @additional_properties
      end
    end
  end

  struct ParameterProperty
    property type : String
    property description : String
    property enum_values : Array(String)?
    property items : Hash(String, String)?

    def initialize(@type, @description, @enum_values = nil, @items = nil)
    end

    def self.string(description : String, enum_values : Array(String)? = nil) : ParameterProperty
      new("string", description, enum_values)
    end

    def self.number(description : String) : ParameterProperty
      new("number", description)
    end

    def self.integer(description : String) : ParameterProperty
      new("integer", description)
    end

    def self.boolean(description : String) : ParameterProperty
      new("boolean", description)
    end

    def self.array(description : String, item_type : String) : ParameterProperty
      new("array", description, items: {"type" => item_type})
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "type", @type
        json.field "description", @description
        if ev = @enum_values
          json.field "enum" do
            json.array { ev.each { |v| json.string(v) } }
          end
        end
        if it = @items
          json.field "items" do
            json.object do
              it.each { |k, v| json.field k, v }
            end
          end
        end
      end
    end
  end

  # Tool call from model response
  struct ToolCall
    property id : String
    property type : String
    property function_name : String
    property function_arguments : String

    def initialize(@id, @type, @function_name, @function_arguments)
    end

    def self.from_json(json : JSON::Any) : ToolCall
      func = json["function"]
      new(
        json["id"].as_s,
        json["type"]?.try(&.as_s) || "function",
        func["name"].as_s,
        func["arguments"].as_s
      )
    end

    def parsed_arguments : JSON::Any
      JSON.parse(@function_arguments)
    end
  end

  # Tool choice configuration
  class ToolChoice
    property mode : ToolChoiceMode
    property function_name : String?

    enum ToolChoiceMode
      Auto     # Let model decide
      None     # Don't use tools
      Required # Must use a tool
      Specific # Use specific tool
    end

    def initialize(@mode : ToolChoiceMode = ToolChoiceMode::Auto, @function_name : String? = nil)
    end

    def self.auto : ToolChoice
      new(ToolChoiceMode::Auto)
    end

    def self.none : ToolChoice
      new(ToolChoiceMode::None)
    end

    def self.required : ToolChoice
      new(ToolChoiceMode::Required)
    end

    def self.function(name : String) : ToolChoice
      new(ToolChoiceMode::Specific, name)
    end

    def to_json_value : JSON::Any
      case @mode
      when .auto?
        JSON::Any.new("auto")
      when .none?
        JSON::Any.new("none")
      when .required?
        JSON::Any.new("required")
      when .specific?
        obj = {} of String => JSON::Any
        obj["type"] = JSON::Any.new("function")
        func = {} of String => JSON::Any
        func["name"] = JSON::Any.new(@function_name.not_nil!)
        obj["function"] = JSON::Any.new(func)
        JSON::Any.new(obj)
      else
        JSON::Any.new("auto")
      end
    end
  end

  # Tool configuration
  class ToolConfig
    property tools : Array(ToolDefinition)
    property tool_choice : ToolChoice
    property parallel_tool_calls : Bool

    def initialize(
      @tools = [] of ToolDefinition,
      @tool_choice = ToolChoice.auto,
      @parallel_tool_calls = true
    )
    end

    def add_tool(tool : ToolDefinition)
      @tools << tool
    end

    def add_function(name : String, description : String, &block : ToolParameters -> Nil)
      params = ToolParameters.new
      yield params
      @tools << ToolDefinition.new(name, description, params)
    end

    def enabled? : Bool
      !@tools.empty?
    end
  end

  # ==========================================================================
  # Speculative Decoding (NEW)
  # ==========================================================================

  # Speculative decoding configuration
  class SpeculativeDecodingConfig
    property enabled : Bool
    property draft_model : String?
    property num_speculative_tokens : Int32
    property draft_model_quantization : String?
    property speculative_disable_by_batch_size : Int32?
    property ngram_prompt_lookup_max : Int32?
    property ngram_prompt_lookup_min : Int32?

    def initialize(
      @enabled = false,
      @draft_model = nil,
      @num_speculative_tokens = 5,
      @draft_model_quantization = nil,
      @speculative_disable_by_batch_size = nil,
      @ngram_prompt_lookup_max = nil,
      @ngram_prompt_lookup_min = nil
    )
    end

    # Enable with draft model
    def self.with_draft_model(draft_model : String, num_tokens : Int32 = 5) : SpeculativeDecodingConfig
      new(
        enabled: true,
        draft_model: draft_model,
        num_speculative_tokens: num_tokens
      )
    end

    # Enable with n-gram lookup
    def self.ngram_lookup(max : Int32 = 4, min : Int32 = 1) : SpeculativeDecodingConfig
      new(
        enabled: true,
        ngram_prompt_lookup_max: max,
        ngram_prompt_lookup_min: min
      )
    end
  end

  # ==========================================================================
  # Caching Configuration (NEW)
  # ==========================================================================

  # Prompt/Prefix caching configuration
  class CachingConfig
    property enable_prefix_caching : Bool
    property enable_chunked_prefill : Bool
    property max_num_batched_tokens : Int32?
    property max_num_seqs : Int32?

    def initialize(
      @enable_prefix_caching = false,
      @enable_chunked_prefill = false,
      @max_num_batched_tokens = nil,
      @max_num_seqs = nil
    )
    end

    def self.enabled : CachingConfig
      new(enable_prefix_caching: true, enable_chunked_prefill: true)
    end
  end

  # ==========================================================================
  # Request Priority (NEW)
  # ==========================================================================

  # Request priority for scheduling
  enum RequestPriority
    Low      = 0
    Normal   = 1
    High     = 2
    Critical = 3

    def to_api_value : Int32
      self.value
    end
  end

  # ==========================================================================
  # LoRA Configuration
  # ==========================================================================

  # LoRA adapter configuration
  class LoRAConfig
    property enabled : Bool
    property adapters : Array(LoRAAdapter)
    property max_loras : Int32
    property max_lora_rank : Int32
    property lora_extra_vocab_size : Int32
    property max_cpu_loras : Int32?

    def initialize(
      @enabled = false,
      @adapters = [] of LoRAAdapter,
      @max_loras = 4,
      @max_lora_rank = 64,
      @lora_extra_vocab_size = 256,
      @max_cpu_loras = nil
    )
    end

    def add_adapter(name : String, path : String, scale : Float64 = 1.0)
      @adapters << LoRAAdapter.new(name, path, scale)
      @enabled = true
    end

    def remove_adapter(name : String)
      @adapters.reject! { |a| a.name == name }
      @enabled = !@adapters.empty?
    end
  end

  struct LoRAAdapter
    property name : String
    property path : String
    property scale : Float64

    def initialize(@name, @path, @scale = 1.0)
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "name", @name
        json.field "path", @path
        json.field "scale", @scale
      end
    end
  end

  # ==========================================================================
  # Guided Decoding Configuration
  # ==========================================================================

  # Guided decoding for structured output
  class GuidedDecodingConfig
    property enabled : Bool
    property backend : GuidedBackend
    property json_schema : String?
    property regex_pattern : String?
    property grammar : String?
    property choice : Array(String)?

    enum GuidedBackend
      Outlines         # Default, uses outlines library
      LMFormatEnforcer # Alternative backend
    end

    def initialize(
      @enabled = false,
      @backend = GuidedBackend::Outlines,
      @json_schema = nil,
      @regex_pattern = nil,
      @grammar = nil,
      @choice = nil
    )
    end

    # Create config for JSON schema enforcement
    def self.json(schema : String) : GuidedDecodingConfig
      config = new(enabled: true)
      config.json_schema = schema
      config
    end

    # Create config for regex pattern enforcement
    def self.regex(pattern : String) : GuidedDecodingConfig
      config = new(enabled: true)
      config.regex_pattern = pattern
      config
    end

    # Create config for choice selection
    def self.choice(options : Array(String)) : GuidedDecodingConfig
      config = new(enabled: true)
      config.choice = options
      config
    end

    def to_api_params : Hash(String, JSON::Any)?
      return nil unless @enabled

      params = {} of String => JSON::Any
      params["guided_decoding_backend"] = JSON::Any.new(@backend.to_s.underscore)

      if schema = @json_schema
        params["guided_json"] = JSON::Any.new(schema)
      elsif pattern = @regex_pattern
        params["guided_regex"] = JSON::Any.new(pattern)
      elsif grammar_str = @grammar
        params["guided_grammar"] = JSON::Any.new(grammar_str)
      elsif choices = @choice
        params["guided_choice"] = JSON::Any.new(choices.map { |c| JSON::Any.new(c) })
      end

      params
    end
  end

  # ==========================================================================
  # Banned Strings Configuration (Anti-Slop)
  # ==========================================================================

  # Configuration for phrase/string banning
  class BannedStringsConfig
    property enabled : Bool
    property banned_strings : Array(String)
    property banned_tokens : Array(Int32)
    property case_sensitive : Bool

    # Common "slop" phrases often banned in creative writing
    COMMON_SLOP = [
      "shivers down", "sent shivers", "shiver down my spine",
      "eyes gleaming", "glint in", "couldn't help but",
      "A mix of", "a mixture of", "I couldn't help but notice",
      "the air was thick", "thick with tension",
      "dance of", "danced across", "danced in",
      "sanctuary", "testament to",
      "heart pounding", "heart racing", "pulse quickened",
      "let out a breath", "breath I didn't know",
      "kaleidoscope of", "symphony of", "tapestry of",
      "oh god", "oh my god",
    ]

    def initialize(
      @enabled = false,
      @banned_strings = [] of String,
      @banned_tokens = [] of Int32,
      @case_sensitive = false
    )
    end

    # Enable with common slop phrases
    def self.anti_slop : BannedStringsConfig
      config = new(enabled: true)
      config.banned_strings = COMMON_SLOP.dup
      config
    end

    def add_phrase(phrase : String)
      @banned_strings << phrase unless @banned_strings.includes?(phrase)
      @enabled = true
    end

    def add_phrases(phrases : Array(String))
      phrases.each { |p| add_phrase(p) }
    end

    def remove_phrase(phrase : String)
      @banned_strings.delete(phrase)
      @enabled = !@banned_strings.empty? && !@banned_tokens.empty?
    end

    def to_api_params : Hash(String, JSON::Any)?
      return nil unless @enabled && (!@banned_strings.empty? || !@banned_tokens.empty?)

      params = {} of String => JSON::Any

      unless @banned_strings.empty?
        params["banned_strings"] = JSON::Any.new(@banned_strings.map { |s| JSON::Any.new(s) })
      end

      unless @banned_tokens.empty?
        params["banned_tokens"] = JSON::Any.new(@banned_tokens.map { |t| JSON::Any.new(t.to_i64) })
      end

      params
    end
  end

  # ==========================================================================
  # Character/Persona Configuration
  # ==========================================================================

  # Character card and persona formatting
  class CharacterConfig
    property name : String
    property description : String
    property personality : String
    property scenario : String
    property first_message : String
    property example_dialogue : Array(DialogueExample)
    property system_prompt : String?
    property jailbreak_prompt : String?
    property format : CharacterFormat

    enum CharacterFormat
      Pygmalion # {{char}}, {{user}} format
      OpenAI    # Standard system/user/assistant
      Alpaca    # Instruction format
      ChatML    # <|im_start|> format
      Llama3    # Llama 3 format
    end

    def initialize(
      @name = "Assistant",
      @description = "",
      @personality = "",
      @scenario = "",
      @first_message = "",
      @example_dialogue = [] of DialogueExample,
      @system_prompt = nil,
      @jailbreak_prompt = nil,
      @format = CharacterFormat::Pygmalion
    )
    end

    # Build system prompt from character card
    def build_system_prompt(user_name : String = "User") : String
      parts = [] of String

      if sys = @system_prompt
        parts << sys
      end

      unless @description.empty?
        parts << "Character: #{@name}"
        parts << @description
      end

      unless @personality.empty?
        parts << "Personality: #{@personality}"
      end

      unless @scenario.empty?
        parts << "Scenario: #{@scenario}"
      end

      unless @example_dialogue.empty?
        parts << "Example dialogue:"
        @example_dialogue.each do |example|
          parts << format_dialogue(example, user_name)
        end
      end

      if jb = @jailbreak_prompt
        parts << jb
      end

      result = parts.join("\n\n")

      # Apply format-specific replacements
      case @format
      when .pygmalion?
        result = result.gsub("{{char}}", @name)
        result = result.gsub("{{user}}", user_name)
      end

      result
    end

    private def format_dialogue(example : DialogueExample, user_name : String) : String
      case @format
      when .pygmalion?
        "{{user}}: #{example.user_message}\n{{char}}: #{example.char_message}"
      else
        "#{user_name}: #{example.user_message}\n#{@name}: #{example.char_message}"
      end
    end
  end

  struct DialogueExample
    property user_message : String
    property char_message : String

    def initialize(@user_message, @char_message)
    end
  end

  # ==========================================================================
  # Chat Message (Enhanced with Multimodal + Tools)
  # ==========================================================================

  # Chat message structure (enhanced)
  class ChatMessage
    property role : String
    property content : String | MultimodalContent
    property name : String?
    property tool_calls : Array(ToolCall)?
    property tool_call_id : String?

    def initialize(@role : String, @content : String | MultimodalContent, @name : String? = nil,
                   @tool_calls : Array(ToolCall)? = nil, @tool_call_id : String? = nil)
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "role", @role

        case c = @content
        when String
          json.field "content", c
        when MultimodalContent
          json.field "content" do
            c.to_json(json)
          end
        end

        if n = @name
          json.field "name", n
        end

        if tc = @tool_calls
          json.field "tool_calls" do
            json.array do
              tc.each do |call|
                json.object do
                  json.field "id", call.id
                  json.field "type", call.type
                  json.field "function" do
                    json.object do
                      json.field "name", call.function_name
                      json.field "arguments", call.function_arguments
                    end
                  end
                end
              end
            end
          end
        end

        if tcid = @tool_call_id
          json.field "tool_call_id", tcid
        end
      end
    end

    def self.system(content : String) : ChatMessage
      new("system", content)
    end

    def self.user(content : String, name : String? = nil) : ChatMessage
      new("user", content, name)
    end

    def self.user_multimodal(content : MultimodalContent, name : String? = nil) : ChatMessage
      new("user", content, name)
    end

    def self.assistant(content : String, name : String? = nil) : ChatMessage
      new("assistant", content, name)
    end

    def self.assistant_with_tool_calls(tool_calls : Array(ToolCall)) : ChatMessage
      msg = new("assistant", "")
      msg.tool_calls = tool_calls
      msg
    end

    def self.tool_response(tool_call_id : String, content : String) : ChatMessage
      new("tool", content, tool_call_id: tool_call_id)
    end

    # Get text content (for backward compatibility)
    def text_content : String
      case c = @content
      when String
        c
      when MultimodalContent
        c.parts.select { |p| p.type == :text }.map { |p| p.text_content || "" }.join
      else
        ""
      end
    end
  end

  # ==========================================================================
  # Generation Request (Enhanced)
  # ==========================================================================

  # Generation request (enhanced with all features)
  class GenerationRequest
    property messages : Array(ChatMessage)
    property model : String?
    property max_tokens : Int32
    property stop : Array(String)
    property stream : Bool
    property logprobs : Bool
    property top_logprobs : Int32?
    property n : Int32
    property user : String?
    property echo : Bool # Echo prompt in response

    property sampling : SamplingConfig
    property guided : GuidedDecodingConfig
    property banned : BannedStringsConfig
    property lora_request : LoRAAdapter?
    property tools : ToolConfig
    property priority : RequestPriority

    # Prompt caching
    property use_cache : Bool
    property cache_salt : String?

    def initialize(
      @messages = [] of ChatMessage,
      @model = nil,
      @max_tokens = 512,
      @stop = [] of String,
      @stream = false,
      @logprobs = false,
      @top_logprobs = nil,
      @n = 1,
      @user = nil,
      @echo = false,
      @sampling = SamplingConfig.new,
      @guided = GuidedDecodingConfig.new,
      @banned = BannedStringsConfig.new,
      @lora_request = nil,
      @tools = ToolConfig.new,
      @priority = RequestPriority::Normal,
      @use_cache = true,
      @cache_salt = nil
    )
    end

    def add_message(role : String, content : String)
      @messages << ChatMessage.new(role, content)
    end

    def add_multimodal_message(role : String, content : MultimodalContent)
      @messages << ChatMessage.new(role, content)
    end

    def add_stop(sequence : String)
      @stop << sequence unless @stop.includes?(sequence)
    end

    def add_tool(tool : ToolDefinition)
      @tools.add_tool(tool)
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          # Messages
          json.field "messages" do
            json.array do
              @messages.each { |m| m.to_json(json) }
            end
          end

          # Model
          if m = @model
            json.field "model", m
          end

          # Basic params
          json.field "max_tokens", @max_tokens
          json.field "stream", @stream
          json.field "n", @n

          if @echo
            json.field "echo", true
          end

          # Stop sequences
          unless @stop.empty?
            json.field "stop" do
              json.array do
                @stop.each { |s| json.string(s) }
              end
            end
          end

          # Logprobs
          if @logprobs
            json.field "logprobs", true
            if tlp = @top_logprobs
              json.field "top_logprobs", tlp
            end
          end

          # User ID
          if u = @user
            json.field "user", u
          end

          # Sampling parameters
          @sampling.to_api_params.each do |key, value|
            json.field key, value
          end

          # Guided decoding
          if guided_params = @guided.to_api_params
            guided_params.each do |key, value|
              json.field key, value
            end
          end

          # Banned strings
          if banned_params = @banned.to_api_params
            banned_params.each do |key, value|
              json.field key, value
            end
          end

          # LoRA
          if lora = @lora_request
            json.field "lora_request", lora
          end

          # Tools
          if @tools.enabled?
            json.field "tools" do
              json.array do
                @tools.tools.each { |t| t.to_json(json) }
              end
            end
            json.field "tool_choice", @tools.tool_choice.to_json_value
            json.field "parallel_tool_calls", @tools.parallel_tool_calls
          end

          # Priority
          if @priority != RequestPriority::Normal
            json.field "priority", @priority.to_api_value
          end

          # Caching
          if !@use_cache
            json.field "skip_cache", true
          end
          if salt = @cache_salt
            json.field "cache_salt", salt
          end
        end
      end
    end
  end

  # ==========================================================================
  # Completion Request (Non-Chat) (NEW)
  # ==========================================================================

  # Standard completion request (non-chat)
  class CompletionRequest
    property prompt : String | Array(String)
    property model : String?
    property max_tokens : Int32
    property stop : Array(String)
    property stream : Bool
    property logprobs : Int32?
    property echo : Bool
    property suffix : String?

    property sampling : SamplingConfig

    def initialize(
      @prompt = "",
      @model = nil,
      @max_tokens = 512,
      @stop = [] of String,
      @stream = false,
      @logprobs = nil,
      @echo = false,
      @suffix = nil,
      @sampling = SamplingConfig.new
    )
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          case p = @prompt
          when String
            json.field "prompt", p
          when Array(String)
            json.field "prompt" do
              json.array { p.each { |s| json.string(s) } }
            end
          end

          if m = @model
            json.field "model", m
          end

          json.field "max_tokens", @max_tokens
          json.field "stream", @stream
          json.field "echo", @echo

          unless @stop.empty?
            json.field "stop" do
              json.array { @stop.each { |s| json.string(s) } }
            end
          end

          if lp = @logprobs
            json.field "logprobs", lp
          end

          if suf = @suffix
            json.field "suffix", suf
          end

          @sampling.to_api_params.each do |key, value|
            json.field key, value
          end
        end
      end
    end
  end

  # ==========================================================================
  # Embeddings (NEW)
  # ==========================================================================

  # Embedding request
  class EmbeddingRequest
    property input : String | Array(String)
    property model : String?
    property encoding_format : String # "float" or "base64"

    def initialize(
      @input = "",
      @model = nil,
      @encoding_format = "float"
    )
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          case i = @input
          when String
            json.field "input", i
          when Array(String)
            json.field "input" do
              json.array { i.each { |s| json.string(s) } }
            end
          end

          if m = @model
            json.field "model", m
          end

          json.field "encoding_format", @encoding_format
        end
      end
    end
  end

  # Embedding response
  class EmbeddingResponse
    property embeddings : Array(Array(Float64))
    property model : String
    property usage : TokenUsage

    def initialize(@embeddings = [] of Array(Float64), @model = "", @usage = TokenUsage.new)
    end

    def self.from_json(body : String) : EmbeddingResponse
      json = JSON.parse(body)
      response = new(model: json["model"]?.try(&.as_s) || "")

      if data = json["data"]?
        data.as_a.each do |item|
          if emb = item["embedding"]?
            response.embeddings << emb.as_a.map(&.as_f)
          end
        end
      end

      if usage = json["usage"]?
        response.usage = TokenUsage.from_json(usage)
      end

      response
    end

    # Get first embedding (convenience)
    def embedding : Array(Float64)
      @embeddings.first? || [] of Float64
    end
  end

  # ==========================================================================
  # Tokenization (NEW)
  # ==========================================================================

  # Tokenize request
  class TokenizeRequest
    property text : String
    property model : String?
    property add_special_tokens : Bool

    def initialize(@text = "", @model = nil, @add_special_tokens = true)
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          json.field "text", @text
          if m = @model
            json.field "model", m
          end
          json.field "add_special_tokens", @add_special_tokens
        end
      end
    end
  end

  # Tokenize response
  struct TokenizeResponse
    property tokens : Array(Int32)
    property count : Int32

    def initialize(@tokens = [] of Int32, @count = 0)
    end

    def self.from_json(body : String) : TokenizeResponse
      json = JSON.parse(body)
      tokens = json["tokens"]?.try(&.as_a.map(&.as_i)) || [] of Int32
      count = json["count"]?.try(&.as_i) || tokens.size
      new(tokens, count)
    end
  end

  # Detokenize request
  class DetokenizeRequest
    property tokens : Array(Int32)
    property model : String?

    def initialize(@tokens = [] of Int32, @model = nil)
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          json.field "tokens" do
            json.array { @tokens.each { |t| json.number(t) } }
          end
          if m = @model
            json.field "model", m
          end
        end
      end
    end
  end

  # Detokenize response
  struct DetokenizeResponse
    property text : String

    def initialize(@text = "")
    end

    def self.from_json(body : String) : DetokenizeResponse
      json = JSON.parse(body)
      new(json["text"]?.try(&.as_s) || "")
    end
  end

  # ==========================================================================
  # Response Types
  # ==========================================================================

  # Token usage information
  struct TokenUsage
    property prompt_tokens : Int32
    property completion_tokens : Int32
    property total_tokens : Int32

    def initialize(@prompt_tokens = 0, @completion_tokens = 0, @total_tokens = 0)
    end

    def self.from_json(json : JSON::Any) : TokenUsage
      new(
        json["prompt_tokens"]?.try(&.as_i) || 0,
        json["completion_tokens"]?.try(&.as_i) || 0,
        json["total_tokens"]?.try(&.as_i) || 0
      )
    end
  end

  # Log probability information
  struct LogProb
    property token : String
    property logprob : Float64
    property top_logprobs : Array(Hash(String, Float64))

    def initialize(@token, @logprob, @top_logprobs = [] of Hash(String, Float64))
    end
  end

  # Generation choice (enhanced)
  struct GenerationChoice
    property index : Int32
    property message : ChatMessage
    property finish_reason : String
    property logprobs : Array(LogProb)?

    def initialize(@index, @message, @finish_reason, @logprobs = nil)
    end

    def self.from_json(json : JSON::Any) : GenerationChoice
      message_json = json["message"]

      # Handle tool calls
      tool_calls : Array(ToolCall)? = nil
      if tc_json = message_json["tool_calls"]?
        tool_calls = tc_json.as_a.map { |tc| ToolCall.from_json(tc) }
      end

      message = ChatMessage.new(
        message_json["role"].as_s,
        message_json["content"]?.try(&.as_s) || "",
        message_json["name"]?.try(&.as_s),
        tool_calls
      )

      new(
        json["index"].as_i,
        message,
        json["finish_reason"]?.try(&.as_s) || "stop"
      )
    end

    def has_tool_calls? : Bool
      @message.tool_calls.try(&.size.> 0) || false
    end
  end

  # Generation response
  class GenerationResponse
    property id : String
    property model : String
    property choices : Array(GenerationChoice)
    property usage : TokenUsage
    property created : Int64

    def initialize(
      @id = "",
      @model = "",
      @choices = [] of GenerationChoice,
      @usage = TokenUsage.new,
      @created = Time.utc.to_unix
    )
    end

    def self.from_json(body : String) : GenerationResponse
      json = JSON.parse(body)

      response = new(
        id: json["id"]?.try(&.as_s) || "",
        model: json["model"]?.try(&.as_s) || "",
        created: json["created"]?.try(&.as_i64) || Time.utc.to_unix
      )

      if choices_json = json["choices"]?
        choices_json.as_a.each do |choice_json|
          response.choices << GenerationChoice.from_json(choice_json)
        end
      end

      if usage_json = json["usage"]?
        response.usage = TokenUsage.from_json(usage_json)
      end

      response
    end

    # Get the primary response text
    def text : String
      @choices.first?.try(&.message.text_content) || ""
    end

    # Check if response has tool calls
    def has_tool_calls? : Bool
      @choices.any?(&.has_tool_calls?)
    end

    # Get all tool calls
    def tool_calls : Array(ToolCall)
      @choices.flat_map { |c| c.message.tool_calls || [] of ToolCall }
    end
  end

  # Streaming chunk (enhanced)
  struct StreamChunk
    property id : String
    property delta : String
    property finish_reason : String?
    property tool_calls : Array(ToolCall)?

    def initialize(@id, @delta, @finish_reason = nil, @tool_calls = nil)
    end

    def self.from_sse(line : String) : StreamChunk?
      return nil unless line.starts_with?("data: ")

      data = line[6..]
      return nil if data == "[DONE]"

      begin
        json = JSON.parse(data)
        delta = ""
        finish_reason : String? = nil
        tool_calls : Array(ToolCall)? = nil

        if choices = json["choices"]?
          if first_choice = choices.as_a.first?
            if delta_json = first_choice["delta"]?
              delta = delta_json["content"]?.try(&.as_s) || ""

              if tc = delta_json["tool_calls"]?
                tool_calls = tc.as_a.map { |t| ToolCall.from_json(t) }
              end
            end
            finish_reason = first_choice["finish_reason"]?.try(&.as_s)
          end
        end

        new(
          json["id"]?.try(&.as_s) || "",
          delta,
          finish_reason,
          tool_calls
        )
      rescue
        nil
      end
    end
  end

  # Health check response (NEW)
  struct HealthStatus
    property status : String
    property version : String?
    property model : String?
    property gpu_memory_used : Float64?
    property gpu_memory_total : Float64?

    def initialize(@status = "unknown", @version = nil, @model = nil,
                   @gpu_memory_used = nil, @gpu_memory_total = nil)
    end

    def self.from_json(body : String) : HealthStatus
      json = JSON.parse(body)
      new(
        status: json["status"]?.try(&.as_s) || "unknown",
        version: json["version"]?.try(&.as_s),
        model: json["model"]?.try(&.as_s),
        gpu_memory_used: json["gpu_memory_used"]?.try(&.as_f),
        gpu_memory_total: json["gpu_memory_total"]?.try(&.as_f)
      )
    end

    def healthy? : Bool
      @status == "ok" || @status == "healthy"
    end
  end

  # ==========================================================================
  # HTTP Client with Retry Logic
  # ==========================================================================

  class APIClient
    property config : APIConfig
    @last_request_time : Time?
    @request_count : Int32 = 0

    def initialize(@config : APIConfig)
    end

    # Make a POST request with retry logic
    def post(endpoint : String, body : String) : HTTP::Client::Response
      retries = 0
      last_error : Exception? = nil

      loop do
        begin
          # Rate limiting
          enforce_rate_limit

          uri = URI.parse(endpoint)
          client = HTTP::Client.new(uri)
          client.connect_timeout = @config.timeout
          client.read_timeout = @config.timeout

          response = client.post(
            uri.path || "/",
            headers: @config.headers,
            body: body
          )

          @last_request_time = Time.utc
          @request_count += 1

          # Check for rate limit response
          if response.status_code == 429
            retry_after = response.headers["Retry-After"]?.try(&.to_i) || 60
            CogUtil::Logger.warn("Rate limited, waiting #{retry_after}s")
            sleep(retry_after.seconds)
            retries += 1
            next if retries < @config.max_retries
          end

          return response
        rescue ex : Exception
          last_error = ex
          retries += 1

          if retries < @config.max_retries
            delay = @config.retry_delay * (2 ** (retries - 1)) # Exponential backoff
            CogUtil::Logger.warn("Request failed, retrying in #{delay}: #{ex.message}")
            sleep(delay)
          else
            break
          end
        end
      end

      raise last_error || Exception.new("Request failed after #{@config.max_retries} retries")
    end

    # Stream a POST request
    def post_stream(endpoint : String, body : String, &block : StreamChunk -> Nil)
      uri = URI.parse(endpoint)
      client = HTTP::Client.new(uri)
      client.connect_timeout = @config.timeout
      client.read_timeout = @config.timeout

      enforce_rate_limit

      headers = @config.headers
      headers["Accept"] = "text/event-stream"

      client.post(uri.path || "/", headers: headers, body: body) do |response|
        if response.status_code != 200
          raise Exception.new("Stream request failed: #{response.status_code}")
        end

        response.body_io.each_line do |line|
          line = line.strip
          next if line.empty?

          if chunk = StreamChunk.from_sse(line)
            block.call(chunk)
            break if chunk.finish_reason
          end
        end
      end

      @last_request_time = Time.utc
      @request_count += 1
    end

    # GET request for model list, etc.
    def get(endpoint : String) : HTTP::Client::Response
      uri = URI.parse(endpoint)
      client = HTTP::Client.new(uri)
      client.connect_timeout = @config.timeout

      enforce_rate_limit

      response = client.get(uri.path || "/", headers: @config.headers)
      @last_request_time = Time.utc
      @request_count += 1
      response
    end

    private def enforce_rate_limit
      if rpm = @config.requests_per_minute
        if last = @last_request_time
          min_interval = 60.0 / rpm
          elapsed = (Time.utc - last).total_seconds
          if elapsed < min_interval
            sleep((min_interval - elapsed).seconds)
          end
        end
      end
    end
  end

  # ==========================================================================
  # Token Counter
  # ==========================================================================

  # Simple token estimation (actual tokenization requires model-specific tokenizer)
  class TokenCounter
    # Approximate tokens per character ratio (varies by model)
    CHARS_PER_TOKEN = 4.0

    property model_max_tokens : Int32
    property reserved_tokens : Int32 # For response

    def initialize(@model_max_tokens = 4096, @reserved_tokens = 512)
    end

    # Estimate token count for text
    def estimate(text : String) : Int32
      (text.size / CHARS_PER_TOKEN).ceil.to_i
    end

    # Estimate tokens for messages
    def estimate_messages(messages : Array(ChatMessage)) : Int32
      total = 0
      messages.each do |msg|
        # Account for role/name tokens and message formatting
        total += 4 # Approximate overhead per message
        total += estimate(msg.text_content)
        if name = msg.name
          total += estimate(name) + 1
        end
      end
      total + 2 # Priming tokens
    end

    # Calculate available tokens for generation
    def available_for_generation(messages : Array(ChatMessage)) : Int32
      used = estimate_messages(messages)
      available = @model_max_tokens - used - @reserved_tokens
      available > 0 ? available : 0
    end

    # Truncate messages to fit context
    def truncate_to_fit(messages : Array(ChatMessage), max_tokens : Int32? = nil) : Array(ChatMessage)
      max = max_tokens || (@model_max_tokens - @reserved_tokens)

      # Always keep system message if present
      system_msg = messages.find { |m| m.role == "system" }
      other_msgs = messages.reject { |m| m.role == "system" }

      result = system_msg ? [system_msg] : [] of ChatMessage
      current_tokens = system_msg ? estimate_messages([system_msg]) : 0

      # Add messages from end (most recent first)
      other_msgs.reverse_each do |msg|
        msg_tokens = estimate_messages([msg])
        if current_tokens + msg_tokens <= max
          result.insert(system_msg ? 1 : 0, msg)
          current_tokens += msg_tokens
        else
          break
        end
      end

      result
    end
  end

  # ==========================================================================
  # Echo State Network Configuration (Cognitive Extension)
  # ==========================================================================

  # Echo State Network configuration for cognitive processing
  class EchoStateConfig
    property reservoir_size : Int32
    property spectral_radius : Float64
    property sparsity : Float64
    property input_scaling : Float64
    property leaking_rate : Float64
    property tensor_signatures : Bool
    property cognitive_binding : Bool

    def initialize(
      @reservoir_size = 1000,
      @spectral_radius = 0.95,
      @sparsity = 0.1,
      @input_scaling = 1.0,
      @leaking_rate = 0.3,
      @tensor_signatures = true,
      @cognitive_binding = true
    )
    end
  end

  # ==========================================================================
  # Main Configuration
  # ==========================================================================

  # Main configuration combining all settings
  class Config
    property api : APIConfig
    property sampling : SamplingConfig
    property lora : LoRAConfig
    property guided : GuidedDecodingConfig
    property banned : BannedStringsConfig
    property character : CharacterConfig
    property echo_state : EchoStateConfig
    property token_counter : TokenCounter
    property speculative : SpeculativeDecodingConfig
    property caching : CachingConfig
    property tools : ToolConfig

    property model_name : String
    property max_context_length : Int32
    property default_max_tokens : Int32
    property stream_by_default : Bool

    def initialize(
      @api = APIConfig.new,
      @sampling = SamplingConfig.new,
      @lora = LoRAConfig.new,
      @guided = GuidedDecodingConfig.new,
      @banned = BannedStringsConfig.new,
      @character = CharacterConfig.new,
      @echo_state = EchoStateConfig.new,
      @token_counter = TokenCounter.new,
      @speculative = SpeculativeDecodingConfig.new,
      @caching = CachingConfig.new,
      @tools = ToolConfig.new,
      @model_name = "default",
      @max_context_length = 4096,
      @default_max_tokens = 512,
      @stream_by_default = false
    )
      @token_counter.model_max_tokens = @max_context_length
    end

    # Quick setup for local Aphrodite instance
    def self.aphrodite_local(port : Int32 = 2242, model : String = "default") : Config
      config = new
      config.api.base_url = "http://localhost:#{port}"
      config.api.api_type = APIConfig::APIType::Aphrodite
      config.model_name = model
      config
    end

    # Quick setup for remote API with key
    def self.remote(url : String, api_key : String, model : String) : Config
      config = new
      config.api.base_url = url
      config.api.api_key = api_key
      config.model_name = model
      config
    end

    # Setup for vision/multimodal model
    def self.vision(url : String, model : String = "llava") : Config
      config = new
      config.api.base_url = url
      config.model_name = model
      config.max_context_length = 8192
      config
    end
  end

  # ==========================================================================
  # Main Agent Class (Enhanced)
  # ==========================================================================

  class Agent
    property config : Config
    property atomspace : AtomSpace::AtomSpace?
    property conversation_history : Array(ChatMessage)
    property client : APIClient
    property user_name : String

    @connected : Bool = false
    @available_models : Array(String) = [] of String
    @health_status : HealthStatus?

    def initialize(@config : Config)
      @atomspace = nil
      @conversation_history = [] of ChatMessage
      @client = APIClient.new(@config.api)
      @user_name = "User"
    end

    # Legacy constructor compatibility
    def initialize(config : Config, echo_config : EchoStateConfig)
      @config = config
      @config.echo_state = echo_config
      @atomspace = nil
      @conversation_history = [] of ChatMessage
      @client = APIClient.new(@config.api)
      @user_name = "User"
    end

    # Initialize and test connection
    def initialize_agent : Bool
      CogUtil::Logger.info("Initializing Pygmalion agent with model: #{@config.model_name}")

      begin
        response = @client.get(@config.api.models_endpoint)
        if response.status_code == 200
          json = JSON.parse(response.body)
          if data = json["data"]?
            @available_models = data.as_a.map { |m| m["id"].as_s }
          end
          @connected = true
          CogUtil::Logger.info("Connected to API. Available models: #{@available_models.join(", ")}")
          true
        else
          CogUtil::Logger.warn("Failed to connect to API: #{response.status_code}")
          false
        end
      rescue ex
        CogUtil::Logger.warn("Failed to initialize agent: #{ex.message}")
        false
      end
    end

    # Check if connected
    def connected? : Bool
      @connected
    end

    # Get available models
    def models : Array(String)
      @available_models
    end

    # Health check
    def health : HealthStatus
      begin
        response = @client.get(@config.api.health_endpoint)
        if response.status_code == 200
          @health_status = HealthStatus.from_json(response.body)
        else
          @health_status = HealthStatus.new(status: "error")
        end
      rescue
        @health_status = HealthStatus.new(status: "unreachable")
      end
      @health_status.not_nil!
    end

    # Attach AtomSpace for cognitive-conversational integration
    def attach_atomspace(atomspace : AtomSpace::AtomSpace)
      @atomspace = atomspace
      CogUtil::Logger.info("Attached AtomSpace to Pygmalion agent")
    end

    # Set character/persona
    def set_character(character : CharacterConfig)
      @config.character = character

      # Add system message with character prompt
      system_prompt = character.build_system_prompt(@user_name)
      unless system_prompt.empty?
        # Remove existing system message
        @conversation_history.reject! { |m| m.role == "system" }
        # Add new system message at the beginning
        @conversation_history.unshift(ChatMessage.system(system_prompt))
      end

      # Add first message if present
      unless character.first_message.empty?
        first_msg = character.first_message
          .gsub("{{char}}", character.name)
          .gsub("{{user}}", @user_name)
        @conversation_history << ChatMessage.assistant(first_msg, character.name)
      end
    end

    # Simple chat interface
    def chat(message : String, context : Hash(String, String)? = nil) : String
      request = build_request(message)
      response = generate(request)
      response.text
    end

    # Chat with image (multimodal)
    def chat_with_image(message : String, image_path : String) : String
      content = MultimodalContent.new
      content.add_text(message)
      content.add_image_file(image_path)

      @conversation_history << ChatMessage.user_multimodal(content, @user_name)

      request = GenerationRequest.new(
        messages: @config.token_counter.truncate_to_fit(@conversation_history),
        model: @config.model_name,
        max_tokens: @config.default_max_tokens,
        sampling: @config.sampling
      )

      response = generate(request)
      response.text
    end

    # Chat with image URL
    def chat_with_image_url(message : String, image_url : String) : String
      content = MultimodalContent.new
      content.add_text(message)
      content.add_image_url(image_url)

      @conversation_history << ChatMessage.user_multimodal(content, @user_name)

      request = GenerationRequest.new(
        messages: @config.token_counter.truncate_to_fit(@conversation_history),
        model: @config.model_name,
        max_tokens: @config.default_max_tokens,
        sampling: @config.sampling
      )

      response = generate(request)
      response.text
    end

    # Full chat with streaming callback
    def chat_stream(message : String, &block : String -> Nil) : String
      request = build_request(message)
      request.stream = true
      generate_stream(request, &block)
    end

    # Chat with tools
    def chat_with_tools(message : String, tools : Array(ToolDefinition), &handler : ToolCall -> String) : String
      @conversation_history << ChatMessage.user(message, @user_name)

      request = GenerationRequest.new(
        messages: @config.token_counter.truncate_to_fit(@conversation_history),
        model: @config.model_name,
        max_tokens: @config.default_max_tokens,
        sampling: @config.sampling
      )

      tools.each { |t| request.add_tool(t) }

      response = generate(request)

      # Handle tool calls if present
      if response.has_tool_calls?
        response.tool_calls.each do |call|
          # Add assistant message with tool call
          @conversation_history << ChatMessage.assistant_with_tool_calls([call])

          # Execute tool and get result
          result = handler.call(call)

          # Add tool response
          @conversation_history << ChatMessage.tool_response(call.id, result)
        end

        # Generate final response
        followup_request = GenerationRequest.new(
          messages: @config.token_counter.truncate_to_fit(@conversation_history),
          model: @config.model_name,
          max_tokens: @config.default_max_tokens,
          sampling: @config.sampling
        )
        response = generate(followup_request)
      end

      response.text
    end

    # Build a generation request from a message
    def build_request(message : String) : GenerationRequest
      # Add user message to history
      @conversation_history << ChatMessage.user(message, @user_name)

      # Process with Echo State Networks if enabled
      if @config.echo_state.cognitive_binding
        process_echo_state(message)
      end

      # Truncate history to fit context
      messages = @config.token_counter.truncate_to_fit(@conversation_history)

      request = GenerationRequest.new(
        messages: messages,
        model: @config.model_name,
        max_tokens: @config.default_max_tokens,
        stream: @config.stream_by_default,
        sampling: @config.sampling,
        guided: @config.guided,
        banned: @config.banned,
        tools: @config.tools
      )

      # Add character-specific stop sequences
      if @config.character.name != "Assistant"
        request.add_stop("\n#{@user_name}:")
        request.add_stop("\n#{@config.character.name}:")
      end

      request
    end

    # Execute generation request
    def generate(request : GenerationRequest) : GenerationResponse
      CogUtil::Logger.info("Generating response with #{request.messages.size} messages")

      response = @client.post(@config.api.chat_completions_endpoint, request.to_json)

      if response.status_code != 200
        CogUtil::Logger.error("Generation failed: #{response.status_code} - #{response.body}")
        raise Exception.new("Generation failed: #{response.status_code}")
      end

      gen_response = GenerationResponse.from_json(response.body)

      # Add assistant response to history (only if no tool calls)
      unless gen_response.has_tool_calls?
        if text = gen_response.choices.first?.try(&.message)
          @conversation_history << text
        end
      end

      CogUtil::Logger.info("Generated #{gen_response.usage.completion_tokens} tokens")
      gen_response
    end

    # Execute streaming generation
    def generate_stream(request : GenerationRequest, &block : String -> Nil) : String
      request.stream = true
      full_response = String::Builder.new

      CogUtil::Logger.info("Streaming response with #{request.messages.size} messages")

      @client.post_stream(@config.api.chat_completions_endpoint, request.to_json) do |chunk|
        unless chunk.delta.empty?
          full_response << chunk.delta
          block.call(chunk.delta)
        end
      end

      result = full_response.to_s

      # Add to history
      @conversation_history << ChatMessage.assistant(result, @config.character.name)

      result
    end

    # Standard completion (non-chat)
    def complete(prompt : String, max_tokens : Int32? = nil) : String
      request = CompletionRequest.new(
        prompt: prompt,
        model: @config.model_name,
        max_tokens: max_tokens || @config.default_max_tokens,
        sampling: @config.sampling
      )

      response = @client.post(@config.api.completions_endpoint, request.to_json)

      if response.status_code != 200
        raise Exception.new("Completion failed: #{response.status_code}")
      end

      json = JSON.parse(response.body)
      json["choices"]?.try(&.as_a.first?).try { |c| c["text"]?.try(&.as_s) } || ""
    end

    # Get embeddings
    def embed(text : String) : Array(Float64)
      request = EmbeddingRequest.new(input: text, model: @config.model_name)
      response = @client.post(@config.api.embeddings_endpoint, request.to_json)

      if response.status_code != 200
        raise Exception.new("Embedding failed: #{response.status_code}")
      end

      EmbeddingResponse.from_json(response.body).embedding
    end

    # Get embeddings for multiple texts
    def embed_batch(texts : Array(String)) : Array(Array(Float64))
      request = EmbeddingRequest.new(input: texts, model: @config.model_name)
      response = @client.post(@config.api.embeddings_endpoint, request.to_json)

      if response.status_code != 200
        raise Exception.new("Embedding failed: #{response.status_code}")
      end

      EmbeddingResponse.from_json(response.body).embeddings
    end

    # Tokenize text
    def tokenize(text : String) : TokenizeResponse
      request = TokenizeRequest.new(text: text, model: @config.model_name)
      response = @client.post(@config.api.tokenize_endpoint, request.to_json)

      if response.status_code != 200
        raise Exception.new("Tokenization failed: #{response.status_code}")
      end

      TokenizeResponse.from_json(response.body)
    end

    # Detokenize tokens
    def detokenize(tokens : Array(Int32)) : String
      request = DetokenizeRequest.new(tokens: tokens, model: @config.model_name)
      response = @client.post(@config.api.detokenize_endpoint, request.to_json)

      if response.status_code != 200
        raise Exception.new("Detokenization failed: #{response.status_code}")
      end

      DetokenizeResponse.from_json(response.body).text
    end

    # Count tokens in text (using API)
    def count_tokens(text : String) : Int32
      tokenize(text).count
    end

    # Regenerate last response
    def regenerate : GenerationResponse
      # Remove last assistant message
      if @conversation_history.last?.try(&.role) == "assistant"
        @conversation_history.pop
      end

      # Get last user message
      last_user = @conversation_history.reverse.find { |m| m.role == "user" }
      raise Exception.new("No user message to regenerate from") unless last_user

      request = GenerationRequest.new(
        messages: @config.token_counter.truncate_to_fit(@conversation_history),
        model: @config.model_name,
        max_tokens: @config.default_max_tokens,
        sampling: @config.sampling,
        guided: @config.guided,
        banned: @config.banned
      )

      generate(request)
    end

    # Continue last response
    def continue(max_tokens : Int32? = nil) : GenerationResponse
      request = GenerationRequest.new(
        messages: @config.token_counter.truncate_to_fit(@conversation_history),
        model: @config.model_name,
        max_tokens: max_tokens || @config.default_max_tokens,
        sampling: @config.sampling
      )

      generate(request)
    end

    # Edit a message in history and regenerate
    def edit_and_regenerate(index : Int32, new_content : String) : GenerationResponse
      if index >= 0 && index < @conversation_history.size
        old_msg = @conversation_history[index]
        @conversation_history[index] = ChatMessage.new(old_msg.role, new_content, old_msg.name)

        # Remove all messages after the edited one
        @conversation_history = @conversation_history[0..index]
      end

      regenerate
    end

    # Process message through Echo State Networks
    private def process_echo_state(message : String)
      return unless @config.echo_state.cognitive_binding

      CogUtil::Logger.debug("Processing message through Echo State Networks")

      # Extract cognitive context from AtomSpace if attached
      if atomspace = @atomspace
        context = get_cognitive_context
        unless context.empty?
          CogUtil::Logger.debug("Cognitive context: #{context.size} concepts")
        end
      end
    end

    # Compute tensor signatures for cognitive state
    def compute_tensor_signatures : Hash(String, Array(Float64))
      CogUtil::Logger.debug("Computing tensor signatures")

      # Placeholder for actual tensor computation
      {
        "prime_factors"   => [] of Float64,
        "rooted_trees"    => [] of Float64,
        "gestalt_state"   => [] of Float64,
        "reservoir_state" => [] of Float64,
      }
    end

    # Get conversation context from AtomSpace
    def get_cognitive_context : Array(String)
      return [] of String unless @atomspace

      CogUtil::Logger.debug("Retrieving cognitive context from AtomSpace")
      [] of String
    end

    # Store conversation in AtomSpace
    def store_conversation_in_atomspace : Bool
      return false unless @atomspace

      CogUtil::Logger.info("Storing conversation history in AtomSpace")
      true
    end

    # Get agent status
    def status : Hash(String, String)
      {
        "agent_status"        => @connected ? "connected" : "disconnected",
        "model"               => @config.model_name,
        "api_url"             => @config.api.base_url,
        "api_type"            => @config.api.api_type.to_s,
        "available_models"    => @available_models.join(", "),
        "echo_state_enabled"  => @config.echo_state.cognitive_binding.to_s,
        "conversation_length" => @conversation_history.size.to_s,
        "atomspace_attached"  => (@atomspace.nil? ? "false" : "true"),
        "character"           => @config.character.name,
        "sampling_preset"     => describe_sampling,
        "tools_enabled"       => @config.tools.enabled?.to_s,
        "caching_enabled"     => @config.caching.enable_prefix_caching.to_s,
      }
    end

    private def describe_sampling : String
      s = @config.sampling
      parts = ["T=#{s.temperature}"]
      parts << "top_k=#{s.top_k}" if s.top_k > 0
      parts << "top_p=#{s.top_p}" if s.top_p < 1.0
      parts << "mirostat" if s.mirostat_mode > 0
      parts << "DRY" if s.dry_multiplier > 0
      parts << "XTC" if s.xtc_probability > 0
      parts << "seed=#{s.seed}" if s.seed
      parts.join(", ")
    end

    # Clear conversation history
    def clear_history
      # Keep system message if present
      system_msg = @conversation_history.find { |m| m.role == "system" }
      @conversation_history.clear
      @conversation_history << system_msg if system_msg
      CogUtil::Logger.info("Cleared conversation history")
    end

    # Export conversation
    def export_conversation(format : Symbol = :json) : String
      case format
      when :json
        JSON.build do |json|
          json.object do
            json.field "character", @config.character.name
            json.field "user", @user_name
            json.field "messages" do
              json.array do
                @conversation_history.each { |m| m.to_json(json) }
              end
            end
          end
        end
      when :text
        @conversation_history.map do |m|
          name = m.name || m.role.capitalize
          "#{name}: #{m.text_content}"
        end.join("\n\n")
      else
        raise ArgumentError.new("Unknown format: #{format}")
      end
    end

    # Import conversation
    def import_conversation(json_str : String)
      json = JSON.parse(json_str)

      @conversation_history.clear

      if messages = json["messages"]?
        messages.as_a.each do |msg|
          @conversation_history << ChatMessage.new(
            msg["role"].as_s,
            msg["content"]?.try(&.as_s) || "",
            msg["name"]?.try(&.as_s)
          )
        end
      end

      if user = json["user"]?
        @user_name = user.as_s
      end
    end

    # Getters for backward compatibility
    def echo_config : EchoStateConfig
      @config.echo_state
    end
  end

  # ==========================================================================
  # Factory Methods
  # ==========================================================================

  # Create agent with default configuration
  def self.create_default_agent : Agent
    config = Config.new
    Agent.new(config)
  end

  # Create agent for local Aphrodite instance
  def self.create_aphrodite_agent(port : Int32 = 2242, model : String = "default") : Agent
    config = Config.aphrodite_local(port, model)
    Agent.new(config)
  end

  # Create agent with custom model
  def self.create_agent(model_name : String, api_url : String) : Agent
    config = Config.new
    config.api.base_url = api_url
    config.model_name = model_name
    Agent.new(config)
  end

  # Create agent with API key
  def self.create_authenticated_agent(api_url : String, api_key : String, model : String) : Agent
    config = Config.remote(api_url, api_key, model)
    Agent.new(config)
  end

  # Create roleplay-optimized agent
  def self.create_roleplay_agent(api_url : String, character : CharacterConfig) : Agent
    config = Config.new
    config.api.base_url = api_url
    config.sampling = SamplingConfig.roleplay
    config.character = character
    config.banned = BannedStringsConfig.anti_slop

    agent = Agent.new(config)
    agent.set_character(character)
    agent
  end

  # Create vision/multimodal agent
  def self.create_vision_agent(api_url : String, model : String = "llava") : Agent
    config = Config.vision(api_url, model)
    Agent.new(config)
  end

  # Create tool-enabled agent
  def self.create_tool_agent(api_url : String, model : String, tools : Array(ToolDefinition)) : Agent
    config = Config.new
    config.api.base_url = api_url
    config.model_name = model
    tools.each { |t| config.tools.add_tool(t) }
    Agent.new(config)
  end
end
