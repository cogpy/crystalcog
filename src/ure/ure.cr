# Crystal implementation of URE (Unified Rule Engine)
# Converted from ure/opencog/ure/

require "../atomspace/atomspace_main"
require "../cogutil/cogutil"

module URE
  VERSION = "0.1.0"

  # What each variable stands for, by variable name. A value may contain
  # other variables; `Unifier.resolve` follows them through.
  alias Bindings = Hash(String, AtomSpace::Atom)

  # First-order unification of atoms.
  #
  # A variable is a node whose name starts with `$`, of any node type, and
  # is identified by its name. Either side may contain variables. A
  # variable keeps one value throughout, and cannot be bound to a term
  # that contains it (the occurs check), so `$X` never unifies with
  # `List($X, a)`.
  module Unifier
    def self.variable?(atom : AtomSpace::Atom) : Bool
      atom.is_a?(AtomSpace::Node) && atom.name.starts_with?("$")
    end

    # The names of the variables in an atom, in order of first appearance.
    def self.variables(atom : AtomSpace::Atom) : Array(String)
      names = [] of String
      collect_variables(atom, names)
      names
    end

    private def self.collect_variables(atom : AtomSpace::Atom, names : Array(String)) : Nil
      if variable?(atom)
        names << atom.name unless names.includes?(atom.name)
      elsif atom.is_a?(AtomSpace::Link)
        atom.outgoing.each { |child| collect_variables(child, names) }
      end
    end

    def self.ground?(atom : AtomSpace::Atom) : Bool
      return false if variable?(atom)
      return true unless atom.is_a?(AtomSpace::Link)
      atom.outgoing.all? { |child| ground?(child) }
    end

    # The most general set of bindings that makes `a` and `b` the same
    # atom, extending `bindings`; nil when there is none. `bindings` itself
    # is left as it was.
    def self.unify(a : AtomSpace::Atom, b : AtomSpace::Atom, bindings : Bindings = Bindings.new) : Bindings?
      result = bindings.dup
      unify_into(a, b, result) ? result : nil
    end

    private def self.unify_into(a : AtomSpace::Atom, b : AtomSpace::Atom, bindings : Bindings) : Bool
      a = walk(a, bindings)
      b = walk(b, bindings)

      if variable?(a)
        return true if variable?(b) && a.name == b.name
        return bind(a.name, b, bindings)
      end
      return bind(b.name, a, bindings) if variable?(b)

      if a.is_a?(AtomSpace::Link) && b.is_a?(AtomSpace::Link)
        return false unless a.type == b.type
        left = a.outgoing
        right = b.outgoing
        return false unless left.size == right.size
        left.each_with_index do |child, i|
          return false unless unify_into(child, right[i], bindings)
        end
        return true
      end

      a == b
    end

    # Follow a bound variable to what it currently stands for.
    private def self.walk(atom : AtomSpace::Atom, bindings : Bindings) : AtomSpace::Atom
      while variable?(atom)
        bound = bindings[atom.name]? || break
        atom = bound
      end
      atom
    end

    private def self.bind(name : String, value : AtomSpace::Atom, bindings : Bindings) : Bool
      return false if occurs?(name, value, bindings)
      bindings[name] = value
      true
    end

    private def self.occurs?(name : String, atom : AtomSpace::Atom, bindings : Bindings) : Bool
      atom = walk(atom, bindings)
      return atom.name == name if variable?(atom)
      return false unless atom.is_a?(AtomSpace::Link)
      atom.outgoing.any? { |child| occurs?(name, child, bindings) }
    end

    # The atom with every bound variable replaced by its value, all the way
    # down. Unbound variables stay. Links are rebuilt only where something
    # changed.
    def self.resolve(atom : AtomSpace::Atom, bindings : Bindings) : AtomSpace::Atom
      atom = walk(atom, bindings)
      return atom unless atom.is_a?(AtomSpace::Link)

      children = atom.outgoing
      resolved = children.map { |child| resolve(child, bindings) }
      unchanged = resolved.each_with_index.all? { |child, i| child.same?(children[i]) }
      unchanged ? atom : AtomSpace::Link.new(atom.type, resolved, atom.truth_value)
    end

    def self.unifiable?(a : AtomSpace::Atom, b : AtomSpace::Atom) : Bool
      !unify(a, b).nil?
    end

    # The atom with `suffix` added to the name of every variable, so that
    # a rule's `$A` is not taken for the `$A` of a goal it is tried on.
    def self.rename(atom : AtomSpace::Atom, suffix : String) : AtomSpace::Atom
      if variable?(atom)
        AtomSpace::Node.new(atom.type, atom.name + suffix).as(AtomSpace::Atom)
      elsif atom.is_a?(AtomSpace::Link)
        children = atom.outgoing
        renamed = children.map { |child| rename(child, suffix) }
        unchanged = renamed.each_with_index.all? { |child, i| child.same?(children[i]) }
        unchanged ? atom : AtomSpace::Link.new(atom.type, renamed, atom.truth_value).as(AtomSpace::Atom)
      else
        atom
      end
    end
  end

  # Generic rule interface for URE
  abstract class Rule
    abstract def name : String
    abstract def premises : Array(AtomSpace::AtomType)
    abstract def conclusion : AtomSpace::AtomType
    abstract def apply(premises : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
    abstract def fitness(premises : Array(AtomSpace::Atom)) : Float64

    # The shapes of the premises, in the order `apply` takes them, with
    # `$variables` where any atom may stand and the same variable where
    # the same atom must. A rule that declares them is offered only the
    # atoms that fit together, and is chosen for a goal only when its
    # conclusion can be that goal. nil: the rule declares types alone.
    def premise_patterns : Array(AtomSpace::Atom)?
      nil
    end

    # The shape of the conclusion, in the variables of the premises.
    def conclusion_pattern : AtomSpace::Atom?
      nil
    end
  end

  # Finds what a rule's patterns fit.
  module RuleMatcher
    # The bindings under which these atoms are the rule's premises, in
    # order; nil when they do not fit together.
    def self.match(patterns : Array(AtomSpace::Atom), atoms : Array(AtomSpace::Atom)) : Bindings?
      return nil unless patterns.size == atoms.size
      bindings = Bindings.new
      patterns.each_with_index do |pattern, i|
        bindings = Unifier.unify(pattern, atoms[i], bindings) || return nil
      end
      bindings
    end

    # Every way the ground atoms of an AtomSpace satisfy the patterns
    # together, as the atoms in pattern order, up to `limit`. The block
    # says whether a found application is wanted; ones it turns down do
    # not count toward the limit. An atom is used for one premise only.
    def self.applications(patterns : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace, limit : Int32,
                          & : Array(AtomSpace::Atom) -> Bool) : Array(Array(AtomSpace::Atom))
      found = [] of Array(AtomSpace::Atom)
      return found if patterns.empty?
      # Explicit stack: premise index, bindings so far, atoms chosen so far.
      pending = [{0, Bindings.new, [] of AtomSpace::Atom}]
      while state = pending.pop?
        index, bindings, chosen = state
        if index == patterns.size
          found << chosen if yield chosen
          return found if found.size >= limit
          next
        end

        goal = Unifier.resolve(patterns[index], bindings)
        # Pushed in reverse so that applications come out in AtomSpace order.
        candidates(goal, atomspace).reverse_each do |atom|
          next if chosen.any?(&.same?(atom))
          next unless Unifier.ground?(atom)
          extended = Unifier.unify(goal, atom, bindings) || next
          pending << {index + 1, extended, chosen + [atom]}
        end
      end
      found
    end

    # The atoms a pattern could be: those of its type, or when one of its
    # parts is already an atom of the AtomSpace, only the links that part
    # is in. The part in the fewest links narrows the most.
    def self.candidates(goal : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      if goal.is_a?(AtomSpace::Link)
        narrowest = nil
        goal.outgoing.each do |child|
          next unless Unifier.ground?(child)
          known = canonical(child, atomspace) || return [] of AtomSpace::Atom
          incoming = known.incoming
          narrowest = incoming if narrowest.nil? || incoming.size < narrowest.size
        end
        return narrowest.select { |atom| atom.type == goal.type } if narrowest
      end
      atomspace.get_atoms_by_type(goal.type)
    end

    # The AtomSpace's own atom for a ground atom, if it has one.
    def self.canonical(atom : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      if atom.is_a?(AtomSpace::Link)
        children = [] of AtomSpace::Atom
        atom.outgoing.each { |child| children << (canonical(child, atomspace) || return nil) }
        atomspace.find_link(atom.type, children)
      else
        atomspace.get_nodes_by_name(atom.name, atom.type).first?
      end
    end

    # Put a ground atom into the AtomSpace with a truth value. Its parts
    # are looked up first, so that what is there keeps its truth value.
    def self.intern(atom : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, tv : AtomSpace::TruthValue) : AtomSpace::Atom
      if atom.is_a?(AtomSpace::Link)
        atomspace.add_link(atom.type, atom.outgoing.map { |child| intern_part(child, atomspace) }, tv)
      else
        atomspace.add_node(atom.type, atom.name, tv)
      end
    end

    private def self.intern_part(atom : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom
      if atom.is_a?(AtomSpace::Link)
        children = atom.outgoing.map { |child| intern_part(child, atomspace) }
        atomspace.find_link(atom.type, children) || atomspace.add_link(atom.type, children)
      else
        atomspace.get_nodes_by_name(atom.name, atom.type).first? || atomspace.add_node(atom.type, atom.name)
      end
    end
  end

  # A rule given by the shapes of its premises and of its conclusion:
  #
  #   PatternRule.new("grandparent",
  #     [parent($X, $Y), parent($Y, $Z)],     # premises
  #     grandparent($X, $Z))                  # conclusion
  #
  # The chainers apply it wherever atoms fit the premises together, and
  # choose it for a goal the conclusion unifies with. The block computes
  # the conclusion's truth value from those of the premises; without one
  # strengths and confidences are multiplied, and confidence loses a tenth.
  class PatternRule < Rule
    getter name : String
    getter premise_patterns : Array(AtomSpace::Atom)
    getter conclusion_pattern : AtomSpace::Atom

    def initialize(@name : String, @premise_patterns : Array(AtomSpace::Atom), @conclusion_pattern : AtomSpace::Atom,
                   &@formula : Array(AtomSpace::TruthValue) -> AtomSpace::TruthValue)
      raise ArgumentError.new("#{@name}: a rule needs a premise") if @premise_patterns.empty?
      if @premise_patterns.any? { |pattern| Unifier.variable?(pattern) }
        raise ArgumentError.new("#{@name}: a premise cannot be a bare variable")
      end
      known = @premise_patterns.flat_map { |pattern| Unifier.variables(pattern) }
      loose = Unifier.variables(@conclusion_pattern) - known
      unless loose.empty?
        raise ArgumentError.new("#{@name}: #{loose.join(", ")} in the conclusion is in no premise")
      end
    end

    def self.new(name : String, premise_patterns : Array(AtomSpace::Atom), conclusion_pattern : AtomSpace::Atom) : PatternRule
      new(name, premise_patterns, conclusion_pattern) do |values|
        strength = values.product(1.0, &.strength)
        confidence = values.product(1.0, &.confidence) * 0.9
        AtomSpace::SimpleTruthValue.new(strength, confidence).as(AtomSpace::TruthValue)
      end
    end

    def premises : Array(AtomSpace::AtomType)
      @premise_patterns.map(&.type)
    end

    def conclusion : AtomSpace::AtomType
      @conclusion_pattern.type
    end

    def apply(premises : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      bindings = RuleMatcher.match(@premise_patterns, premises) || return nil
      concluded = Unifier.resolve(@conclusion_pattern, bindings)
      return nil unless Unifier.ground?(concluded)
      # A conclusion that is one of its own premises says nothing new.
      return nil if premises.any? { |premise| premise.type == concluded.type && premise.to_s == concluded.to_s }
      RuleMatcher.intern(concluded, atomspace, @formula.call(premises.map(&.truth_value)))
    end

    def fitness(premises : Array(AtomSpace::Atom)) : Float64
      return 0.0 if premises.empty?
      premises.sum(&.truth_value.confidence) / premises.size
    end
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
      # Do not conjoin open patterns containing free variables
      return nil if premises.any? { |p| contains_variable?(p) }

      # Calculate conjunction truth value
      min_strength = premises.map(&.truth_value.strength).min
      min_confidence = premises.map(&.truth_value.confidence).min

      tv = AtomSpace::SimpleTruthValue.new(min_strength, min_confidence * 0.9)

      # Create AND link
      atomspace.add_link(AtomSpace::AtomType::AND_LINK, premises, tv)
    end

    def fitness(premises : Array(AtomSpace::Atom)) : Float64
      return 0.0 if premises.any? { |p| contains_variable?(p) }
      # Fitness based on truth value confidence
      premises.map(&.truth_value.confidence).sum / premises.size
    end

    private def contains_variable?(atom : AtomSpace::Atom) : Bool
      visited = Set(UInt64).new
      stack = [atom]
      while node = stack.pop?
        next unless visited.add?(node.handle)
        return true if node.type == AtomSpace::AtomType::VARIABLE_NODE
        next unless node.is_a?(AtomSpace::Link)
        node.outgoing.each { |child| stack << child }
      end
      false
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

    # A->B and B->C give A->C.
    PATTERNS = begin
      a, b, c = {"$A", "$B", "$C"}.map { |name| AtomSpace::VariableNode.new(name).as(AtomSpace::Atom) }
      inherits = ->(child : AtomSpace::Atom, parent : AtomSpace::Atom) {
        AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [child, parent]).as(AtomSpace::Atom)
      }
      {[inherits.call(a, b), inherits.call(b, c)], inherits.call(a, c)}
    end

    def premise_patterns : Array(AtomSpace::Atom)?
      PATTERNS[0]
    end

    def conclusion_pattern : AtomSpace::Atom?
      PATTERNS[1]
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

      # Exact match (ground implication)
      if antecedent == if_part
        tv_impl = implication.truth_value
        tv_ante = antecedent.truth_value
        new_strength = [tv_ante.strength, tv_impl.strength].min
        new_confidence = tv_ante.confidence * tv_impl.confidence * 0.95
        tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

        if then_part.is_a?(AtomSpace::EvaluationLink)
          return atomspace.add_evaluation_link(then_part.predicate, then_part.arguments, tv)
        end

        then_part.truth_value = tv
        return then_part
      end

      # Pattern implication: Implication(Evaluation(P, vars), Evaluation(Q, vars))
      # grounded by Evaluation(P, constants)
      return nil unless if_part.is_a?(AtomSpace::EvaluationLink)
      return nil unless then_part.is_a?(AtomSpace::EvaluationLink)
      return nil unless antecedent.is_a?(AtomSpace::EvaluationLink)

      # Same predicate on the antecedent side
      return nil unless if_part.predicate == antecedent.predicate

      bindings = unify_atoms(if_part.arguments, antecedent.arguments)
      return nil if bindings.nil?

      grounded_args = substitute_bindings(then_part.arguments, bindings, atomspace)
      return nil unless grounded_args

      tv_impl = implication.truth_value
      tv_ante = antecedent.truth_value
      new_strength = [tv_ante.strength, tv_impl.strength].min
      new_confidence = tv_ante.confidence * tv_impl.confidence * 0.95
      tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

      atomspace.add_evaluation_link(then_part.predicate, grounded_args, tv)
    end

    def fitness(premises : Array(AtomSpace::Atom)) : Float64
      premises.map(&.truth_value.strength).min
    end

    # Unify pattern atom against ground atom; returns variable bindings or nil
    private def unify_atoms(pattern : AtomSpace::Atom, ground : AtomSpace::Atom) : Hash(String, AtomSpace::Atom)?
      bindings = {} of String => AtomSpace::Atom
      return nil unless unify(pattern, ground, bindings)
      bindings
    end

    private def unify(pattern : AtomSpace::Atom, ground : AtomSpace::Atom, bindings : Hash(String, AtomSpace::Atom)) : Bool
      if pattern.type == AtomSpace::AtomType::VARIABLE_NODE && pattern.is_a?(AtomSpace::Node)
        name = pattern.name
        if existing = bindings[name]?
          return existing == ground
        end
        bindings[name] = ground
        return true
      end

      return false unless pattern.type == ground.type

      if pattern.is_a?(AtomSpace::Link) && ground.is_a?(AtomSpace::Link)
        return false unless pattern.outgoing.size == ground.outgoing.size
        pattern.outgoing.zip(ground.outgoing).each do |p, g|
          return false unless unify(p, g, bindings)
        end
        return true
      end

      # Ground nodes must match by identity or name
      if pattern.is_a?(AtomSpace::Node) && ground.is_a?(AtomSpace::Node)
        return pattern.name == ground.name
      end

      pattern == ground
    end

    private def substitute_bindings(atom : AtomSpace::Atom, bindings : Hash(String, AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      if atom.type == AtomSpace::AtomType::VARIABLE_NODE && atom.is_a?(AtomSpace::Node)
        return bindings[atom.name]?
      end

      if atom.is_a?(AtomSpace::Link)
        new_outgoing = atom.outgoing.map do |child|
          substituted = substitute_bindings(child, bindings, atomspace)
          return nil unless substituted
          substituted
        end

        case atom.type
        when AtomSpace::AtomType::LIST_LINK
          atomspace.add_list_link(new_outgoing)
        when AtomSpace::AtomType::EVALUATION_LINK
          return nil unless new_outgoing.size == 2
          atomspace.add_evaluation_link(new_outgoing[0], new_outgoing[1])
        else
          atomspace.add_link(atom.type, new_outgoing)
        end
      else
        atom
      end
    end
  end

  # Transitive closure over binary EvaluationLinks sharing a predicate:
  # Evaluation(P, [A,B]) & Evaluation(P, [B,C]) => Evaluation(P, [A,C])
  class EvaluationTransitivityRule < Rule
    def name : String
      "EvaluationTransitivityRule"
    end

    def premises : Array(AtomSpace::AtomType)
      [AtomSpace::AtomType::EVALUATION_LINK, AtomSpace::AtomType::EVALUATION_LINK]
    end

    def conclusion : AtomSpace::AtomType
      AtomSpace::AtomType::EVALUATION_LINK
    end

    def apply(premises : Array(AtomSpace::Atom), atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premises.size == 2

      link1, link2 = premises[0], premises[1]
      return nil unless link1.is_a?(AtomSpace::EvaluationLink)
      return nil unless link2.is_a?(AtomSpace::EvaluationLink)
      return nil unless link1.predicate == link2.predicate

      args1 = link1.arguments
      args2 = link2.arguments
      return nil unless args1.is_a?(AtomSpace::ListLink) && args2.is_a?(AtomSpace::ListLink)
      return nil unless args1.outgoing.size == 2 && args2.outgoing.size == 2

      a, b = args1.outgoing[0], args1.outgoing[1]
      b2, c = args2.outgoing[0], args2.outgoing[1]
      return nil unless b == b2
      return nil if a == c

      tv1, tv2 = link1.truth_value, link2.truth_value
      new_strength = tv1.strength * tv2.strength
      new_confidence = tv1.confidence * tv2.confidence * 0.9
      tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

      predicate = link1.predicate
      # Derive "above" from stacked "on" relations for spatial reasoning
      if predicate.responds_to?(:name) && predicate.name == "on"
        above = atomspace.add_predicate_node("above")
        return atomspace.add_evaluation_link(above, atomspace.add_list_link([a, c]), tv)
      end

      atomspace.add_evaluation_link(predicate, atomspace.add_list_link([a, c]), tv)
    end

    def fitness(premises : Array(AtomSpace::Atom)) : Float64
      premises.map(&.truth_value.confidence).sum / premises.size
    end
  end

  # Forward chainer for URE
  class ForwardChainer
    @rules : Array(Rule)
    @max_iterations : Int32
    # Handles of conclusions already produced. Results come back canonical from
    # the AtomSpace, so the handle identifies the conclusion without rendering it.
    @seen_results : Set(AtomSpace::Handle)
    # Applications of pattern rules already made, as the rule and its
    # premises. Each is made once, so a later step moves on to others.
    @tried : Set({Int32, Array(AtomSpace::Handle)})
    MAX_APPLICATIONS_PER_RULE = 500

    def initialize(@atomspace : AtomSpace::AtomSpace, @max_iterations = 100)
      @rules = [] of Rule
      @seen_results = Set(AtomSpace::Handle).new
      @tried = Set({Int32, Array(AtomSpace::Handle)}).new
    end

    def add_rule(rule : Rule)
      @rules << rule
    end

    def clear_seen_results
      @seen_results.clear
      @tried.clear
    end

    def add_default_rules
      add_rule(ConjunctionRule.new)
      add_rule(ModusPonensRule.new)
      add_rule(InheritanceTransitivityRule.new)
      add_rule(EvaluationTransitivityRule.new)
    end

    def run(max_iterations : Int32 = @max_iterations) : Array(AtomSpace::Atom)
      @seen_results.clear
      @tried.clear
      new_atoms = [] of AtomSpace::Atom
      iterations = 0

      while iterations < max_iterations
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

          # Track size so we only count atoms actually created by apply.
          # Rules add results into the atomspace, so contains?(result) is
          # true afterwards and must not be used as a "new atom" check.
          size_before = @atomspace.size
          result = rule.apply(premises, @atomspace)
          if result && @atomspace.size > size_before
            next unless @seen_results.add?(result.handle)
            step_atoms << result
            CogUtil::Logger.debug("URE: Applied #{rule.name}, fitness: #{fitness}")
          elsif result
            # Already-present conclusion — mark seen so we do not reapply forever
            @seen_results.add(result.handle)
          end
        end
      end

      step_atoms
    end

    private def find_rule_applications(rule : Rule) : Array(Array(AtomSpace::Atom))
      # A rule that says what its premises look like gets the atoms that
      # fit, found by unification, and each such application once.
      if patterns = rule.premise_patterns
        index = @rules.index(rule) || 0
        return RuleMatcher.applications(patterns, @atomspace, MAX_APPLICATIONS_PER_RULE) do |premises|
          @tried.add?({index, premises.map(&.handle)})
        end
      end

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

    # Rule expansions one proof search may make.
    PROOF_BUDGET = 20_000

    # Prove a goal from the AtomSpace with the rules that declare
    # patterns, working back from the goal: a rule is tried when its
    # conclusion unifies with the goal, and its premises become goals in
    # turn. The goal may contain variables. Every conclusion reached on
    # the way is added to the AtomSpace by the rule that draws it.
    #
    # Returns one entry per proof found: the atom proved and the values
    # of the goal's variables. A goal that is in the AtomSpace already is
    # its own proof.
    def prove(goal : AtomSpace::Atom) : Array({AtomSpace::Atom, Bindings})
      @expansions = 0
      names = Unifier.variables(goal)
      solve(goal, Bindings.new, 0, [] of String).map do |(atom, bindings)|
        {atom, names.to_h { |name| {name, Unifier.resolve(bindings[name], bindings)} }}
      end
    end

    @expansions = 0
    @renamings = 0

    # Proofs of `goal` under `bindings`: the atom and the bindings extended.
    private def solve(goal : AtomSpace::Atom, bindings : Bindings, depth : Int32,
                      path : Array(String)) : Array({AtomSpace::Atom, Bindings})
      goal = Unifier.resolve(goal, bindings)
      proofs = [] of {AtomSpace::Atom, Bindings}
      proved = Set(AtomSpace::Handle).new

      RuleMatcher.candidates(goal, @atomspace).each do |atom|
        next unless Unifier.ground?(atom)
        extended = Unifier.unify(goal, atom, bindings) || next
        proofs << {atom, extended} if proved.add?(atom.handle)
      end
      return proofs if depth >= @max_depth

      # A goal of the same shape further up is already being worked on;
      # going into it again would never end. What is known still counts.
      shape = shape_of(goal)
      return proofs if path.includes?(shape)
      path << shape

      @rules.each do |rule|
        patterns = rule.premise_patterns || next
        concluded = rule.conclusion_pattern || next
        next unless concluded.type == goal.type
        break if @expansions >= PROOF_BUDGET
        @expansions += 1

        # The rule's variables are its own.
        suffix = "~#{@renamings += 1}"
        start = Unifier.unify(Unifier.rename(concluded, suffix), goal, bindings) || next
        premises = patterns.map { |pattern| Unifier.rename(pattern, suffix) }

        solve_all(premises, 0, start, [] of AtomSpace::Atom, depth + 1, path) do |atoms|
          next if atoms.uniq(&.handle).size < atoms.size
          conclusion = rule.apply(atoms, @atomspace) || next
          extended = Unifier.unify(goal, conclusion, bindings) || next
          proofs << {conclusion, extended} if proved.add?(conclusion.handle)
        end
      end

      path.pop
      proofs
    end

    # Each way of proving the premises from `index` on, one after another.
    private def solve_all(premises : Array(AtomSpace::Atom), index : Int32, bindings : Bindings,
                          atoms : Array(AtomSpace::Atom), depth : Int32, path : Array(String),
                          &block : Array(AtomSpace::Atom) ->) : Nil
      if index == premises.size
        block.call(atoms)
        return
      end
      solve(premises[index], bindings, depth, path).each do |(atom, extended)|
        solve_all(premises, index + 1, extended, atoms + [atom], depth, path, &block)
      end
    end

    # A goal with its variables numbered by first appearance, so that two
    # goals that differ only in the names of their variables look alike.
    private def shape_of(goal : AtomSpace::Atom) : String
      names = {} of String => String
      Unifier.variables(goal).each { |name| names[name] = "$#{names.size}" }
      names.empty? ? goal.to_s : Unifier.resolve(goal, names.transform_values { |name| AtomSpace::VariableNode.new(name).as(AtomSpace::Atom) }).to_s
    end

    # Advanced backward chaining with BIT construction
    def do_chain(target : AtomSpace::Atom) : Array(AtomSpace::Atom)
      # Rules that declare patterns can prove the target outright; what
      # they conclude is then in the AtomSpace for the search below.
      prove(target) if @rules.any?(&.premise_patterns)

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

    # Variable fulfillment query - find groundings for variables. With
    # `derive`, what the pattern rules can conclude about the pattern is
    # worked out first and counts too; that adds those conclusions to the
    # AtomSpace.
    def variable_fulfillment_query(pattern : AtomSpace::Atom, derive : Bool = false) : Array(Hash(String, AtomSpace::Atom))
      groundings = [] of Hash(String, AtomSpace::Atom)

      # Extract variables from pattern
      variables = Unifier.variables(pattern)
      return groundings if variables.empty?
      prove(pattern) if derive

      # Each ground atom the pattern unifies with gives one grounding.
      # Atoms with variables of their own, the pattern included when it is
      # stored in the AtomSpace, are other patterns and ground nothing.
      @atomspace.get_all_atoms.each do |atom|
        next unless Unifier.ground?(atom)
        bindings = Unifier.unify(pattern, atom) || next
        groundings << variables.to_h { |name| {name, Unifier.resolve(bindings[name], bindings)} }
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
      @current_iteration >= @max_iterations || all_nodes_exhausted? || root_satisfied?
    end

    # The goal is proven once it is in the AtomSpace; expanding further only
    # rebuilds premises for a target that is already established.
    private def root_satisfied? : Bool
      if root = @root_bit
        @atomspace.contains?(root.target)
      else
        false
      end
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
      # A rule that declares the shape of its conclusion applies when that
      # shape can be the target. One that declares only a type is matched
      # on the type.
      @rules.select do |rule|
        next false unless rule.conclusion == target.type
        pattern = rule.conclusion_pattern
        pattern.nil? || Unifier.unifiable?(Unifier.rename(pattern, "~rule"), target)
      end
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

    private def atoms_unify?(atom1 : AtomSpace::Atom, atom2 : AtomSpace::Atom) : Bool
      Unifier.unifiable?(atom1, atom2)
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
      @forward_chainer.run(steps)
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
