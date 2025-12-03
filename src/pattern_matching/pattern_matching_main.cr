# Pattern Matching main module entry point
# This provides convenient access to pattern matching functionality
# Including advanced features for Agent-Zero Genesis

require "./pattern_matching"
require "./advanced_pattern_matching"

module PatternMatching
  # Convenience methods for common pattern matching operations
  module Utils
    # Create a simple variable with the given name
    def self.variable(name : String) : AtomSpace::Atom
      AtomSpace::VariableNode.new("$#{name}")
    end

    # Create a type constraint for a variable
    def self.type_constraint(variable : AtomSpace::Atom, atom_type : AtomSpace::AtomType) : TypeConstraint
      TypeConstraint.new(variable, atom_type)
    end

    # Create a present constraint for atoms
    def self.present_constraint(atoms : Array(AtomSpace::Atom)) : PresentConstraint
      PresentConstraint.new(atoms)
    end

    # Create an absent constraint for atoms
    def self.absent_constraint(atoms : Array(AtomSpace::Atom)) : AbsentConstraint
      AbsentConstraint.new(atoms)
    end

    # Create an equality constraint between two atoms
    def self.equality_constraint(left : AtomSpace::Atom, right : AtomSpace::Atom) : EqualityConstraint
      EqualityConstraint.new(left, right)
    end

    # Create a greater than constraint for numeric comparisons
    def self.greater_than_constraint(left : AtomSpace::Atom, right : AtomSpace::Atom) : GreaterThanConstraint
      GreaterThanConstraint.new(left, right)
    end

    # Quick match for simple inheritance patterns
    def self.match_inheritance(atomspace : AtomSpace::AtomSpace, child : String?, parent : String?) : Array(MatchResult)
      matcher = PatternMatcher.new(atomspace)

      child_atom = if child
                     atomspace.add_concept_node(child)
                   else
                     variable("child")
                   end

      parent_atom = if parent
                      atomspace.add_concept_node(parent)
                    else
                      variable("parent")
                    end

      pattern_atom = AtomSpace::InheritanceLink.new(child_atom, parent_atom)
      pattern = Pattern.new(pattern_atom)

      matcher.match(pattern)
    end

    # Quick match for simple evaluation patterns
    def self.match_evaluation(atomspace : AtomSpace::AtomSpace, predicate : String?,
                              subject : String?, object : String?) : Array(MatchResult)
      matcher = PatternMatcher.new(atomspace)

      pred_atom = if predicate
                    atomspace.add_predicate_node(predicate)
                  else
                    variable("predicate")
                  end

      subj_atom = if subject
                    atomspace.add_concept_node(subject)
                  else
                    variable("subject")
                  end

      obj_atom = if object
                   atomspace.add_concept_node(object)
                 else
                   variable("object")
                 end

      args = AtomSpace::ListLink.new([subj_atom, obj_atom].map(&.as(AtomSpace::Atom)))
      pattern_atom = AtomSpace::EvaluationLink.new(pred_atom, args)
      pattern = Pattern.new(pattern_atom)

      matcher.match(pattern)
    end

    # Advanced utility: Create recursive query composer
    def self.create_recursive_composer(atomspace : AtomSpace::AtomSpace) : Advanced::RecursiveQueryComposer
      Advanced::RecursiveQueryComposer.new(atomspace)
    end

    # Advanced utility: Create temporal pattern matcher
    def self.create_temporal_matcher(atomspace : AtomSpace::AtomSpace, time_window_ms : Int64 = 5000) : Advanced::TemporalPatternMatcher
      Advanced::TemporalPatternMatcher.new(atomspace, time_window_ms)
    end

    # Advanced utility: Create pattern learner
    def self.create_pattern_learner(atomspace : AtomSpace::AtomSpace, frequency_threshold : Float64 = 0.1, confidence_threshold : Float64 = 0.8) : Advanced::PatternLearner
      Advanced::PatternLearner.new(atomspace, frequency_threshold, confidence_threshold)
    end

    # Advanced utility: Create statistical matcher
    def self.create_statistical_matcher(atomspace : AtomSpace::AtomSpace, fuzzy_threshold : Float64 = 0.7) : Advanced::StatisticalMatcher
      Advanced::StatisticalMatcher.new(atomspace, fuzzy_threshold)
    end
  end

  # Query builder for more complex patterns
  class QueryBuilder
    getter atomspace : AtomSpace::AtomSpace
    getter variables : Hash(String, AtomSpace::Atom)
    getter constraints : Array(Constraint)

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @variables = Hash(String, AtomSpace::Atom).new
      @constraints = Array(Constraint).new
    end

    # Add a variable to the query
    def variable(name : String) : AtomSpace::Atom
      unless @variables.has_key?(name)
        @variables[name] = Utils.variable(name)
      end
      @variables[name]
    end

    # Add a type constraint
    def constrain_type(var_name : String, atom_type : AtomSpace::AtomType)
      var = variable(var_name)
      @constraints << TypeConstraint.new(var, atom_type)
      self
    end

    # Require atoms to be present
    def require_present(atoms : Array(AtomSpace::Atom))
      @constraints << PresentConstraint.new(atoms)
      self
    end

    # Require atoms to be absent
    def require_absent(atoms : Array(AtomSpace::Atom))
      @constraints << AbsentConstraint.new(atoms)
      self
    end

    # Add equality constraint between variables or atoms
    def constrain_equal(left : String | AtomSpace::Atom, right : String | AtomSpace::Atom)
      left_atom = left.is_a?(String) ? variable(left) : left
      right_atom = right.is_a?(String) ? variable(right) : right
      @constraints << EqualityConstraint.new(left_atom, right_atom)
      self
    end

    # Add greater than constraint for numeric comparisons
    def constrain_greater_than(left : String | AtomSpace::Atom, right : String | AtomSpace::Atom)
      left_atom = left.is_a?(String) ? variable(left) : left
      right_atom = right.is_a?(String) ? variable(right) : right
      @constraints << GreaterThanConstraint.new(left_atom, right_atom)
      self
    end

    # Build an inheritance pattern
    def inheritance(child : String | AtomSpace::Atom, parent : String | AtomSpace::Atom) : AtomSpace::Atom
      child_atom = child.is_a?(String) ? variable(child) : child
      parent_atom = parent.is_a?(String) ? variable(parent) : parent
      AtomSpace::InheritanceLink.new(child_atom, parent_atom)
    end

    # Build an evaluation pattern
    def evaluation(predicate : String | AtomSpace::Atom, subject : String | AtomSpace::Atom,
                   object : String | AtomSpace::Atom) : AtomSpace::Atom
      pred_atom = predicate.is_a?(String) ? variable(predicate) : predicate
      subj_atom = subject.is_a?(String) ? variable(subject) : subject
      obj_atom = object.is_a?(String) ? variable(object) : object

      args = AtomSpace::ListLink.new([subj_atom, obj_atom].map(&.as(AtomSpace::Atom)))
      AtomSpace::EvaluationLink.new(pred_atom, args)
    end

    # Execute the query with the given pattern
    def execute(template : AtomSpace::Atom) : Array(MatchResult)
      pattern = Pattern.new(template)
      @constraints.each { |constraint| pattern.add_constraint(constraint) }

      matcher = PatternMatcher.new(@atomspace)
      matcher.match(pattern)
    end

    # Advanced: Execute with probabilistic matching
    def execute_probabilistic(template : AtomSpace::Atom, threshold : Float64 = 0.7) : Array(Advanced::StatisticalMatcher::ProbabilisticMatch)
      pattern = Pattern.new(template)
      @constraints.each { |constraint| pattern.add_constraint(constraint) }

      statistical_matcher = Utils.create_statistical_matcher(@atomspace, threshold)
      statistical_matcher.probabilistic_match(pattern)
    end

    # Advanced: Execute with fuzzy matching
    def execute_fuzzy(template : AtomSpace::Atom, similarity_threshold : Float64 = 0.8) : Array(Advanced::StatisticalMatcher::ProbabilisticMatch)
      pattern = Pattern.new(template)
      @constraints.each { |constraint| pattern.add_constraint(constraint) }

      statistical_matcher = Utils.create_statistical_matcher(@atomspace)
      statistical_matcher.fuzzy_match(pattern, similarity_threshold)
    end
  end

  # Enhanced pattern builder for advanced pattern matching
  class AdvancedPatternBuilder
    getter atomspace : AtomSpace::AtomSpace
    getter composer : Advanced::RecursiveQueryComposer
    getter temporal_matcher : Advanced::TemporalPatternMatcher
    getter learner : Advanced::PatternLearner
    getter statistical_matcher : Advanced::StatisticalMatcher

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @composer = Advanced::RecursiveQueryComposer.new(@atomspace)
      @temporal_matcher = Advanced::TemporalPatternMatcher.new(@atomspace)
      @learner = Advanced::PatternLearner.new(@atomspace)
      @statistical_matcher = Advanced::StatisticalMatcher.new(@atomspace)
    end

    # Register a reusable pattern
    def register_pattern(name : String, template : AtomSpace::Atom, constraints : Array(Constraint) = [] of Constraint)
      @composer.register_pattern(name, template, constraints)
      self
    end

    # Compose patterns using logical operations
    def and_patterns(pattern_names : Array(String)) : Array(MatchResult)
      @composer.compose_and(pattern_names)
    end

    def or_patterns(pattern_names : Array(String)) : Array(MatchResult)
      @composer.compose_or(pattern_names)
    end

    def not_patterns(base_pattern : String, exclude_pattern : String) : Array(MatchResult)
      @composer.compose_not(base_pattern, exclude_pattern)
    end

    # Temporal pattern operations
    def temporal_sequence(patterns : Array(Pattern), sequence_name : String = "default") : Array(Advanced::TemporalPatternMatcher::TemporalMatch)
      @temporal_matcher.match_sequence(patterns, sequence_name)
    end

    def temporal_interval(pattern : Pattern, interval_ms : Int64) : Array(Advanced::TemporalPatternMatcher::TemporalMatch)
      @temporal_matcher.match_within_interval(pattern, interval_ms)
    end

    # Pattern learning operations
    def learn_patterns : Array(Advanced::PatternLearner::LearnedPattern)
      @learner.learn_patterns
    end

    def apply_learned_patterns : Array(MatchResult)
      @learner.apply_learned_patterns
    end

    # Statistical pattern operations
    def probabilistic_match(pattern : Pattern) : Array(Advanced::StatisticalMatcher::ProbabilisticMatch)
      @statistical_matcher.probabilistic_match(pattern)
    end

    def fuzzy_match(pattern : Pattern, similarity_threshold : Float64 = 0.8) : Array(Advanced::StatisticalMatcher::ProbabilisticMatch)
      @statistical_matcher.fuzzy_match(pattern, similarity_threshold)
    end

    def bayesian_inference(evidence : Array(Pattern), hypothesis : Pattern) : Advanced::StatisticalMatcher::ProbabilisticMatch?
      @statistical_matcher.bayesian_inference(evidence, hypothesis)
    end

    def monte_carlo_sampling(pattern : Pattern, num_samples : Int32 = 1000) : Array(Advanced::StatisticalMatcher::ProbabilisticMatch)
      @statistical_matcher.monte_carlo_sampling(pattern, num_samples)
    end
  end

  # Module-level convenience methods for pattern matching
  
  # Create a pattern matcher for the given atomspace
  def self.create_matcher(atomspace : AtomSpace::AtomSpace) : PatternMatcher
    PatternMatcher.new(atomspace)
  end

  # Create a pattern from a template atom
  def self.create_pattern(template : AtomSpace::Atom) : Pattern
    Pattern.new(template)
  end

  # Match a pattern in the given atomspace
  def self.match_pattern(atomspace : AtomSpace::AtomSpace, pattern : Pattern) : Array(MatchResult)
    matcher = PatternMatcher.new(atomspace)
    matcher.match(pattern)
  end
end
