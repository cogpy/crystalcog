# Explanation Generation Module for CrystalCog
#
# This module provides explanation and interpretability capabilities including:
# - Reasoning trace generation
# - Causal explanation
# - Counterfactual reasoning
# - Natural language explanation generation
# - Attention-based explanation
# - Rule-based justification
#
# References:
# - Explainable AI: Guidotti et al. 2019
# - LIME: Ribeiro et al. 2016
# - Counterfactual Explanations: Wachter et al. 2017

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../pln/pln"
require "../nlp/nlp_main"

module Explanation
  VERSION = "0.1.0"

  # Exception classes
  class ExplanationException < Exception
  end

  class TraceNotFoundException < ExplanationException
  end

  class GenerationException < ExplanationException
  end

  # Explanation types
  enum ExplanationType
    CAUSAL           # Why did X cause Y?
    CONTRASTIVE      # Why X instead of Y?
    COUNTERFACTUAL   # What if X were different?
    TRACE            # How was conclusion reached?
    RULE_BASED       # Which rules were applied?
    FEATURE_BASED    # Which features contributed?
  end

  # Reasoning step in a trace
  struct ReasoningStep
    getter step_number : Int32
    getter rule_name : String
    getter premises : Array(String)
    getter conclusion : String
    getter confidence : Float64
    getter timestamp : Time

    def initialize(@step_number : Int32, @rule_name : String,
                   @premises : Array(String), @conclusion : String,
                   @confidence : Float64)
      @timestamp = Time.utc
    end

    def to_s : String
      "Step #{@step_number}: #{@rule_name}\n" +
        "  Premises: #{@premises.join(", ")}\n" +
        "  Conclusion: #{@conclusion} (conf: #{@confidence.round(3)})"
    end
  end

  # Reasoning trace - full derivation path
  class ReasoningTrace
    getter id : String
    getter query : String
    getter steps : Array(ReasoningStep)
    getter final_conclusion : String?
    getter final_confidence : Float64
    getter start_time : Time
    getter end_time : Time?

    def initialize(@query : String)
      @id = UUID.random.to_s
      @steps = [] of ReasoningStep
      @final_conclusion = nil
      @final_confidence = 0.0
      @start_time = Time.utc
      @end_time = nil
    end

    def add_step(rule_name : String, premises : Array(String),
                 conclusion : String, confidence : Float64)
      step = ReasoningStep.new(
        @steps.size + 1,
        rule_name,
        premises,
        conclusion,
        confidence
      )
      @steps << step
    end

    # Crystal invokes `finalize` with no arguments when registering a GC
    # finalizer. Keep that lifecycle hook separate from the public trace
    # completion overload below.
    def finalize
    end

    def finalize(conclusion : String, confidence : Float64)
      @final_conclusion = conclusion
      @final_confidence = confidence
      @end_time = Time.utc
    end

    def duration : Time::Span?
      if end_t = @end_time
        end_t - @start_time
      else
        nil
      end
    end

    def depth : Int32
      @steps.size
    end

    def rules_used : Array(String)
      @steps.map(&.rule_name).uniq
    end

    def to_s : String
      result = "=== Reasoning Trace ===\n"
      result += "Query: #{@query}\n"
      result += "Steps: #{@steps.size}\n\n"

      @steps.each do |step|
        result += "#{step}\n\n"
      end

      if conclusion = @final_conclusion
        result += "Final Conclusion: #{conclusion}\n"
        result += "Confidence: #{@final_confidence.round(3)}\n"
      end

      if dur = duration
        result += "Duration: #{dur.total_milliseconds.round(2)}ms\n"
      end

      result
    end
  end

  # Explanation node in explanation graph
  class ExplanationNode
    getter id : String
    getter content : String
    getter node_type : Symbol
    getter importance : Float64
    getter children : Array(ExplanationNode)
    getter metadata : Hash(String, String)

    def initialize(@content : String, @node_type : Symbol = :fact,
                   @importance : Float64 = 1.0)
      @id = UUID.random.to_s
      @children = [] of ExplanationNode
      @metadata = {} of String => String
    end

    def add_child(node : ExplanationNode)
      @children << node
    end

    def leaf? : Bool
      @children.empty?
    end

    def set_metadata(key : String, value : String)
      @metadata[key] = value
    end
  end

  # Explanation graph for structured explanations
  class ExplanationGraph
    getter root : ExplanationNode?
    getter nodes : Hash(String, ExplanationNode)

    def initialize
      @root = nil
      @nodes = {} of String => ExplanationNode
    end

    def set_root(node : ExplanationNode)
      @root = node
      @nodes[node.id] = node
    end

    def add_node(node : ExplanationNode, parent_id : String? = nil)
      @nodes[node.id] = node

      if pid = parent_id
        if parent = @nodes[pid]?
          parent.add_child(node)
        end
      elsif @root.nil?
        @root = node
      end
    end

    def get_node(id : String) : ExplanationNode?
      @nodes[id]?
    end

    def size : Int32
      @nodes.size
    end

    def depth : Int32
      return 0 unless root = @root
      calculate_depth(root)
    end

    private def calculate_depth(node : ExplanationNode) : Int32
      return 1 if node.leaf?
      1 + node.children.max_of { |c| calculate_depth(c) }
    end

    # Convert to natural language
    def to_natural_language : String
      return "" unless root = @root
      generate_nl(root, 0)
    end

    private def generate_nl(node : ExplanationNode, level : Int32) : String
      result = ""

      case node.node_type
      when :conclusion
        result += "Therefore, #{node.content}.\n"
      when :premise
        result += "Because #{node.content}"
        if !node.leaf?
          result += ", which follows from:\n"
          node.children.each do |child|
            result += "  " * (level + 1) + "- " + generate_nl(child, level + 1)
          end
        else
          result += ".\n"
        end
      when :rule
        result += "By applying #{node.content}:\n"
        node.children.each do |child|
          result += "  " * (level + 1) + generate_nl(child, level + 1)
        end
      when :fact
        result += "#{node.content}.\n"
      else
        result += "#{node.content}\n"
      end

      result
    end
  end

  # Causal model for causal explanations
  class CausalModel
    getter variables : Hash(String, CausalVariable)
    getter edges : Array(CausalEdge)

    def initialize
      @variables = {} of String => CausalVariable
      @edges = [] of CausalEdge
    end

    def add_variable(name : String, value : Float64 = 0.0)
      @variables[name] = CausalVariable.new(name, value)
    end

    def add_edge(cause : String, effect : String, strength : Float64 = 1.0)
      @edges << CausalEdge.new(cause, effect, strength)
    end

    def get_causes(effect : String) : Array(String)
      @edges.select { |e| e.effect == effect }.map(&.cause)
    end

    def get_effects(cause : String) : Array(String)
      @edges.select { |e| e.cause == cause }.map(&.effect)
    end

    # Intervention: Set a variable to a specific value
    def intervene(variable : String, value : Float64) : Hash(String, Float64)
      result = {} of String => Float64

      if var = @variables[variable]?
        var.value = value
        result[variable] = value

        # Propagate effects
        propagate(variable, result)
      end

      result
    end

    # Counterfactual: What would happen if X were Y?
    def counterfactual(variable : String, value : Float64) : Hash(String, Float64)
      # Save original values
      original_values = @variables.transform_values(&.value)

      # Perform intervention
      result = intervene(variable, value)

      # Restore original values
      original_values.each { |name, val| @variables[name].value = val }

      result
    end

    # Find causal path between two variables
    def causal_path(from : String, to : String) : Array(String)?
      visited = Set(String).new
      path = [] of String

      if find_path(from, to, visited, path)
        path
      else
        nil
      end
    end

    private def propagate(variable : String, result : Hash(String, Float64))
      effects = get_effects(variable)

      effects.each do |effect|
        if var = @variables[effect]?
          edge = @edges.find { |e| e.cause == variable && e.effect == effect }
          next unless edge

          # Simple linear propagation
          new_value = result[variable] * edge.strength
          var.value = new_value
          result[effect] = new_value

          propagate(effect, result)
        end
      end
    end

    private def find_path(from : String, to : String, visited : Set(String),
                          path : Array(String)) : Bool
      return false if visited.includes?(from)
      visited.add(from)
      path << from

      return true if from == to

      get_effects(from).each do |next_var|
        if find_path(next_var, to, visited, path)
          return true
        end
      end

      path.pop
      false
    end
  end

  class CausalVariable
    getter name : String
    property value : Float64

    def initialize(@name : String, @value : Float64 = 0.0)
    end
  end

  struct CausalEdge
    getter cause : String
    getter effect : String
    getter strength : Float64

    def initialize(@cause : String, @effect : String, @strength : Float64 = 1.0)
    end
  end

  # Feature importance for feature-based explanations
  class FeatureImportance
    getter features : Hash(String, Float64)
    getter prediction : String
    getter confidence : Float64

    def initialize(@prediction : String, @confidence : Float64)
      @features = {} of String => Float64
    end

    def set_importance(feature : String, importance : Float64)
      @features[feature] = importance
    end

    def top_features(k : Int32 = 5) : Array(Tuple(String, Float64))
      @features.to_a.sort_by { |_, imp| -imp.abs }.first(k)
    end

    def positive_features : Array(Tuple(String, Float64))
      @features.to_a.select { |_, imp| imp > 0 }.sort_by { |_, imp| -imp }
    end

    def negative_features : Array(Tuple(String, Float64))
      @features.to_a.select { |_, imp| imp < 0 }.sort_by { |_, imp| imp }
    end

    def to_natural_language : String
      result = "The prediction '#{@prediction}' (confidence: #{(@confidence * 100).round(1)}%) was made because:\n"

      positive = positive_features.first(3)
      negative = negative_features.first(3)

      unless positive.empty?
        result += "\nPositive factors:\n"
        positive.each do |feature, imp|
          result += "  - #{feature} contributed #{(imp * 100).round(1)}%\n"
        end
      end

      unless negative.empty?
        result += "\nNegative factors:\n"
        negative.each do |feature, imp|
          result += "  - #{feature} reduced confidence by #{(imp.abs * 100).round(1)}%\n"
        end
      end

      result
    end
  end

  # Main Explainer class
  class Explainer
    getter atomspace : AtomSpace::AtomSpace
    getter traces : Hash(String, ReasoningTrace)
    getter causal_model : CausalModel
    @current_trace : ReasoningTrace?

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @traces = {} of String => ReasoningTrace
      @causal_model = CausalModel.new
      @current_trace = nil
      CogUtil::Logger.info("Explainer initialized")
    end

    # Start recording a reasoning trace
    def start_trace(query : String) : String
      trace = ReasoningTrace.new(query)
      @current_trace = trace
      @traces[trace.id] = trace
      trace.id
    end

    # Record a reasoning step
    def record_step(rule_name : String, premises : Array(String),
                    conclusion : String, confidence : Float64)
      if trace = @current_trace
        trace.add_step(rule_name, premises, conclusion, confidence)
      end
    end

    # End recording and finalize trace
    def end_trace(conclusion : String, confidence : Float64) : ReasoningTrace?
      if trace = @current_trace
        trace.finalize(conclusion, confidence)
        @current_trace = nil
        trace
      else
        nil
      end
    end

    # Get a recorded trace
    def get_trace(id : String) : ReasoningTrace?
      @traces[id]?
    end

    # Generate explanation for an atom
    def explain(atom : AtomSpace::Atom, type : ExplanationType = ExplanationType::TRACE) : String
      case type
      when ExplanationType::TRACE
        explain_trace(atom)
      when ExplanationType::CAUSAL
        explain_causal(atom)
      when ExplanationType::COUNTERFACTUAL
        explain_counterfactual(atom)
      when ExplanationType::RULE_BASED
        explain_rules(atom)
      when ExplanationType::CONTRASTIVE
        explain_contrastive(atom)
      when ExplanationType::FEATURE_BASED
        explain_features(atom)
      else
        "Unknown explanation type"
      end
    end

    # Generate explanation graph
    def build_explanation_graph(atom : AtomSpace::Atom) : ExplanationGraph
      graph = ExplanationGraph.new

      root = ExplanationNode.new(atom.to_s, :conclusion, 1.0)
      graph.set_root(root)

      # Find supporting atoms
      supporting = find_supporting_atoms(atom)

      supporting.each do |support|
        node = ExplanationNode.new(
          support[:atom].to_s,
          :premise,
          support[:importance]
        )
        graph.add_node(node, root.id)

        # Add rule if available
        if rule = support[:rule]?
          rule_node = ExplanationNode.new(rule, :rule, 0.8)
          graph.add_node(rule_node, node.id)
        end
      end

      graph
    end

    # Why question: Why is X true?
    def why(conclusion : AtomSpace::Atom) : String
      graph = build_explanation_graph(conclusion)
      graph.to_natural_language
    end

    # Why not question: Why isn't X true?
    def why_not(conclusion : AtomSpace::Atom) : String
      result = "The conclusion '#{conclusion}' is not established because:\n"

      # Find what's missing
      if conclusion.is_a?(AtomSpace::Link)
        missing = find_missing_premises(conclusion)

        if missing.empty?
          result += "- No supporting evidence was found\n"
        else
          missing.each do |premise|
            result += "- Missing premise: #{premise}\n"
          end
        end
      end

      # Check truth value
      tv = conclusion.truth_value
      if tv.strength < 0.5
        result += "- Current truth value is too low: #{tv.strength.round(3)}\n"
      end
      if tv.confidence < 0.5
        result += "- Confidence is insufficient: #{tv.confidence.round(3)}\n"
      end

      result
    end

    # What-if question: What if X were different?
    def what_if(variable : String, new_value : Float64) : String
      result = "If '#{variable}' were #{new_value}:\n"

      effects = @causal_model.counterfactual(variable, new_value)

      if effects.empty?
        result += "- No significant changes would occur\n"
      else
        effects.each do |var, val|
          next if var == variable
          result += "- '#{var}' would become #{val.round(3)}\n"
        end
      end

      result
    end

    # How question: How was X derived?
    def how(conclusion : AtomSpace::Atom) : String
      result = "Derivation of '#{conclusion}':\n\n"

      # Find relevant trace
      relevant_trace = @traces.values.find do |trace|
        trace.final_conclusion == conclusion.to_s
      end

      if trace = relevant_trace
        result += trace.to_s
      else
        # Build derivation from atomspace
        result += "Direct derivation:\n"

        if conclusion.is_a?(AtomSpace::Link)
          conclusion.outgoing.each_with_index do |atom, i|
            result += "  #{i + 1}. #{atom}\n"
          end
        end

        result += "\nWith truth value: strength=#{conclusion.truth_value.strength.round(3)}, "
        result += "confidence=#{conclusion.truth_value.confidence.round(3)}\n"
      end

      result
    end

    # Summarize all reasoning for a query
    def summarize(query : String) : String
      result = "=== Explanation Summary ===\n"
      result += "Query: #{query}\n\n"

      # Find relevant traces
      relevant = @traces.values.select { |t| t.query.includes?(query) }

      if relevant.empty?
        result += "No reasoning traces found for this query.\n"
      else
        result += "Found #{relevant.size} relevant reasoning trace(s):\n\n"

        relevant.each_with_index do |trace, i|
          result += "Trace #{i + 1}:\n"
          result += "- Steps: #{trace.depth}\n"
          result += "- Rules used: #{trace.rules_used.join(", ")}\n"
          result += "- Conclusion: #{trace.final_conclusion}\n"
          result += "- Confidence: #{trace.final_confidence.round(3)}\n"
          if dur = trace.duration
            result += "- Duration: #{dur.total_milliseconds.round(2)}ms\n"
          end
          result += "\n"
        end
      end

      result
    end

    # Generate natural language explanation
    def to_natural_language(atom : AtomSpace::Atom) : String
      case atom
      when AtomSpace::Node
        explain_node(atom)
      when AtomSpace::Link
        explain_link(atom)
      else
        atom.to_s
      end
    end

    private def explain_trace(atom : AtomSpace::Atom) : String
      "Trace explanation for: #{atom}"
    end

    private def explain_causal(atom : AtomSpace::Atom) : String
      result = "Causal explanation for '#{atom}':\n"

      if atom.is_a?(AtomSpace::Link)
        causes = find_causes(atom)
        if causes.empty?
          result += "No direct causes identified.\n"
        else
          causes.each do |cause|
            result += "- Caused by: #{cause}\n"
          end
        end
      end

      result
    end

    private def explain_counterfactual(atom : AtomSpace::Atom) : String
      "Counterfactual: What if '#{atom}' were different..."
    end

    private def explain_rules(atom : AtomSpace::Atom) : String
      result = "Rules applied to derive '#{atom}':\n"

      # Find traces that led to this atom
      @traces.values.each do |trace|
        if trace.final_conclusion == atom.to_s
          trace.steps.each do |step|
            result += "- #{step.rule_name}: #{step.premises.join(" + ")} -> #{step.conclusion}\n"
          end
        end
      end

      result
    end

    private def explain_contrastive(atom : AtomSpace::Atom) : String
      result = "Contrastive explanation for '#{atom}':\n"
      result += "This conclusion was reached instead of alternatives because:\n"

      # Find alternative conclusions
      alternatives = find_alternatives(atom)
      alternatives.first(3).each do |alt|
        result += "- Not '#{alt}' because: "
        result += "confidence was lower or premises were not satisfied\n"
      end

      result
    end

    private def explain_features(atom : AtomSpace::Atom) : String
      importance = calculate_feature_importance(atom)
      importance.to_natural_language
    end

    private def explain_node(node : AtomSpace::Node) : String
      case node.type
      when AtomSpace::AtomType::CONCEPT_NODE
        "The concept '#{node.name}'"
      when AtomSpace::AtomType::PREDICATE_NODE
        "The predicate '#{node.name}'"
      when AtomSpace::AtomType::VARIABLE_NODE
        "A variable representing #{node.name}"
      else
        "#{node.type}: #{node.name}"
      end
    end

    private def explain_link(link : AtomSpace::Link) : String
      case link.type
      when AtomSpace::AtomType::INHERITANCE_LINK
        if link.outgoing.size == 2
          "#{to_natural_language(link.outgoing[0])} is a type of #{to_natural_language(link.outgoing[1])}"
        else
          link.to_s
        end
      when AtomSpace::AtomType::EVALUATION_LINK
        if link.outgoing.size == 2
          predicate = link.outgoing[0]
          args = link.outgoing[1]
          "#{to_natural_language(predicate)} holds for #{to_natural_language(args)}"
        else
          link.to_s
        end
      when AtomSpace::AtomType::IMPLICATION_LINK
        if link.outgoing.size == 2
          "If #{to_natural_language(link.outgoing[0])}, then #{to_natural_language(link.outgoing[1])}"
        else
          link.to_s
        end
      when AtomSpace::AtomType::AND_LINK
        parts = link.outgoing.map { |a| to_natural_language(a) }
        parts.join(" and ")
      when AtomSpace::AtomType::OR_LINK
        parts = link.outgoing.map { |a| to_natural_language(a) }
        parts.join(" or ")
      when AtomSpace::AtomType::NOT_LINK
        if link.outgoing.size == 1
          "It is not the case that #{to_natural_language(link.outgoing[0])}"
        else
          link.to_s
        end
      when AtomSpace::AtomType::LIST_LINK
        parts = link.outgoing.map { |a| to_natural_language(a) }
        parts.join(", ")
      else
        link.to_s
      end
    end

    private def find_supporting_atoms(atom : AtomSpace::Atom) : Array(NamedTuple(atom: AtomSpace::Atom, importance: Float64, rule: String?))
      supports = [] of NamedTuple(atom: AtomSpace::Atom, importance: Float64, rule: String?)

      if atom.is_a?(AtomSpace::Link)
        atom.outgoing.each do |outgoing_atom|
          supports << {
            atom:       outgoing_atom,
            importance: 1.0 / atom.outgoing.size,
            rule:       nil,
          }
        end
      end

      # Find implication links that conclude this atom
      @atomspace.get_all_atoms.each do |other|
        next unless other.is_a?(AtomSpace::Link)
        next unless other.type == AtomSpace::AtomType::IMPLICATION_LINK
        next unless other.outgoing.size == 2

        if other.outgoing[1].to_s == atom.to_s
          supports << {
            atom:       other.outgoing[0],
            importance: other.truth_value.strength,
            rule:       "Implication",
          }
        end
      end

      supports
    end

    private def find_missing_premises(conclusion : AtomSpace::Link) : Array(String)
      missing = [] of String

      # Check for required but missing premises
      conclusion.outgoing.each do |required|
        found = @atomspace.get_all_atoms.any? do |atom|
          atom.to_s == required.to_s && atom.truth_value.strength > 0.5
        end

        unless found
          missing << required.to_s
        end
      end

      missing
    end

    private def find_causes(atom : AtomSpace::Link) : Array(String)
      causes = [] of String

      @atomspace.get_all_atoms.each do |other|
        next unless other.is_a?(AtomSpace::Link)
        next unless other.type == AtomSpace::AtomType::IMPLICATION_LINK

        if other.outgoing.size == 2 && other.outgoing[1].to_s == atom.to_s
          causes << other.outgoing[0].to_s
        end
      end

      causes
    end

    private def find_alternatives(atom : AtomSpace::Atom) : Array(String)
      alternatives = [] of String

      if atom.is_a?(AtomSpace::Link)
        # Find similar links with different conclusions
        @atomspace.get_all_atoms.each do |other|
          next unless other.is_a?(AtomSpace::Link)
          next unless other.type == atom.type
          next if other.to_s == atom.to_s

          if other.outgoing.size == atom.outgoing.size
            alternatives << other.to_s
          end
        end
      end

      alternatives
    end

    private def calculate_feature_importance(atom : AtomSpace::Atom) : FeatureImportance
      importance = FeatureImportance.new(atom.to_s, atom.truth_value.strength)

      if atom.is_a?(AtomSpace::Link)
        total = atom.outgoing.size.to_f64

        atom.outgoing.each_with_index do |outgoing_atom, i|
          feature_name = "feature_#{i + 1}: #{outgoing_atom}"
          feature_importance = outgoing_atom.truth_value.strength / total
          importance.set_importance(feature_name, feature_importance)
        end
      end

      importance
    end
  end

  # Trace-enabled PLN inference
  class TracedInference
    getter explainer : Explainer
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @explainer = Explainer.new(@atomspace)
      CogUtil::Logger.info("TracedInference initialized")
    end

    def forward_chain(max_steps : Int32 = 10, trace_query : String = "forward_chain") : Array(AtomSpace::Atom)
      trace_id = @explainer.start_trace(trace_query)
      results = [] of AtomSpace::Atom

      # Simulated forward chaining with tracing
      max_steps.times do |step|
        # Find applicable rules and apply
        @atomspace.get_all_atoms.each do |atom|
          next unless atom.is_a?(AtomSpace::Link)
          next unless atom.type == AtomSpace::AtomType::IMPLICATION_LINK
          next unless atom.outgoing.size == 2

          antecedent = atom.outgoing[0]
          consequent = atom.outgoing[1]

          # Check if antecedent is satisfied
          if antecedent.truth_value.strength > 0.5
            # Apply modus ponens
            new_tv = AtomSpace::SimpleTruthValue.new(
              atom.truth_value.strength * antecedent.truth_value.strength,
              atom.truth_value.confidence * antecedent.truth_value.confidence
            )

            @explainer.record_step(
              "Modus Ponens",
              [antecedent.to_s, atom.to_s],
              consequent.to_s,
              new_tv.strength
            )

            results << consequent
          end
        end
      end

      if results.empty?
        @explainer.end_trace("No conclusions derived", 0.0)
      else
        best = results.max_by(&.truth_value.strength)
        @explainer.end_trace(best.to_s, best.truth_value.strength)
      end

      results
    end

    def explain_last_inference : String
      if trace_id = @explainer.traces.keys.last?
        if trace = @explainer.get_trace(trace_id)
          return trace.to_s
        end
      end
      "No inference trace available"
    end
  end

  # Module-level convenience methods
  def self.create_explainer(atomspace : AtomSpace::AtomSpace) : Explainer
    Explainer.new(atomspace)
  end

  def self.create_traced_inference(atomspace : AtomSpace::AtomSpace) : TracedInference
    TracedInference.new(atomspace)
  end

  def self.create_causal_model : CausalModel
    CausalModel.new
  end

  def self.create_explanation_graph : ExplanationGraph
    ExplanationGraph.new
  end
end
