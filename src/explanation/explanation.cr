# Explanation Generation for CrystalCog
#
# This module implements interpretability and explanation features,
# enabling the system to generate human-readable justifications for
# its conclusions and decisions.
#
# References:
# - Explainable AI: https://en.wikipedia.org/wiki/Explainable_artificial_intelligence
# - OpenCog Explainability: https://wiki.opencog.org/w/Explanations

require "json"
require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Explanation
  VERSION = "0.1.0"

  class ExplanationException < Exception
  end

  # The type of reasoning step used to derive a conclusion
  enum StepType
    DEDUCTION   # A → B, A ⊢ B
    INDUCTION   # observations → general rule
    ABDUCTION   # B, A→B ⊢ A (best explanation)
    ANALOGY     # A:B :: C:?
    LOOKUP      # Direct knowledge retrieval
    INFERENCE   # Generic logical inference
    OBSERVATION # Direct sensory evidence
  end

  # A single step in a reasoning chain
  struct ReasoningStep
    getter step_type : StepType
    getter premise : String
    getter conclusion : String
    getter confidence : Float64
    getter rule_applied : String

    def initialize(
      @step_type : StepType,
      @premise : String,
      @conclusion : String,
      @confidence : Float64 = 1.0,
      @rule_applied : String = "",
    )
    end

    def to_s : String
      "[#{@step_type}] #{@premise} → #{@conclusion} (conf=#{@confidence.round(3)})"
    end
  end

  # A complete explanation trace for a conclusion
  class ExplanationTrace
    getter conclusion : String
    getter steps : Array(ReasoningStep)
    getter overall_confidence : Float64

    def initialize(@conclusion : String, @steps : Array(ReasoningStep) = [] of ReasoningStep)
      @overall_confidence = compute_confidence
    end

    def add_step(step : ReasoningStep)
      @steps << step
      @overall_confidence = compute_confidence
    end

    def depth : Int32
      @steps.size
    end

    def empty? : Bool
      @steps.empty?
    end

    # Generate a human-readable natural language explanation
    def to_natural_language : String
      return "No explanation available." if @steps.empty?

      lines = [] of String
      lines << "Conclusion: #{@conclusion}"
      lines << "Confidence: #{(@overall_confidence * 100).round(1)}%"
      lines << "Reasoning chain:"

      @steps.each_with_index do |step, i|
        prefix = "  #{i + 1}."
        case step.step_type
        when StepType::DEDUCTION
          lines << "#{prefix} Since #{step.premise}, we can deduce #{step.conclusion}."
        when StepType::INDUCTION
          lines << "#{prefix} Based on #{step.premise}, we generalize that #{step.conclusion}."
        when StepType::ABDUCTION
          lines << "#{prefix} The best explanation for #{step.premise} is that #{step.conclusion}."
        when StepType::ANALOGY
          lines << "#{prefix} By analogy with #{step.premise}, we infer #{step.conclusion}."
        when StepType::LOOKUP
          lines << "#{prefix} From stored knowledge: #{step.conclusion}."
        when StepType::OBSERVATION
          lines << "#{prefix} Observed: #{step.conclusion}."
        else
          lines << "#{prefix} Using #{step.rule_applied}: #{step.premise} → #{step.conclusion}."
        end
        unless step.rule_applied.empty?
          lines << "       (rule: #{step.rule_applied}, confidence: #{(step.confidence * 100).round(1)}%)"
        end
      end

      lines.join("\n")
    end

    private def compute_confidence : Float64
      return 0.0 if @steps.empty?
      @steps.reduce(1.0) { |acc, step| acc * step.confidence }
    end

    # Structured JSON-like map for visualization frontends
    def to_visualization : Hash(String, JSON::Any)
      steps_json = @steps.map_with_index do |step, i|
        JSON::Any.new({
          "id"          => JSON::Any.new(i.to_i64),
          "type"        => JSON::Any.new(step.step_type.to_s),
          "premise"     => JSON::Any.new(step.premise),
          "conclusion"  => JSON::Any.new(step.conclusion),
          "confidence"  => JSON::Any.new(step.confidence),
          "rule"        => JSON::Any.new(step.rule_applied),
        } of String => JSON::Any)
      end
      {
        "conclusion"          => JSON::Any.new(@conclusion),
        "overall_confidence"  => JSON::Any.new(@overall_confidence),
        "depth"               => JSON::Any.new(@steps.size.to_i64),
        "steps"               => JSON::Any.new(steps_json),
      } of String => JSON::Any
    end

    # Graph edges for chain rendering: premise -> conclusion
    def to_graph_edges : Array(Tuple(String, String, Float64))
      @steps.map { |s| {s.premise, s.conclusion, s.confidence} }
    end
  end

  # Confidence calibration: map raw confidences to reliability estimates
  class ConfidenceCalibrator
    getter bins : Array(Tuple(Float64, Float64, Int32, Int32)) # lo, hi, correct, total

    def initialize(n_bins : Int32 = 10)
      raise ExplanationException.new("n_bins must be >= 2") if n_bins < 2
      @bins = Array.new(n_bins) do |i|
        lo = i.to_f / n_bins
        hi = (i + 1).to_f / n_bins
        {lo, hi, 0, 0}
      end
    end

    def observe(predicted_confidence : Float64, correct : Bool)
      conf = predicted_confidence.clamp(0.0, 1.0)
      idx = find_bin(conf)
      lo, hi, c, t = @bins[idx]
      @bins[idx] = {lo, hi, c + (correct ? 1 : 0), t + 1}
    end

    # Reliability diagram: expected confidence vs empirical accuracy per bin
    def reliability_diagram : Array(NamedTuple(expected: Float64, accuracy: Float64, count: Int32))
      @bins.compact_map do |lo, hi, correct, total|
        next nil if total == 0
        expected = (lo + hi) / 2.0
        accuracy = correct.to_f / total
        {expected: expected, accuracy: accuracy, count: total}
      end
    end

    # Expected Calibration Error
    def ece : Float64
      total = @bins.sum { |_, _, _, t| t }
      return 0.0 if total == 0
      @bins.sum do |lo, hi, correct, t|
        next 0.0 if t == 0
        expected = (lo + hi) / 2.0
        accuracy = correct.to_f / t
        (t.to_f / total) * (accuracy - expected).abs
      end
    end

    # Natural-language calibration summary for a confidence value
    def explain_confidence(raw : Float64) : String
      conf = raw.clamp(0.0, 1.0)
      idx = find_bin(conf)
      lo, hi, correct, total = @bins[idx]
      if total == 0
        return "Confidence #{(conf * 100).round(1)}% has not been calibrated yet " \
               "(no outcomes observed in bin [#{lo.round(2)}, #{hi.round(2)}))."
      end
      accuracy = correct.to_f / total
      gap = accuracy - conf
      direction = if gap > 0.05
                    "underconfident"
                  elsif gap < -0.05
                    "overconfident"
                  else
                    "well-calibrated"
                  end
      "Predicted confidence #{(conf * 100).round(1)}% is #{direction}: " \
        "historical accuracy in this range is #{(accuracy * 100).round(1)}% " \
        "(n=#{total}, ECE=#{(ece * 100).round(2)}%)."
    end

    private def find_bin(conf : Float64) : Int32
      n = @bins.size
      idx = (conf * n).to_i
      idx = n - 1 if idx >= n
      idx = 0 if idx < 0
      idx
    end
  end

  # Generates explanations by tracing AtomSpace inference paths
  class ExplanationGenerator
    getter atomspace : AtomSpace::AtomSpace
    getter traces : Hash(String, ExplanationTrace)
    getter calibrator : ConfidenceCalibrator

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @traces = {} of String => ExplanationTrace
      @calibrator = ConfidenceCalibrator.new
      CogUtil::Logger.info("ExplanationGenerator initialized")
    end

    # Build an explanation trace for a conclusion atom
    def explain(conclusion : String, max_depth : Int32 = 5) : ExplanationTrace
      trace = ExplanationTrace.new(conclusion)
      build_trace(conclusion, trace, max_depth)
      @traces[conclusion] = trace
      trace
    end

    # Add a manually constructed reasoning step to the trace for a conclusion
    def record_step(conclusion : String, step : ReasoningStep)
      trace = @traces[conclusion]? || ExplanationTrace.new(conclusion)
      trace.add_step(step)
      @traces[conclusion] = trace
    end

    # Generate contrastive explanation: why A rather than B?
    def contrastive_explanation(chosen : String, alternative : String) : String
      trace_chosen = @traces[chosen]?
      trace_alt = @traces[alternative]?

      lines = [] of String
      lines << "Why '#{chosen}' rather than '#{alternative}'?"

      if trace_chosen && trace_alt
        conf_diff = trace_chosen.overall_confidence - trace_alt.overall_confidence
        lines << "  '#{chosen}' has confidence #{(trace_chosen.overall_confidence * 100).round(1)}%"
        lines << "  '#{alternative}' has confidence #{(trace_alt.overall_confidence * 100).round(1)}%"
        if conf_diff > 0
          lines << "  '#{chosen}' is preferred because it has #{(conf_diff * 100).round(1)}% higher confidence."
        else
          lines << "  Both have similar confidence; '#{chosen}' was selected by other criteria."
        end
        lines << "  Calibration: #{@calibrator.explain_confidence(trace_chosen.overall_confidence)}"
      elsif trace_chosen
        lines << "  '#{chosen}' has an explanation trace; '#{alternative}' does not."
      else
        lines << "  No detailed trace available for comparison."
      end

      lines.join("\n")
    end

    # Template-based natural language for a single step
    def render_step_template(step : ReasoningStep) : String
      case step.step_type
      when StepType::DEDUCTION
        "If #{step.premise}, then #{step.conclusion} (deduction, conf=#{step.confidence.round(2)})."
      when StepType::INDUCTION
        "From instances of #{step.premise}, we induce #{step.conclusion}."
      when StepType::ABDUCTION
        "#{step.conclusion} best explains #{step.premise}."
      when StepType::ANALOGY
        "Analogous to #{step.premise}, conclude #{step.conclusion}."
      when StepType::LOOKUP
        "Retrieved fact: #{step.conclusion}."
      when StepType::OBSERVATION
        "Observed evidence: #{step.conclusion}."
      else
        "Inferred #{step.conclusion} from #{step.premise} via #{step.rule_applied}."
      end
    end

    # Full calibrated natural-language explanation
    def explain_calibrated(conclusion : String) : String
      trace = @traces[conclusion]? || explain(conclusion)
      nl = trace.to_natural_language
      cal = @calibrator.explain_confidence(trace.overall_confidence)
      "#{nl}\n\nConfidence calibration:\n#{cal}"
    end

    # Visualization payload for a conclusion
    def visualize(conclusion : String) : Hash(String, JSON::Any)
      trace = @traces[conclusion]? || explain(conclusion)
      viz = trace.to_visualization
      viz["calibration_ece"] = JSON::Any.new(@calibrator.ece)
      viz
    end

    # Store explanation traces in AtomSpace as inference chains
    def to_atomspace
      @traces.each do |conclusion, trace|
        conclusion_node = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, conclusion)

        trace.steps.each_with_index do |step, i|
          step_node = @atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            "step_#{conclusion}_#{i}_#{step.step_type.to_s.downcase}"
          )
          premise_node = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, step.premise)
          rule_pred = @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "implies")
          list = @atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [premise_node, conclusion_node])
          @atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [rule_pred, list],
            AtomSpace::SimpleTruthValue.new(step.confidence, 0.9)
          )
          _ = step_node
        end
      end
    end

    private def build_trace(conclusion : String, trace : ExplanationTrace, depth : Int32)
      return if depth == 0

      # Look for ImplicationLinks in AtomSpace where the consequent matches conclusion
      @atomspace.get_atoms_by_type(AtomSpace::AtomType::IMPLICATION_LINK).each do |link|
        next unless link.is_a?(AtomSpace::Link)
        next if link.outgoing.size < 2

        consequent = link.outgoing.last
        next unless consequent.name == conclusion

        premise = link.outgoing.first
        step = ReasoningStep.new(
          StepType::DEDUCTION,
          premise.name,
          conclusion,
          link.truth_value.strength,
          "ImplicationLink"
        )
        trace.add_step(step)
        build_trace(premise.name, trace, depth - 1)
        break # One supporting path is enough for basic explanation
      end
    end
  end

  # Initialize Explanation subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Explanation subsystem...")
    CogUtil::Logger.info("Explanation subsystem initialized successfully")
  end
end
