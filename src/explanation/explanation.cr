# Explanation Generation for CrystalCog
#
# This module implements interpretability and explanation features,
# enabling the system to generate human-readable justifications for
# its conclusions and decisions.
#
# References:
# - Explainable AI: https://en.wikipedia.org/wiki/Explainable_artificial_intelligence
# - OpenCog Explainability: https://wiki.opencog.org/w/Explanations

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Explanation
  VERSION = "0.1.0"

  class ExplanationException < Exception
  end

  # The type of reasoning step used to derive a conclusion
  enum StepType
    DEDUCTION        # A → B, A ⊢ B
    INDUCTION        # observations → general rule
    ABDUCTION        # B, A→B ⊢ A (best explanation)
    ANALOGY          # A:B :: C:? 
    LOOKUP           # Direct knowledge retrieval
    INFERENCE        # Generic logical inference
    OBSERVATION      # Direct sensory evidence
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
      @rule_applied : String = ""
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
  end

  # Generates explanations by tracing AtomSpace inference paths
  class ExplanationGenerator
    getter atomspace : AtomSpace::AtomSpace
    getter traces : Hash(String, ExplanationTrace)

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @traces = {} of String => ExplanationTrace
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
      elsif trace_chosen
        lines << "  '#{chosen}' has an explanation trace; '#{alternative}' does not."
      else
        lines << "  No detailed trace available for comparison."
      end

      lines.join("\n")
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
        break  # One supporting path is enough for basic explanation
      end
    end
  end

  # Initialize Explanation subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Explanation subsystem...")
    CogUtil::Logger.info("Explanation subsystem initialized successfully")
  end
end
