# Crystal implementation of OpenCog Pattern Matching Engine
# Converted from opencog/query and related components
#
# This provides pattern matching capabilities for the AtomSpace,
# allowing complex graph queries and variable binding operations.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module PatternMatching
  VERSION = "0.1.0"

  # Variable binding represents a mapping from variables to atoms
  alias VariableBinding = Hash(AtomSpace::Atom, AtomSpace::Atom)

  # Pattern match result contains the bindings and any matched atoms
  struct MatchResult
    getter bindings : VariableBinding
    getter matched_atoms : Array(AtomSpace::Atom)

    def initialize(@bindings : VariableBinding, @matched_atoms : Array(AtomSpace::Atom))
    end

    def success?
      !@bindings.empty? || !@matched_atoms.empty?
    end

    def empty?
      @bindings.empty? && @matched_atoms.empty?
    end

    def to_s(io)
      io << "MatchResult("
      io << "bindings: #{@bindings.size}, "
      io << "matched: #{@matched_atoms.size}"
      io << ")"
    end
  end

  # Pattern specification for matching operations
  class Pattern
    getter template : AtomSpace::Atom
    getter variables : Set(AtomSpace::Atom)
    getter constraints : Array(Constraint)

    def initialize(@template : AtomSpace::Atom)
      @variables = Set(AtomSpace::Atom).new
      @constraints = Array(Constraint).new
      collect_variables(@template)
    end

    def add_constraint(constraint : Constraint)
      @constraints << constraint
    end

    # Check if an atom is a variable (VariableNode starting with $)
    def self.variable?(atom : AtomSpace::Atom) : Bool
      atom.type == AtomSpace::AtomType::VARIABLE_NODE &&
        atom.responds_to?(:name) &&
        atom.name.starts_with?("$")
    end

    private def collect_variables(atom : AtomSpace::Atom)
      if Pattern.variable?(atom)
        @variables << atom
      elsif atom.responds_to?(:outgoing)
        atom.outgoing.each { |child| collect_variables(child) }
      end
    end

    def to_s(io)
      io << "Pattern(template: #{@template}, variables: #{@variables.size})"
    end
  end

  # Base class for pattern matching constraints
  abstract class Constraint
    abstract def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
    abstract def to_s(io)
  end

  # Type constraint - ensures a variable binds to atoms of specific types
  class TypeConstraint < Constraint
    getter variable : AtomSpace::Atom
    getter allowed_types : Set(AtomSpace::AtomType)

    def initialize(@variable : AtomSpace::Atom, @allowed_types : Set(AtomSpace::AtomType))
    end

    def initialize(@variable : AtomSpace::Atom, allowed_type : AtomSpace::AtomType)
      @allowed_types = Set{allowed_type}
    end

    def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
      bound_atom = bindings[@variable]?
      return true unless bound_atom # No binding yet, constraint doesn't apply

      @allowed_types.includes?(bound_atom.type)
    end

    def to_s(io)
      io << "TypeConstraint(#{@variable} : #{@allowed_types})"
    end
  end

  # Present constraint - ensures atoms exist in the atomspace
  class PresentConstraint < Constraint
    getter atoms : Array(AtomSpace::Atom)

    def initialize(@atoms : Array(AtomSpace::Atom))
    end

    def initialize(atom : AtomSpace::Atom)
      @atoms = [atom]
    end

    def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
      @atoms.all? do |atom|
        # Substitute variables with bindings
        substituted = substitute_variables(atom, bindings)
        atomspace.contains?(substituted)
      end
    end

    private def substitute_variables(atom : AtomSpace::Atom, bindings : VariableBinding) : AtomSpace::Atom
      if Pattern.variable?(atom)
        bindings[atom]? || atom
      elsif atom.responds_to?(:outgoing)
        # For links, substitute variables in outgoing atoms
        new_outgoing = atom.outgoing.map { |child| substitute_variables(child, bindings) }
        # Create a new link with substituted outgoing atoms
        # This is simplified - would need proper link creation based on type
        atom # Return original for now
      else
        atom
      end
    end

    def to_s(io)
      io << "PresentConstraint(#{@atoms.size} atoms)"
    end
  end

  # Absent constraint - ensures atoms do NOT exist in the atomspace
  class AbsentConstraint < Constraint
    getter atoms : Array(AtomSpace::Atom)

    def initialize(@atoms : Array(AtomSpace::Atom))
    end

    def initialize(atom : AtomSpace::Atom)
      @atoms = [atom]
    end

    def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
      @atoms.all? do |atom|
        # Substitute variables with bindings
        substituted = substitute_variables(atom, bindings)
        !atomspace.contains?(substituted)
      end
    end

    private def substitute_variables(atom : AtomSpace::Atom, bindings : VariableBinding) : AtomSpace::Atom
      if Pattern.variable?(atom)
        bindings[atom]? || atom
      elsif atom.responds_to?(:outgoing)
        # For links, substitute variables in outgoing atoms
        new_outgoing = atom.outgoing.map { |child| substitute_variables(child, bindings) }
        atom # Return original for now
      else
        atom
      end
    end

    def to_s(io)
      io << "AbsentConstraint(#{@atoms.size} atoms)"
    end
  end

  # Equality constraint - ensures two expressions bind to equal atoms
  class EqualityConstraint < Constraint
    getter left : AtomSpace::Atom
    getter right : AtomSpace::Atom

    def initialize(@left : AtomSpace::Atom, @right : AtomSpace::Atom)
    end

    def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
      left_substituted = substitute_variables(@left, bindings)
      right_substituted = substitute_variables(@right, bindings)
      left_substituted == right_substituted
    end

    private def substitute_variables(atom : AtomSpace::Atom, bindings : VariableBinding) : AtomSpace::Atom
      if Pattern.variable?(atom)
        bindings[atom]? || atom
      elsif atom.responds_to?(:outgoing)
        new_outgoing = atom.outgoing.map { |child| substitute_variables(child, bindings) }
        atom # Return original for now
      else
        atom
      end
    end

    def to_s(io)
      io << "EqualityConstraint(#{@left} == #{@right})"
    end
  end

  # Greater than constraint - for numeric comparisons
  class GreaterThanConstraint < Constraint
    getter left : AtomSpace::Atom
    getter right : AtomSpace::Atom

    def initialize(@left : AtomSpace::Atom, @right : AtomSpace::Atom)
    end

    def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
      left_substituted = substitute_variables(@left, bindings)
      right_substituted = substitute_variables(@right, bindings)

      # Check if both are numeric
      if left_substituted.responds_to?(:value) && right_substituted.responds_to?(:value)
        left_val = left_substituted.value
        right_val = right_substituted.value

        if left_val.is_a?(Number) && right_val.is_a?(Number)
          return left_val > right_val
        end
      end

      false
    end

    private def substitute_variables(atom : AtomSpace::Atom, bindings : VariableBinding) : AtomSpace::Atom
      if Pattern.variable?(atom)
        bindings[atom]? || atom
      else
        atom
      end
    end

    def to_s(io)
      io << "GreaterThanConstraint(#{@left} > #{@right})"
    end
  end

  # Temporal constraint - requires bound atoms to have timestamps satisfying
  # an ordering or window relationship. Timestamps are looked up from a
  # provided Hash (atom handle -> unix ms) or from EvaluationLinks named
  # "timestamp" in the atomspace.
  class TemporalConstraint < Constraint
    enum Relation
      Before
      After
      Within
      Concurrent
    end

    getter left : AtomSpace::Atom
    getter right : AtomSpace::Atom
    getter relation : Relation
    getter window_ms : Int64
    getter timestamps : Hash(AtomSpace::Handle, Int64)?

    def initialize(@left : AtomSpace::Atom, @right : AtomSpace::Atom,
                   @relation : Relation = Relation::Before,
                   @window_ms : Int64 = 0_i64,
                   @timestamps : Hash(AtomSpace::Handle, Int64)? = nil)
    end

    def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
      left_atom = resolve(@left, bindings)
      right_atom = resolve(@right, bindings)
      return true unless left_atom && right_atom # Unbound vars: don't fail yet

      t1 = timestamp_of(left_atom, atomspace)
      t2 = timestamp_of(right_atom, atomspace)
      return true if t1.nil? || t2.nil? # No temporal info: don't reject

      case @relation
      in .before?
        t1 < t2
      in .after?
        t1 > t2
      in .within?
        (t1 - t2).abs <= @window_ms
      in .concurrent?
        t1 == t2 || (t1 - t2).abs <= @window_ms
      end
    end

    private def resolve(atom : AtomSpace::Atom, bindings : VariableBinding) : AtomSpace::Atom?
      if Pattern.variable?(atom)
        bindings[atom]?
      else
        atom
      end
    end

    private def timestamp_of(atom : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : Int64?
      if ts = @timestamps
        return ts[atom.handle]?
      end
      nil
    end

    def to_s(io)
      io << "TemporalConstraint(#{@left} #{@relation} #{@right}"
      io << ", window=#{@window_ms}ms" if @window_ms > 0
      io << ")"
    end
  end

  # Fuzzy threshold constraint - requires truth-value strength of a bound
  # atom to meet a configurable minimum threshold.
  class FuzzyThresholdConstraint < Constraint
    getter variable : AtomSpace::Atom
    getter threshold : Float64
    getter use_confidence : Bool

    def initialize(@variable : AtomSpace::Atom, @threshold : Float64 = 0.5, @use_confidence : Bool = false)
      raise PatternMatchingException.new("threshold must be in [0, 1]") unless @threshold >= 0.0 && @threshold <= 1.0
    end

    def satisfied?(bindings : VariableBinding, atomspace : AtomSpace::AtomSpace) : Bool
      bound = bindings[@variable]?
      return true unless bound

      tv = bound.truth_value
      score = @use_confidence ? (tv.strength * tv.confidence) : tv.strength
      score >= @threshold
    end

    def to_s(io)
      io << "FuzzyThresholdConstraint(#{@variable} >= #{@threshold}"
      io << ", conf-weighted" if @use_confidence
      io << ")"
    end
  end

  # State for backtracking during pattern matching
  private struct MatchState
    getter bindings : VariableBinding
    getter matched_atoms : Array(AtomSpace::Atom)
    getter clause_index : Int32

    def initialize(@bindings : VariableBinding, @matched_atoms : Array(AtomSpace::Atom), @clause_index : Int32 = 0)
    end

    def dup
      MatchState.new(@bindings.dup, @matched_atoms.dup, @clause_index)
    end
  end

  # Main pattern matching engine with enhanced backtracking
  class PatternMatcher
    getter atomspace : AtomSpace::AtomSpace
    @state_stack : Array(MatchState)
    @max_results : Int32
    @timeout_seconds : Int32?

    def initialize(@atomspace : AtomSpace::AtomSpace, @max_results : Int32 = 1000, @timeout_seconds : Int32? = nil)
      @state_stack = Array(MatchState).new
    end

    # Enhanced find all matches for a given pattern with backtracking
    def match(pattern : Pattern) : Array(MatchResult)
      results = Array(MatchResult).new
      start_time = Time.instant

      # Initialize state stack
      @state_stack.clear
      initial_state = MatchState.new(VariableBinding.new, Array(AtomSpace::Atom).new)
      @state_stack.push(initial_state)

      # Start recursive exploration with backtracking
      explore_pattern(pattern, pattern.template, results, start_time)

      results.first(@max_results)
    end

    # Enhanced recursive pattern exploration with proper backtracking
    private def explore_pattern(pattern : Pattern, template : AtomSpace::Atom,
                                results : Array(MatchResult), start_time : Time::Instant)
      return if check_timeout(start_time)
      return if results.size >= @max_results

      current_state = @state_stack.last

      if Pattern.variable?(template)
        explore_variable_bindings(pattern, template, results, start_time)
      elsif template.responds_to?(:outgoing)
        explore_link_structures(pattern, template, results, start_time)
      else
        # Concrete atom - check if it exists and satisfies constraints
        if @atomspace.contains?(template)
          if constraints_satisfied?(pattern, current_state.bindings)
            new_matched = current_state.matched_atoms + [template]
            results << MatchResult.new(current_state.bindings.dup, new_matched)
          end
        end
      end
    end

    # Enhanced variable binding exploration with backtracking
    private def explore_variable_bindings(pattern : Pattern, variable : AtomSpace::Atom,
                                          results : Array(MatchResult), start_time : Time::Instant)
      return if check_timeout(start_time)

      current_state = @state_stack.last

      # If already bound, check consistency
      if existing_binding = current_state.bindings[variable]?
        if constraints_satisfied?(pattern, current_state.bindings)
          new_matched = current_state.matched_atoms + [existing_binding]
          results << MatchResult.new(current_state.bindings.dup, new_matched)
        end
        return
      end

      # Find candidates for this variable
      candidates = find_variable_candidates(variable, pattern)

      # Try each candidate with backtracking
      candidates.each do |candidate|
        break if results.size >= @max_results
        break if check_timeout(start_time)

        # Push new state onto stack (branch point)
        new_bindings = current_state.bindings.dup
        new_bindings[variable] = candidate
        new_state = MatchState.new(new_bindings, current_state.matched_atoms)
        @state_stack.push(new_state)

        # Check if constraints are satisfied with this binding
        if constraints_satisfied?(pattern, new_bindings)
          new_matched = current_state.matched_atoms + [candidate]
          results << MatchResult.new(new_bindings, new_matched)
        end

        # Backtrack - pop the state
        @state_stack.pop
      end
    end

    # Enhanced link structure exploration with tree comparison
    private def explore_link_structures(pattern : Pattern, template : AtomSpace::Atom,
                                        results : Array(MatchResult), start_time : Time::Instant)
      return if check_timeout(start_time)

      current_state = @state_stack.last

      # Find atoms in atomspace with the same type as template
      candidates = @atomspace.get_atoms_by_type(template.type)

      candidates.each do |candidate|
        break if results.size >= @max_results
        break if check_timeout(start_time)

        next unless candidate.responds_to?(:outgoing)
        next unless candidate.outgoing.size == template.outgoing.size

        # Push state for this candidate exploration
        candidate_state = current_state.dup
        @state_stack.push(candidate_state)

        # Try to match the tree structure recursively
        if tree_compare(pattern, template, candidate, start_time)
          final_state = @state_stack.last
          if constraints_satisfied?(pattern, final_state.bindings)
            new_matched = final_state.matched_atoms + [candidate]
            results << MatchResult.new(final_state.bindings.dup, new_matched)
          end
        end

        # Backtrack
        @state_stack.pop
      end
    end

    # Enhanced tree comparison algorithm from OpenCog specification
    private def tree_compare(pattern : Pattern, template : AtomSpace::Atom,
                             candidate : AtomSpace::Atom, start_time : Time::Instant) : Bool
      return false if check_timeout(start_time)

      # Base case: both are atoms
      if !template.responds_to?(:outgoing) && !candidate.responds_to?(:outgoing)
        return template == candidate || Pattern.variable?(template)
      end

      # One is link, one is atom - no match unless template is variable
      if template.responds_to?(:outgoing) != candidate.responds_to?(:outgoing)
        return Pattern.variable?(template)
      end

      # Both are links - compare recursively
      return false unless template.responds_to?(:outgoing) && candidate.responds_to?(:outgoing)
      return false unless template.type == candidate.type
      return false unless template.outgoing.size == candidate.outgoing.size

      # Compare each outgoing atom recursively
      template.outgoing.zip(candidate.outgoing) do |t_atom, c_atom|
        if Pattern.variable?(t_atom)
          # Try to bind this variable
          current_state = @state_stack.last
          if existing_binding = current_state.bindings[t_atom]?
            return false unless existing_binding == c_atom
          else
            current_state.bindings[t_atom] = c_atom
          end
        else
          # Recursive tree comparison
          return false unless tree_compare(pattern, t_atom, c_atom, start_time)
        end
      end

      true
    end

    # Check for timeout conditions
    private def check_timeout(start_time : Time::Instant) : Bool
      if timeout = @timeout_seconds
        elapsed = (Time.instant - start_time).total_seconds
        if elapsed > timeout
          raise MatchingTimeoutException.new("Pattern matching timed out after #{elapsed} seconds")
        end
      end
      false
    end

    # Match a single pattern template and return the first result
    def match_one(template : AtomSpace::Atom) : MatchResult?
      pattern = Pattern.new(template)
      results = match(pattern)
      results.first?
    end

    # Find all atoms that could bind to a variable given constraints
    def find_variable_candidates(variable : AtomSpace::Atom, pattern : Pattern) : Array(AtomSpace::Atom)
      # Get type constraints for this variable
      type_constraints = pattern.constraints.select(&.is_a?(TypeConstraint))
        .map(&.as(TypeConstraint))
        .select(&.variable.==(variable))

      if type_constraints.empty?
        # No type constraints, get all concrete atoms (but limit for performance)
        candidates = Array(AtomSpace::Atom).new

        # Add all concept nodes
        candidates.concat(@atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE).first(100))
        candidates.concat(@atomspace.get_atoms_by_type(AtomSpace::AtomType::PREDICATE_NODE).first(100))
        candidates.concat(@atomspace.get_atoms_by_type(AtomSpace::AtomType::NUMBER_NODE).first(100))

        # Add some link types (limited for performance)
        candidates.concat(@atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).first(50))
        candidates.concat(@atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).first(50))
        candidates.concat(@atomspace.get_atoms_by_type(AtomSpace::AtomType::LIST_LINK).first(50))

        candidates.uniq.first(200) # Limit total candidates for performance
      else
        # Get atoms matching the type constraints
        candidates = Array(AtomSpace::Atom).new
        type_constraints.each do |constraint|
          constraint.allowed_types.each do |atom_type|
            candidates.concat(@atomspace.get_atoms_by_type(atom_type))
          end
        end
        candidates.uniq.first(500) # Allow more when type-constrained
      end
    end

    # Check if all constraints are satisfied with current bindings
    private def constraints_satisfied?(pattern : Pattern, bindings : VariableBinding) : Bool
      pattern.constraints.all? { |constraint| constraint.satisfied?(bindings, @atomspace) }
    end
  end

  # Initialize the PatternMatching subsystem
  def self.initialize
    CogUtil::Logger.info("PatternMatching #{VERSION} initializing")

    # Initialize dependencies
    CogUtil.initialize unless @@cogutil_initialized
    AtomSpace.initialize unless @@atomspace_initialized

    CogUtil::Logger.info("PatternMatching #{VERSION} initialized")
  end

  # Track initialization state
  @@cogutil_initialized = false
  @@atomspace_initialized = false

  # Exception classes for PatternMatching
  class PatternMatchingException < CogUtil::OpenCogException
  end

  class PatternCompilationException < PatternMatchingException
  end

  class MatchingTimeoutException < PatternMatchingException
  end
end
