# Cognitive Agency Layer - Unified Grip Control for CrystalCog
#
# This module provides a unified cognitive agency layer that coordinates
# grip control across all integration components (Galatea, Paphos, etc.)
# Features:
# - Centralized cognitive state management
# - Distributed grip coordination
# - Attention and focus mechanisms
# - Thought stream processing
# - Agency coherence maintenance

require "json"
require "../cogutil/logger"
require "../atomspace/atomspace"

module CognitiveAgency
  VERSION = "0.1.0"

  # Core agency parameters for optimal cognitive grip
  module Constants
    DEFAULT_GRIP_STRENGTH       =    8
    OPTIMAL_COHERENCE_THRESHOLD = 0.85
    MAX_ATTENTION_FOCUS         =  100
    THOUGHT_STREAM_CAPACITY     =  500
    SYNC_INTERVAL_MS            =  100
    AGENCY_MODES                = [:passive, :active, :autonomous, :coordinated]
  end

  # Unified cognitive state representation
  class CognitiveState
    property awareness : Float64
    property intentionality : Float64
    property coherence : Float64
    property autonomy : Float64
    property focus : Float64
    property grip_factor : Float64
    property timestamp : Time

    def initialize(
      @awareness = 0.8,
      @intentionality = 0.7,
      @coherence = 0.9,
      @autonomy = 0.6,
      @focus = 0.75,
      @grip_factor = 0.8
    )
      @timestamp = Time.utc
    end

    # Calculate overall agency strength
    def agency_strength : Float64
      weights = {
        awareness:      0.2,
        intentionality: 0.25,
        coherence:      0.25,
        autonomy:       0.15,
        focus:          0.15,
      }

      (@awareness * weights[:awareness] +
        @intentionality * weights[:intentionality] +
        @coherence * weights[:coherence] +
        @autonomy * weights[:autonomy] +
        @focus * weights[:focus]) * @grip_factor
    end

    # Check if agency is in optimal state
    def optimal? : Bool
      agency_strength >= Constants::OPTIMAL_COHERENCE_THRESHOLD
    end

    # Serialize to hash
    def to_h : Hash(String, String)
      {
        "awareness"       => @awareness.to_s,
        "intentionality"  => @intentionality.to_s,
        "coherence"       => @coherence.to_s,
        "autonomy"        => @autonomy.to_s,
        "focus"           => @focus.to_s,
        "grip_factor"     => @grip_factor.to_s,
        "agency_strength" => agency_strength.to_s,
        "optimal"         => optimal?.to_s,
        "timestamp"       => @timestamp.to_s,
      }
    end

    # Create from hash
    def self.from_h(h : Hash(String, String)) : CognitiveState
      CognitiveState.new(
        awareness: h["awareness"]?.try(&.to_f64) || 0.8,
        intentionality: h["intentionality"]?.try(&.to_f64) || 0.7,
        coherence: h["coherence"]?.try(&.to_f64) || 0.9,
        autonomy: h["autonomy"]?.try(&.to_f64) || 0.6,
        focus: h["focus"]?.try(&.to_f64) || 0.75,
        grip_factor: h["grip_factor"]?.try(&.to_f64) || 0.8
      )
    end
  end

  # Thought representation for cognitive stream
  class Thought
    property content : String
    property type : String
    property source : String
    property grip_state : Float64
    property attention_weight : Float64
    property timestamp : Time
    property metadata : Hash(String, String)

    def initialize(
      @content : String,
      @type : String = "general",
      @source : String = "internal",
      @grip_state : Float64 = 0.8,
      @attention_weight : Float64 = 0.5
    )
      @timestamp = Time.utc
      @metadata = {} of String => String
    end

    def to_h : Hash(String, String)
      {
        "content"          => @content,
        "type"             => @type,
        "source"           => @source,
        "grip_state"       => @grip_state.to_s,
        "attention_weight" => @attention_weight.to_s,
        "timestamp"        => @timestamp.to_s,
      }
    end
  end

  # Attention mechanism for cognitive focus
  class AttentionMechanism
    property focus_weights : Hash(String, Float64)
    property decay_rate : Float64
    property max_focus_items : Int32
    property attention_history : Array(Hash(String, String))

    def initialize(@decay_rate = 0.95, @max_focus_items = Constants::MAX_ATTENTION_FOCUS)
      @focus_weights = {} of String => Float64
      @attention_history = [] of Hash(String, String)
    end

    # Update attention weights based on input
    def attend(input : String, weight_boost : Float64 = 0.1)
      # Tokenize input
      tokens = input.downcase.split(/\s+/).map { |t| t.gsub(/[^a-z0-9]/, "") }.reject(&.empty?)

      tokens.each do |token|
        if @focus_weights.has_key?(token)
          @focus_weights[token] = [(@focus_weights[token] + weight_boost), 1.0].min
        else
          @focus_weights[token] = 0.5 + weight_boost
        end
      end

      # Record attention event
      @attention_history << {
        "input"     => input[0, 100],
        "tokens"    => tokens.size.to_s,
        "timestamp" => Time.utc.to_s,
      }

      if @attention_history.size > 100
        @attention_history.shift
      end
    end

    # Apply decay to all weights
    def decay
      @focus_weights.each do |k, v|
        @focus_weights[k] = v * @decay_rate
      end

      # Prune very low weights
      @focus_weights.reject! { |_, v| v < 0.05 }

      # Limit to max focus items
      if @focus_weights.size > @max_focus_items
        sorted = @focus_weights.to_a.sort_by { |_, v| -v }
        @focus_weights = Hash(String, Float64).new
        sorted.first(@max_focus_items).each { |k, v| @focus_weights[k] = v }
      end
    end

    # Get top attention focuses
    def top_focuses(n : Int32 = 10) : Array(Tuple(String, Float64))
      @focus_weights.to_a.sort_by { |_, v| -v }.first(n)
    end

    # Calculate attention score for input
    def attention_score(input : String) : Float64
      tokens = input.downcase.split(/\s+/).map { |t| t.gsub(/[^a-z0-9]/, "") }.reject(&.empty?)
      return 0.0 if tokens.empty?

      scores = tokens.map { |t| @focus_weights[t]? || 0.0 }
      scores.sum / tokens.size
    end

    def status : Hash(String, String)
      {
        "focus_count"     => @focus_weights.size.to_s,
        "decay_rate"      => @decay_rate.to_s,
        "max_focus_items" => @max_focus_items.to_s,
        "history_size"    => @attention_history.size.to_s,
      }
    end
  end

  # Thought stream processor
  class ThoughtStream
    property thoughts : Array(Thought)
    property capacity : Int32
    property processing_enabled : Bool

    def initialize(@capacity = Constants::THOUGHT_STREAM_CAPACITY)
      @thoughts = [] of Thought
      @processing_enabled = true
    end

    # Add thought to stream
    def add(thought : Thought)
      @thoughts << thought

      if @thoughts.size > @capacity
        @thoughts.shift
      end
    end

    # Add thought from content
    def add_thought(content : String, type : String = "general", source : String = "internal", grip_state : Float64 = 0.8)
      add(Thought.new(content, type, source, grip_state))
    end

    # Get recent thoughts
    def recent(n : Int32 = 20) : Array(Thought)
      @thoughts.last(n)
    end

    # Get thoughts by type
    def by_type(type : String) : Array(Thought)
      @thoughts.select { |t| t.type == type }
    end

    # Get thoughts by source
    def by_source(source : String) : Array(Thought)
      @thoughts.select { |t| t.source == source }
    end

    # Clear stream
    def clear
      @thoughts.clear
    end

    def status : Hash(String, String)
      type_counts = {} of String => Int32
      @thoughts.each do |t|
        type_counts[t.type] = (type_counts[t.type]? || 0) + 1
      end

      {
        "total_thoughts"     => @thoughts.size.to_s,
        "capacity"           => @capacity.to_s,
        "processing_enabled" => @processing_enabled.to_s,
        "types"              => type_counts.to_json,
      }
    end
  end

  # Grip controller for cognitive agency
  class GripController
    property grip_strength : Int32
    property mode : Symbol
    property auto_adjust : Bool
    property adjustment_sensitivity : Float64

    def initialize(@grip_strength = Constants::DEFAULT_GRIP_STRENGTH, @mode = :active)
      @auto_adjust = true
      @adjustment_sensitivity = 0.1
    end

    # Apply grip to cognitive input
    def apply(input : String, cognitive_state : CognitiveState) : Hash(String, String)
      effective_strength = calculate_effective_strength(cognitive_state)

      {
        "grip_applied"         => "true",
        "base_strength"        => @grip_strength.to_s,
        "effective_strength"   => effective_strength.to_s,
        "mode"                 => @mode.to_s,
        "input_length"         => input.size.to_s,
        "coherence_maintained" => (cognitive_state.coherence > 0.5).to_s,
      }
    end

    # Calculate effective grip strength based on state
    def calculate_effective_strength(state : CognitiveState) : Float64
      base = @grip_strength / 10.0

      # Adjust based on mode
      mode_multiplier = case @mode
                        when :passive     then 0.5
                        when :active      then 1.0
                        when :autonomous  then 1.2
                        when :coordinated then 1.1
                        else                   1.0
                        end

      # Adjust based on state
      state_factor = (state.coherence + state.focus) / 2.0

      [base * mode_multiplier * state_factor, 1.0].min
    end

    # Auto-adjust grip based on feedback
    def adjust(feedback : Hash(String, String))
      return unless @auto_adjust

      if feedback.has_key?("coherence_drop")
        # Increase grip on coherence issues
        @grip_strength = [(@grip_strength + 1), 10].min
      elsif feedback.has_key?("over_constrained")
        # Decrease grip if too constrained
        @grip_strength = [(@grip_strength - 1), 1].max
      end
    end

    # Set grip mode
    def set_mode(new_mode : Symbol)
      if Constants::AGENCY_MODES.includes?(new_mode)
        @mode = new_mode
        CogUtil::Logger.info("Grip mode changed to: #{new_mode}")
      end
    end

    def status : Hash(String, String)
      {
        "grip_strength"          => @grip_strength.to_s,
        "mode"                   => @mode.to_s,
        "auto_adjust"            => @auto_adjust.to_s,
        "adjustment_sensitivity" => @adjustment_sensitivity.to_s,
      }
    end
  end

  # Main Unified Agency Controller
  class UnifiedAgencyController
    property cognitive_state : CognitiveState
    property attention : AttentionMechanism
    property thought_stream : ThoughtStream
    property grip_controller : GripController
    property atomspace : AtomSpace::AtomSpace?
    property component_links : Hash(String, Bool)
    property coordination_log : Array(Hash(String, String))

    def initialize(grip_strength : Int32 = Constants::DEFAULT_GRIP_STRENGTH, mode : Symbol = :active)
      @cognitive_state = CognitiveState.new(grip_factor: grip_strength / 10.0)
      @attention = AttentionMechanism.new
      @thought_stream = ThoughtStream.new
      @grip_controller = GripController.new(grip_strength, mode)
      @atomspace = nil
      @component_links = {} of String => Bool
      @coordination_log = [] of Hash(String, String)
    end

    # Link a component for coordination
    def link_component(component_name : String)
      @component_links[component_name] = true
      CogUtil::Logger.info("Linked component for cognitive agency: #{component_name}")
    end

    # Unlink a component
    def unlink_component(component_name : String)
      @component_links.delete(component_name)
      CogUtil::Logger.info("Unlinked component from cognitive agency: #{component_name}")
    end

    # Attach AtomSpace
    def attach_atomspace(atomspace : AtomSpace::AtomSpace)
      @atomspace = atomspace
      CogUtil::Logger.info("AtomSpace attached to unified agency controller")
    end

    # Process cognitive input through the agency layer
    def process(input : String, source : String = "external") : Hash(String, String)
      CogUtil::Logger.debug("Processing cognitive input through unified agency")

      # Update attention
      @attention.attend(input)

      # Add to thought stream
      @thought_stream.add_thought(input, "processed_input", source, @cognitive_state.grip_factor)

      # Apply grip
      grip_result = @grip_controller.apply(input, @cognitive_state)

      # Update cognitive state
      update_state_from_input(input)

      # Log coordination
      log_coordination("process", {
        "source"       => source,
        "input_length" => input.size.to_s,
      })

      # Decay attention
      @attention.decay

      # Build result
      result = grip_result.merge(@cognitive_state.to_h)
      result["attention_score"] = @attention.attention_score(input).to_s
      result["thought_count"] = @thought_stream.thoughts.size.to_s

      result
    end

    # Coordinate grip across linked components
    def coordinate_grip(local_grip : Hash(String, String)) : Hash(String, String)
      CogUtil::Logger.debug("Coordinating grip across #{@component_links.size} components")

      coordination_result = {
        "components_coordinated" => @component_links.size.to_s,
        "coordination_mode"      => @grip_controller.mode.to_s,
        "coherence"              => @cognitive_state.coherence.to_s,
        "consensus"              => "true",
      }

      # Update state from grip info
      if local_grip.has_key?("coherence")
        new_coherence = local_grip["coherence"].to_f64 rescue @cognitive_state.coherence
        @cognitive_state.coherence = (@cognitive_state.coherence + new_coherence) / 2.0
      end

      log_coordination("grip_coordination", coordination_result)

      coordination_result
    end

    # Modulate agency based on signal
    def modulate(signal : String, intensity : Float64 = 0.5)
      case signal
      when "focus"
        @cognitive_state.focus = [(@cognitive_state.focus + intensity * 0.1), 1.0].min
        @cognitive_state.awareness = [(@cognitive_state.awareness + intensity * 0.05), 1.0].min
      when "relax"
        @cognitive_state.autonomy = [(@cognitive_state.autonomy - intensity * 0.1), 0.0].max
        @cognitive_state.grip_factor = [(@cognitive_state.grip_factor - intensity * 0.05), 0.1].max
      when "engage"
        @cognitive_state.intentionality = [(@cognitive_state.intentionality + intensity * 0.1), 1.0].min
      when "cohere"
        @cognitive_state.coherence = [(@cognitive_state.coherence + intensity * 0.1), 1.0].min
      when "amplify"
        @cognitive_state.grip_factor = [(@cognitive_state.grip_factor + intensity * 0.1), 1.0].min
      end

      @thought_stream.add_thought("Agency modulated: #{signal} (#{intensity})", "modulation", "internal")
      CogUtil::Logger.debug("Agency modulated: #{signal} (intensity: #{intensity})")
    end

    # Get current agency state
    def get_state : Hash(String, String)
      @cognitive_state.to_h.merge({
        "grip_strength"     => @grip_controller.grip_strength.to_s,
        "grip_mode"         => @grip_controller.mode.to_s,
        "attention_focuses" => @attention.focus_weights.size.to_s,
        "thought_count"     => @thought_stream.thoughts.size.to_s,
        "linked_components" => @component_links.size.to_s,
      })
    end

    # Reset agency to default state
    def reset
      @cognitive_state = CognitiveState.new(grip_factor: @grip_controller.grip_strength / 10.0)
      @attention = AttentionMechanism.new
      @thought_stream.clear
      @coordination_log.clear
      CogUtil::Logger.info("Unified agency controller reset to defaults")
    end

    # Get recent thoughts
    def recent_thoughts(n : Int32 = 20) : Array(Hash(String, String))
      @thought_stream.recent(n).map(&.to_h)
    end

    # Get top attention focuses
    def top_focuses(n : Int32 = 10) : Array(Tuple(String, Float64))
      @attention.top_focuses(n)
    end

    # Get comprehensive status
    def status : Hash(String, String)
      base_status = {
        "version"               => VERSION,
        "agency_strength"       => @cognitive_state.agency_strength.to_s,
        "optimal"               => @cognitive_state.optimal?.to_s,
        "linked_components"     => @component_links.keys.join(","),
        "coordination_log_size" => @coordination_log.size.to_s,
      }

      base_status
        .merge(@cognitive_state.to_h.transform_keys { |k| "state_#{k}" })
        .merge(@grip_controller.status.transform_keys { |k| "grip_#{k}" })
        .merge(@attention.status.transform_keys { |k| "attention_#{k}" })
        .merge(@thought_stream.status.transform_keys { |k| "thoughts_#{k}" })
    end

    private def update_state_from_input(input : String)
      # Update state based on input characteristics
      input_complexity = [input.size / 500.0, 1.0].min

      # Increase focus slightly on complex inputs
      if input_complexity > 0.5
        @cognitive_state.focus = [(@cognitive_state.focus + 0.01), 1.0].min
      end

      @cognitive_state.timestamp = Time.utc
    end

    private def log_coordination(event_type : String, data : Hash(String, String))
      entry = {
        "type"      => event_type,
        "timestamp" => Time.utc.to_s,
      }.merge(data)

      @coordination_log << entry

      if @coordination_log.size > 200
        @coordination_log.shift
      end
    end
  end

  # Factory methods
  def self.create_controller(grip_strength : Int32 = Constants::DEFAULT_GRIP_STRENGTH, mode : Symbol = :active) : UnifiedAgencyController
    UnifiedAgencyController.new(grip_strength, mode)
  end

  def self.create_optimal_controller : UnifiedAgencyController
    controller = UnifiedAgencyController.new(9, :autonomous)
    controller.modulate("engage", 0.8)
    controller.modulate("focus", 0.7)
    controller.modulate("cohere", 0.9)
    controller
  end

  def self.create_coordinated_controller : UnifiedAgencyController
    UnifiedAgencyController.new(8, :coordinated)
  end
end
