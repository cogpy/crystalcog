# Crystal implementation of URE (Unified Rule Engine)
# Converted from ure/opencog/ure/

require "../atomspace/atomspace_main"
require "../cogutil/cogutil"

module URE
  VERSION = "0.1.0"

  # Generic rule interface for URE
  abstract class Rule
    abstract def name : String
    abstract def premises : Array(AtomSpace::AtomType)
    abstract def conclusion : AtomSpace::AtomType
    abstract def apply(premises : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
    abstract def fitness(premises : Array(AtomSpace::Atom)) : Float64
  end

  # Rule to handle simple logical conjunction
  class ConjunctionRule < Rule
    def name : String
      "ConjunctionRule"
    end

    def premises : Array(AtomSpace::AtomType)
      [AtomSpace::AtomType::EVALUATION_LINK, AtomSpace::AtomType::EVALUATION_LINK]
    end

    def conclusion : AtomSpace::AtomType
      AtomSpace::AtomType::AND_LINK
    end

    def apply(premises : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premises.size >= 2

      # Calculate conjunction truth value
      min_strength = premises.map(&.truth_value.strength).min
      min_confidence = premises.map(&.truth_value.confidence).min

      tv = AtomSpace::SimpleTruthValue.new(min_strength, min_confidence * 0.9)

      # Create AND link
      atomspace.add_link(AtomSpace::AtomType::AND_LINK, premises, tv)
    end

    def fitness(premises : Array(AtomSpace::Atom)) : Float64
      # Fitness based on truth value confidence
      premises.map(&.truth_value.confidence).sum / premises.size
    end
  end

  # Simple inheritance transitivity rule for demonstration
  class InheritanceTransitivityRule < Rule
    def name : String
      "InheritanceTransitivityRule"
    end

    def premises : Array(AtomSpace::AtomType)
      [AtomSpace::AtomType::INHERITANCE_LINK, AtomSpace::AtomType::INHERITANCE_LINK]
    end

    def conclusion : AtomSpace::AtomType
      AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premises : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premises.size == 2

      link1, link2 = premises[0], premises[1]
      return nil unless link1.is_a?(AtomSpace::Link) && link2.is_a?(AtomSpace::Link)
      return nil unless link1.outgoing.size == 2 && link2.outgoing.size == 2

      # Check for transitivity: A->B, B->C => A->C
      if link1.outgoing[1] == link2.outgoing[0]
        # A inherits from B, B inherits from C => A inherits from C
        a, b = link1.outgoing[0], link1.outgoing[1]
        c = link2.outgoing[1]

        # Calculate new truth value using transitivity formula
        tv1, tv2 = link1.truth_value, link2.truth_value
        new_strength = tv1.strength * tv2.strength
        new_confidence = tv1.confidence * tv2.confidence * 0.9 # Slight confidence reduction

        tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

        # Create new inheritance link
        atomspace.add_inheritance_link(a, c, tv)
      else
        nil
      end
    end

    def fitness(premises : Array(AtomSpace::Atom)) : Float64
      # High fitness for inheritance links with good confidence
      premises.map(&.truth_value.confidence).sum / premises.size
    end
  end

  class ModusPonensRule < Rule
    def name : String
      "ModusPonensRule"
    end

    def premises : Array(AtomSpace::AtomType)
      [AtomSpace::AtomType::IMPLICATION_LINK, AtomSpace::AtomType::EVALUATION_LINK]
    end

    def conclusion : AtomSpace::AtomType
      AtomSpace::AtomType::EVALUATION_LINK
    end

    def apply(premises : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premises.size == 2

      implication, antecedent = premises[0], premises[1]

      # Check if implication structure matches
      return nil unless implication.is_a?(AtomSpace::Link)
      return nil unless implication.outgoing.size == 2

      if_part, then_part = implication.outgoing[0], implication.outgoing[1]

      # Check if antecedent matches the if_part
      return nil unless antecedent == if_part

      # Calculate conclusion truth value using modus ponens formula
      tv_impl = implication.truth_value
      tv_ante = antecedent.truth_value

      # Simplified modus ponens: min(P(A), P(A->B))
      new_strength = [tv_ante.strength, tv_impl.strength].min
      new_confidence = tv_ante.confidence * tv_impl.confidence * 0.95

      tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

      # Return the consequent with new truth value
      then_part.truth_value = tv
      then_part
    end

    def fitness(premises : Array(AtomSpace::Atom)) : Float64
      premises.map(&.truth_value.strength).min
    end
  end

  # Forward chainer for URE
  class ForwardChainer
    @rules : Array(Rule)
    @max_iterations : Int32
    @seen_results : Set(String)
    MAX_APPLICATIONS_PER_RULE = 500

    def initialize(@atomspace : AtomSpace::AtomSpace, @max_iterations = 100)
      @rules = [] of Rule
      @seen_results = Set(String).new
    end

    def add_rule(rule : Rule)
      @rules << rule
    end

    def clear_seen_results
      @seen_results.clear
    end

    def add_default_rules
      add_rule(ConjunctionRule.new)
      add_rule(ModusPonensRule.new)
      add_rule(InheritanceTransitivityRule.new)
    end

    def run : Array(AtomSpace::Atom)
      @seen_results.clear
      new_atoms = [] of AtomSpace::Atom
      iterations = 0

      while iterations < @max_iterations
        step_atoms = step_forward
        break if step_atoms.empty?

        new_atoms.concat(step_atoms)
        iterations += 1

        CogUtil::Logger.debug("URE: Forward step #{iterations}, generated #{step_atoms.size} atoms")
      end

      CogUtil::Logger.info("URE: Forward chaining completed in #{iterations} steps, generated #{new_atoms.size} atoms")
      new_atoms
    end

    def step_forward : Array(AtomSpace::Atom)
      step_atoms = [] of AtomSpace::Atom

      @rules.each do |rule|
        rule_applications = find_rule_applications(rule)

        rule_applications.each do |premises|
          fitness = rule.fitness(premises)
          next if fitness < 0.1

          result = rule.apply(premises, @atomspace)
          if result
            key = "#{result.type}:#{result.to_s}"
            next if @seen_results.includes?(key)
            @seen_results.add(key)
            if !@atomspace.contains?(result)
              step_atoms << result
              CogUtil::Logger.debug("URE: Applied #{rule.name}, fitness: #{fitness}")
            end
          end
        end
      end

      step_atoms
    end

    private def find_rule_applications(rule : Rule) : Array(Array(AtomSpace::Atom))
      applications = [] of Array(AtomSpace::Atom)
      premise_types = rule.premises

      case premise_types.size
      when 1
        atoms = @atomspace.get_atoms_by_type(premise_types[0])
        atoms.each do |atom|
          applications << [atom]
          break if applications.size >= MAX_APPLICATIONS_PER_RULE
        end
      when 2
        atoms1 = @atomspace.get_atoms_by_type(premise_types[0])
        atoms2 = @atomspace.get_atoms_by_type(premise_types[1])

        atoms1.each do |a1|
          atoms2.each do |a2|
            if a1 != a2
              applications << [a1, a2]
              break if applications.size >= MAX_APPLICATIONS_PER_RULE
            end
          end
          break if applications.size >= MAX_APPLICATIONS_PER_RULE
        end
      end

      applications
    end
  end

  # Backward Inference Tree node for advanced backward chaining
  class BITNode
    property target : AtomSpace::Atom
    property rule : Rule?
    property premises : Array(BITNode)
    property results : Array(AtomSpace::Atom)
    property fitness : Float64
    property depth : Int32
    property exhausted : Bool

    def initialize(@target : AtomSpace::Atom, @depth = 0)
      @rule = nil
      @premises = [] of BITNode
      @results = [] of AtomSpace::Atom
      @fitness = 0.0
      @exhausted = false
    end

    def is_leaf? : Bool
      @premises.empty?
    end

    def add_premise(premise : BITNode)
      @premises << premise
    end

    def calculate_fitness(atomspace : AtomSpace::AtomSpace) : Float64
      # Calculate fitness based on truth value and complexity
      tv = @target.truth_value
      base_fitness = tv.strength * tv.confidence

      # Penalize complex expressions
      complexity_penalty = Math.exp(-@depth * 0.1)

      # Reward if target already exists in atomspace
      existence_bonus = atomspace.contains?(@target) ? 0.2 : 0.0

      @fitness = base_fitness * complexity_penalty + existence_bonus
    end
  end

  # Advanced backward chainer for URE with BIT support
  class BackwardChainer
    @rules : Array(Rule)
    @max_depth : Int32
    @max_iterations : Int32
    @current_iteration : Int32
    @root_bit : BITNode?
    @inference_tree : Array(BITNode)

    def initialize(@atomspace : AtomSpace::AtomSpace, @max_depth = 10, @max_iterations = 100)
      @rules = [] of Rule
      @current_iteration = 0
      @root_bit = nil
      @inference_tree = [] of BITNode
    end

    def add_rule(rule : Rule)
      @rules << rule
    end

    def add_default_rules
      add_rule(ConjunctionRule.new)
      add_rule(ModusPonensRule.new)
      add_rule(InheritanceTransitivityRule.new)
    end

    # Advanced backward chaining with BIT construction
    def do_chain(target : AtomSpace::Atom) : Array(AtomSpace::Atom)
      @root_bit = BITNode.new(target, 0)
      @inference_tree = [@root_bit.not_nil!]
      @current_iteration = 0

      while !termination_criteria_met?
        expand_inference_tree
        fulfill_best_nodes
        @current_iteration += 1
      end

      collect_results
    end

    # Simpler backward query for compatibility
    def query(target : AtomSpace::Atom, depth = 0) : Bool
      results = do_chain(target)
      !results.empty?
    end

    # Variable fulfillment query - find groundings for variables
    def variable_fulfillment_query(pattern : AtomSpace::Atom) : Array(Hash(String, AtomSpace::Atom))
      groundings = [] of Hash(String, AtomSpace::Atom)

      # Extract variables from pattern
      variables = extract_variables(pattern)
      return groundings if variables.empty?

      # Search for matches in atomspace
      @atomspace.get_all_atoms.each do |atom|
        binding = unify_with_variables(pattern, atom, variables)
        groundings << binding if binding
      end

      groundings
    end

    # Truth value fulfillment query - update target truth values
    def truth_value_fulfillment_query(target : AtomSpace::Atom) : AtomSpace::TruthValue?
      chain_results = do_chain(target)
      return nil if chain_results.empty?

      # Aggregate truth values from inference paths
      strengths = chain_results.map(&.truth_value.strength)
      confidences = chain_results.map(&.truth_value.confidence)

      # Use revision formula for combining truth values
      combined_strength = strengths.sum / strengths.size
      combined_confidence = confidences.sum / confidences.size * 0.9 # Conservative confidence

      AtomSpace::SimpleTruthValue.new(combined_strength, combined_confidence)
    end

    private def termination_criteria_met? : Bool
      @current_iteration >= @max_iterations || all_nodes_exhausted?
    end

    private def all_nodes_exhausted? : Bool
      @inference_tree.all?(&.exhausted)
    end

    private def expand_inference_tree
      expandable_nodes = @inference_tree.reject(&.exhausted)
      return if expandable_nodes.empty?

      # Select best node for expansion based on fitness
      node_to_expand = select_best_expandable_node(expandable_nodes)
      expand_node(node_to_expand)
    end

    private def select_best_expandable_node(nodes : Array(BITNode)) : BITNode
      # Calculate fitness for each node
      nodes.each { |node| node.calculate_fitness(@atomspace) }

      # Select node with highest fitness
      nodes.max_by(&.fitness)
    end

    private def expand_node(node : BITNode)
      return if node.depth >= @max_depth

      applicable_rules = find_applicable_rules(node.target)

      if applicable_rules.empty?
        node.exhausted = true
        return
      end

      applicable_rules.each do |rule|
        # Create premise nodes for this rule
        premise_nodes = create_premise_nodes(rule, node.target, node.depth + 1)

        unless premise_nodes.empty?
          # Create a new inference branch
          branch_node = BITNode.new(node.target, node.depth)
          branch_node.rule = rule

          premise_nodes.each { |premise| branch_node.add_premise(premise) }
          @inference_tree.concat(premise_nodes)

          node.add_premise(branch_node)
        end
      end

      # Mark as exhausted if no valid expansions were created
      node.exhausted = true if node.premises.empty?
    end

    private def find_applicable_rules(target : AtomSpace::Atom) : Array(Rule)
      @rules.select do |rule|
        rule.conclusion == target.type || rule_can_generate(rule, target)
      end
    end

    private def rule_can_generate(rule : Rule, target : AtomSpace::Atom) : Bool
      # Check if rule can potentially generate the target
      # This is a simplified check - in practice would use more sophisticated unification
      rule.conclusion == target.type
    end

    private def create_premise_nodes(rule : Rule, target : AtomSpace::Atom, depth : Int32) : Array(BITNode)
      premise_nodes = [] of BITNode

      rule.premises.each do |premise_type|
        # Find or create atoms that could serve as premises
        potential_premises = find_potential_premises(rule, target, premise_type)

        potential_premises.each do |premise|
          premise_node = BITNode.new(premise, depth)
          premise_nodes << premise_node
        end
      end

      premise_nodes
    end

    private def find_potential_premises(rule : Rule, target : AtomSpace::Atom, premise_type : AtomSpace::AtomType) : Array(AtomSpace::Atom)
      # Look for existing atoms of the required type
      existing = @atomspace.get_atoms_by_type(premise_type)

      # Filter based on relevance to target
      relevant = existing.select { |atom| is_relevant_premise(atom, target, rule) }

      # If no existing relevant premises, create virtual premises for backward search
      if relevant.empty? && can_create_virtual_premise(rule, target, premise_type)
        relevant = create_virtual_premises(rule, target, premise_type)
      end

      relevant
    end

    private def is_relevant_premise(premise : AtomSpace::Atom, target : AtomSpace::Atom, rule : Rule) : Bool
      # Simple relevance check - could be much more sophisticated
      return true if premise.type == target.type

      # Check if they share common nodes
      premise_nodes = extract_nodes(premise)
      target_nodes = extract_nodes(target)

      !(premise_nodes & target_nodes).empty?
    end

    private def can_create_virtual_premise(rule : Rule, target : AtomSpace::Atom, premise_type : AtomSpace::AtomType) : Bool
      # Determine if we can create a virtual premise for backward search
      premise_type == AtomSpace::AtomType::INHERITANCE_LINK ||
        premise_type == AtomSpace::AtomType::IMPLICATION_LINK ||
        premise_type == AtomSpace::AtomType::EVALUATION_LINK
    end

    private def create_virtual_premises(rule : Rule, target : AtomSpace::Atom, premise_type : AtomSpace::AtomType) : Array(AtomSpace::Atom)
      # Create virtual premises based on target structure
      premises = [] of AtomSpace::Atom

      case premise_type
      when AtomSpace::AtomType::INHERITANCE_LINK
        if target.is_a?(AtomSpace::Link) && target.outgoing.size >= 2
          # Create intermediate inheritance links
          nodes = target.outgoing
          intermediate = @atomspace.add_concept_node("intermediate_#{nodes[0].name}")
          premises << @atomspace.add_inheritance_link(nodes[0], intermediate)
        end
      when AtomSpace::AtomType::IMPLICATION_LINK
        # Create conditional premises using general add_link method
        if target.is_a?(AtomSpace::Link)
          condition = @atomspace.add_concept_node("condition_#{target.name}")
          premises << @atomspace.add_link(AtomSpace::AtomType::IMPLICATION_LINK, [condition, target])
        end
      end

      premises
    end

    private def extract_nodes(atom : AtomSpace::Atom, visited : Set(UInt64)? = nil) : Array(AtomSpace::Atom)
      visited ||= Set(UInt64).new
      nodes = [] of AtomSpace::Atom

      return nodes if visited.includes?(atom.handle)
      visited.add(atom.handle)

      if atom.is_a?(AtomSpace::Node)
        nodes << atom
      elsif atom.is_a?(AtomSpace::Link)
        atom.outgoing.each { |child| nodes.concat(extract_nodes(child, visited)) }
      end

      nodes
    end

    private def fulfill_best_nodes
      # Find leaf nodes that can be fulfilled (have all premises satisfied)
      fulfillable_nodes = @inference_tree.select do |node|
        node.is_leaf? && @atomspace.contains?(node.target)
      end

      fulfillable_nodes.each { |node| fulfill_node(node) }
    end

    private def fulfill_node(node : BITNode)
      return if node.target.nil? || @atomspace.contains?(node.target)

      # Add the target to atomspace with inferred truth value
      tv = calculate_inferred_truth_value(node)
      node.target.truth_value = tv
      @atomspace.add_atom(node.target)
      node.results << node.target
    end

    private def calculate_inferred_truth_value(node : BITNode) : AtomSpace::TruthValue
      # Calculate truth value based on inference path
      if node.rule && !node.premises.empty?
        # Use rule-specific truth value calculation
        premise_atoms = node.premises.map(&.target)

        # Apply rule to get inferred strength and confidence
        strengths = premise_atoms.map(&.truth_value.strength)
        confidences = premise_atoms.map(&.truth_value.confidence)

        inferred_strength = strengths.min                              # Conservative estimate
        inferred_confidence = confidences.sum / confidences.size * 0.8 # Reduced confidence

        AtomSpace::SimpleTruthValue.new(inferred_strength, inferred_confidence)
      else
        node.target.truth_value
      end
    end

    private def collect_results : Array(AtomSpace::Atom)
      results = [] of AtomSpace::Atom

      @inference_tree.each do |node|
        results.concat(node.results)
        if @atomspace.contains?(node.target)
          results << node.target
        end
      end

      results.uniq
    end

    private def extract_variables(pattern : AtomSpace::Atom, visited : Set(UInt64)? = nil) : Array(String)
      visited ||= Set(UInt64).new
      variables = [] of String

      return variables if visited.includes?(pattern.handle)
      visited.add(pattern.handle)

      if pattern.is_a?(AtomSpace::Node) && pattern.name.starts_with?("$")
        variables << pattern.name
      elsif pattern.is_a?(AtomSpace::Link)
        pattern.outgoing.each { |child| variables.concat(extract_variables(child, visited)) }
      end

      variables.uniq
    end

    private def unify_with_variables(pattern : AtomSpace::Atom, candidate : AtomSpace::Atom, variables : Array(String)) : Hash(String, AtomSpace::Atom)?
      # Simplified unification - in practice would be much more sophisticated
      return nil unless pattern.type == candidate.type

      binding = {} of String => AtomSpace::Atom

      if pattern.is_a?(AtomSpace::Node) && variables.includes?(pattern.name)
        binding[pattern.name] = candidate
        return binding
      end

      if pattern.is_a?(AtomSpace::Link) && candidate.is_a?(AtomSpace::Link)
        return nil unless pattern.outgoing.size == candidate.outgoing.size

        pattern.outgoing.zip(candidate.outgoing) do |p, c|
          sub_binding = unify_with_variables(p, c, variables)
          return nil unless sub_binding
          binding.merge!(sub_binding)
        end

        return binding
      end

      # Exact match for non-variable nodes
      pattern == candidate ? binding : nil
    end

    # Advanced unification with proper variable handling
    private def atoms_unify?(atom1 : AtomSpace::Atom, atom2 : AtomSpace::Atom, depth : Int32 = 0) : Bool
      return false if depth > 100
      return true if atom1 == atom2

      # Handle variable unification
      if atom1.is_a?(AtomSpace::Node) && atom1.name.starts_with?("$")
        return true # Variable matches anything
      end

      if atom2.is_a?(AtomSpace::Node) && atom2.name.starts_with?("$")
        return true # Variable matches anything
      end

      # Structure unification for links
      if atom1.is_a?(AtomSpace::Link) && atom2.is_a?(AtomSpace::Link)
        return false unless atom1.type == atom2.type
        return false unless atom1.outgoing.size == atom2.outgoing.size

        atom1.outgoing.zip(atom2.outgoing) do |a, b|
          return false unless atoms_unify?(a, b, depth + 1)
        end

        return true
      end

      false
    end
  end

  # Mixed inference strategies for adaptive reasoning
  enum InferenceStrategy
    FORWARD_ONLY
    BACKWARD_ONLY
    MIXED_FORWARD_FIRST
    MIXED_BACKWARD_FIRST
    ADAPTIVE_BIDIRECTIONAL
  end

  # Performance metrics for strategy selection
  struct InferenceMetrics
    property atoms_generated : Int32
    property reasoning_time : Float64
    property goal_achieved : Bool
    property confidence_improvement : Float64

    def initialize
      @atoms_generated = 0
      @reasoning_time = 0.0
      @goal_achieved = false
      @confidence_improvement = 0.0
    end

    def efficiency_score : Float64
      return 0.0 if @reasoning_time <= 0.0

      base_score = @atoms_generated.to_f / @reasoning_time
      goal_bonus = @goal_achieved ? 1.5 : 1.0
      confidence_bonus = 1.0 + @confidence_improvement

      base_score * goal_bonus * confidence_bonus
    end
  end

  # Advanced mixed inference engine with adaptive strategy selection
  class MixedInferenceEngine
    @forward_chainer : ForwardChainer
    @backward_chainer : BackwardChainer
    @strategy_history : Hash(InferenceStrategy, Array(InferenceMetrics))
    @current_strategy : InferenceStrategy
    @adaptive_threshold : Float64

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @forward_chainer = ForwardChainer.new(@atomspace)
      @backward_chainer = BackwardChainer.new(@atomspace)
      @strategy_history = Hash(InferenceStrategy, Array(InferenceMetrics)).new
      @current_strategy = InferenceStrategy::ADAPTIVE_BIDIRECTIONAL
      @adaptive_threshold = 0.7

      # Initialize strategy history
      InferenceStrategy.each do |strategy|
        @strategy_history[strategy] = [] of InferenceMetrics
      end

      # Add default rules
      @forward_chainer.add_default_rules
      @backward_chainer.add_default_rules
    end

    def add_rule(rule : Rule)
      @forward_chainer.add_rule(rule)
      @backward_chainer.add_rule(rule)
    end

    # Adaptive mixed inference with strategy selection
    def adaptive_chain(goal : AtomSpace::Atom, max_time : Float64 = 30.0) : Array(AtomSpace::Atom)
      start_time = Time.instant
      initial_confidence = goal.truth_value.confidence

      # Select optimal strategy based on historical performance
      selected_strategy = select_optimal_strategy(goal)

      # Execute inference with selected strategy
      results = execute_strategy(selected_strategy, goal, max_time)

      # Record performance metrics
      elapsed_time = (Time.instant - start_time).total_seconds
      record_performance(selected_strategy, results, elapsed_time, goal, initial_confidence)

      results
    end

    # Execute specific inference strategy
    def execute_strategy(strategy : InferenceStrategy, goal : AtomSpace::Atom, max_time : Float64) : Array(AtomSpace::Atom)
      case strategy
      when .forward_only?
        execute_forward_only(goal, max_time)
      when .backward_only?
        execute_backward_only(goal, max_time)
      when .mixed_forward_first?
        execute_mixed_forward_first(goal, max_time)
      when .mixed_backward_first?
        execute_mixed_backward_first(goal, max_time)
      when .adaptive_bidirectional?
        execute_adaptive_bidirectional(goal, max_time)
      else
        [] of AtomSpace::Atom
      end
    end

    private def select_optimal_strategy(goal : AtomSpace::Atom) : InferenceStrategy
      # Analyze goal characteristics
      goal_complexity = analyze_goal_complexity(goal)
      atomspace_density = @atomspace.size.to_f / 1000.0 # Normalized density metric

      # If we have enough historical data, use performance-based selection
      if has_sufficient_history?
        return select_by_performance
      end

      # Heuristic-based selection for new goals
      select_by_heuristics(goal_complexity, atomspace_density)
    end

    private def analyze_goal_complexity(goal : AtomSpace::Atom) : Float64
      # Calculate complexity based on structure depth and variable count
      structure_depth = calculate_structure_depth(goal)
      variable_count = count_variables(goal)

      base_complexity = structure_depth * 0.3 + variable_count * 0.2

      # Consider goal type complexity
      type_complexity = case goal.type
                        when AtomSpace::AtomType::INHERITANCE_LINK then 0.1
                        when AtomSpace::AtomType::IMPLICATION_LINK then 0.3
                        when AtomSpace::AtomType::AND_LINK         then 0.4
                        when AtomSpace::AtomType::OR_LINK          then 0.5
                        else                                            0.2
                        end

      base_complexity + type_complexity
    end

    private def calculate_structure_depth(atom : AtomSpace::Atom, current_depth = 0, visited : Set(UInt64)? = nil) : Int32
      return current_depth if atom.is_a?(AtomSpace::Node)
      return current_depth if current_depth > 100

      visited ||= Set(UInt64).new
      return current_depth if visited.includes?(atom.handle)
      visited.add(atom.handle)

      if atom.is_a?(AtomSpace::Link)
        max_child_depth = atom.outgoing.map { |child| calculate_structure_depth(child, current_depth + 1, visited) }.max? || current_depth
        return max_child_depth
      end

      current_depth
    end

    private def count_variables(atom : AtomSpace::Atom) : Int32
      if atom.is_a?(AtomSpace::Node) && atom.name.starts_with?("$")
        return 1
      elsif atom.is_a?(AtomSpace::Link)
        return atom.outgoing.sum { |child| count_variables(child) }
      end

      0
    end

    private def has_sufficient_history? : Bool
      @strategy_history.values.any? { |metrics| metrics.size >= 3 }
    end

    private def select_by_performance : InferenceStrategy
      best_strategy = InferenceStrategy::ADAPTIVE_BIDIRECTIONAL
      best_score = 0.0

      @strategy_history.each do |strategy, metrics|
        next if metrics.empty?

        # Calculate average efficiency score
        avg_score = metrics.sum(&.efficiency_score) / metrics.size

        if avg_score > best_score
          best_score = avg_score
          best_strategy = strategy
        end
      end

      best_strategy
    end

    private def select_by_heuristics(goal_complexity : Float64, atomspace_density : Float64) : InferenceStrategy
      # Use heuristics based on problem characteristics
      if goal_complexity < 0.3 && atomspace_density > 0.5
        # Simple goal with rich knowledge base - forward chaining likely effective
        InferenceStrategy::MIXED_FORWARD_FIRST
      elsif goal_complexity > 0.7 || atomspace_density < 0.2
        # Complex goal or sparse knowledge - backward chaining more targeted
        InferenceStrategy::MIXED_BACKWARD_FIRST
      else
        # Medium complexity - use bidirectional approach
        InferenceStrategy::ADAPTIVE_BIDIRECTIONAL
      end
    end

    private def execute_forward_only(goal : AtomSpace::Atom, max_time : Float64) : Array(AtomSpace::Atom)
      results = @forward_chainer.run
      results.select { |atom| atoms_relate_to_goal?(atom, goal) }
    end

    private def execute_backward_only(goal : AtomSpace::Atom, max_time : Float64) : Array(AtomSpace::Atom)
      @backward_chainer.do_chain(goal)
    end

    private def execute_mixed_forward_first(goal : AtomSpace::Atom, max_time : Float64) : Array(AtomSpace::Atom)
      start_time = Time.instant

      # Forward phase (60% of time budget)
      forward_time_budget = max_time * 0.6
      forward_results = @forward_chainer.run

      elapsed = (Time.instant - start_time).total_seconds
      remaining_time = max_time - elapsed

      # Backward phase with remaining time
      if remaining_time > 0.1
        backward_results = @backward_chainer.do_chain(goal)
        return (forward_results + backward_results).uniq
      end

      forward_results
    end

    private def execute_mixed_backward_first(goal : AtomSpace::Atom, max_time : Float64) : Array(AtomSpace::Atom)
      start_time = Time.instant

      # Backward phase (60% of time budget)
      backward_results = @backward_chainer.do_chain(goal)

      elapsed = (Time.instant - start_time).total_seconds
      remaining_time = max_time - elapsed

      # Forward phase with remaining time
      if remaining_time > 0.1 && backward_results.empty?
        forward_results = @forward_chainer.run
        relevant_forward = forward_results.select { |atom| atoms_relate_to_goal?(atom, goal) }
        return (backward_results + relevant_forward).uniq
      end

      backward_results
    end

    private def execute_adaptive_bidirectional(goal : AtomSpace::Atom, max_time : Float64) : Array(AtomSpace::Atom)
      @forward_chainer.clear_seen_results
      start_time = Time.instant
      forward_results = [] of AtomSpace::Atom
      backward_results = [] of AtomSpace::Atom

      # Interleave forward and backward steps
      time_per_phase = max_time / 6.0 # 3 forward + 3 backward phases

      3.times do |phase|
        break if (Time.instant - start_time).total_seconds >= max_time

        # Forward step
        phase_start = Time.instant
        step_results = @forward_chainer.step_forward
        forward_results.concat(step_results)

        # Backward step
        elapsed_phase = (Time.instant - phase_start).total_seconds
        if elapsed_phase < time_per_phase
          step_backward_results = @backward_chainer.do_chain(goal)
          backward_results.concat(step_backward_results)

          # Early termination if goal achieved
          break if backward_results.any? { |atom| atoms_unify?(atom, goal) }
        end

        break if (Time.instant - start_time).total_seconds >= max_time
      end

      (forward_results + backward_results).uniq
    end

    private def atoms_relate_to_goal?(atom : AtomSpace::Atom, goal : AtomSpace::Atom) : Bool
      # Check if atom is related to the goal (shares common elements)
      return true if atoms_unify?(atom, goal)

      atom_nodes = extract_nodes(atom)
      goal_nodes = extract_nodes(goal)

      # Check for shared nodes
      !(atom_nodes & goal_nodes).empty?
    end

    private def extract_nodes(atom : AtomSpace::Atom, visited : Set(UInt64)? = nil) : Array(AtomSpace::Atom)
      visited ||= Set(UInt64).new
      nodes = [] of AtomSpace::Atom

      return nodes if visited.includes?(atom.handle)
      visited.add(atom.handle)

      if atom.is_a?(AtomSpace::Node)
        nodes << atom
      elsif atom.is_a?(AtomSpace::Link)
        atom.outgoing.each { |child| nodes.concat(extract_nodes(child, visited)) }
      end

      nodes
    end

    private def atoms_unify?(atom1 : AtomSpace::Atom, atom2 : AtomSpace::Atom, depth : Int32 = 0) : Bool
      return false if depth > 100
      return true if atom1 == atom2

      # Handle variable unification
      if atom1.is_a?(AtomSpace::Node) && atom1.name.starts_with?("$")
        return true
      end

      if atom2.is_a?(AtomSpace::Node) && atom2.name.starts_with?("$")
        return true
      end

      # Structure unification for links
      if atom1.is_a?(AtomSpace::Link) && atom2.is_a?(AtomSpace::Link)
        return false unless atom1.type == atom2.type
        return false unless atom1.outgoing.size == atom2.outgoing.size

        atom1.outgoing.zip(atom2.outgoing) do |a, b|
          return false unless atoms_unify?(a, b, depth + 1)
        end

        return true
      end

      false
    end

    private def record_performance(strategy : InferenceStrategy, results : Array(AtomSpace::Atom),
                                   elapsed_time : Float64, goal : AtomSpace::Atom, initial_confidence : Float64)
      metrics = InferenceMetrics.new
      metrics.atoms_generated = results.size
      metrics.reasoning_time = elapsed_time
      metrics.goal_achieved = results.any? { |atom| atoms_unify?(atom, goal) }
      metrics.confidence_improvement = goal.truth_value.confidence - initial_confidence

      @strategy_history[strategy] << metrics

      # Keep history size manageable (last 10 runs per strategy)
      if @strategy_history[strategy].size > 10
        @strategy_history[strategy] = @strategy_history[strategy].last(10)
      end

      CogUtil::Logger.debug("URE: Strategy #{strategy} completed in #{elapsed_time}s, generated #{results.size} atoms, goal achieved: #{metrics.goal_achieved}")
    end
  end

  # Main URE engine combining forward and backward chaining with mixed inference
  class UREEngine
    getter forward_chainer : ForwardChainer
    getter backward_chainer : BackwardChainer
    getter mixed_engine : MixedInferenceEngine

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @forward_chainer = ForwardChainer.new(@atomspace)
      @backward_chainer = BackwardChainer.new(@atomspace)
      @mixed_engine = MixedInferenceEngine.new(@atomspace)

      # Add default rules
      @forward_chainer.add_default_rules
      @backward_chainer.add_default_rules
    end

    def add_rule(rule : Rule)
      @forward_chainer.add_rule(rule)
      @backward_chainer.add_rule(rule)
      @mixed_engine.add_rule(rule)
    end

    def forward_chain(steps : Int32 = 10) : Array(AtomSpace::Atom)
      @forward_chainer.run
    end

    def backward_chain(goal : AtomSpace::Atom) : Bool
      results = @backward_chainer.do_chain(goal)
      !results.empty?
    end

    # Simple mixed chaining for compatibility
    def mixed_chain(goal : AtomSpace::Atom, forward_steps : Int32 = 5) : Bool
      # Try forward chaining first
      forward_chain(forward_steps)

      # Then backward chain to goal
      backward_chain(goal)
    end

    # Advanced mixed inference with adaptive strategy selection
    def adaptive_mixed_chain(goal : AtomSpace::Atom, max_time : Float64 = 30.0) : Array(AtomSpace::Atom)
      @mixed_engine.adaptive_chain(goal, max_time)
    end

    # Execute specific inference strategy
    def execute_strategy(strategy : InferenceStrategy, goal : AtomSpace::Atom, max_time : Float64 = 30.0) : Array(AtomSpace::Atom)
      @mixed_engine.execute_strategy(strategy, goal, max_time)
    end
  end

  # Initialize URE module
  def self.initialize
    CogUtil::Logger.info("URE #{VERSION} initialized")
  end

  # Convenience method to create URE engine
  def self.create_engine(atomspace : AtomSpace::AtomSpace) : UREEngine
    UREEngine.new(atomspace)
  end
end
