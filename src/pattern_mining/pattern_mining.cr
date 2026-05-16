# Crystal implementation of Pattern Mining for pattern discovery
# Based on the opencog/miner module algorithm described in miner/opencog/miner/README.md
#
# This module implements mining algorithms that discover frequent patterns
# in the AtomSpace by searching the space of pattern trees, starting from
# abstract patterns and specializing them while maintaining minimum support.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../pattern_matching/pattern_matching"

module PatternMining
  VERSION = "0.1.0"

  # Exception for mining-related errors
  class MiningException < Exception
  end

  # Exception for timeout during mining
  class MiningTimeoutException < MiningException
  end

  # Support information for a pattern
  struct PatternSupport
    getter pattern : PatternMatching::Pattern
    getter support : Int32
    getter frequency : Float64

    def initialize(@pattern : PatternMatching::Pattern, @support : Int32, database_size : Int32)
      @frequency = database_size > 0 ? @support.to_f / database_size.to_f : 0.0
    end

    def meets_minimum_support?(min_support : Int32) : Bool
      @support >= min_support
    end

    def to_s(io)
      io << "PatternSupport(support: #{@support}, frequency: #{@frequency.round(4)})"
    end
  end

  # Represents a valuation - a specific grounding of a pattern
  struct Valuation
    getter pattern : PatternMatching::Pattern
    getter grounding : PatternMatching::MatchResult
    getter data_atom : AtomSpace::Atom

    def initialize(@pattern : PatternMatching::Pattern, @grounding : PatternMatching::MatchResult, @data_atom : AtomSpace::Atom)
    end

    def to_s(io)
      io << "Valuation(pattern: #{@pattern.template}, data: #{@data_atom})"
    end
  end

  # Shallow abstraction represents a way to abstract/generalize valuations
  struct ShallowAbstraction
    getter abstraction_atom : AtomSpace::Atom
    getter frequency : Int32

    def initialize(@abstraction_atom : AtomSpace::Atom, @frequency : Int32)
    end

    def to_s(io)
      io << "ShallowAbstraction(#{@abstraction_atom}, freq: #{@frequency})"
    end
  end

  # Mining result containing discovered patterns
  struct MiningResult
    getter patterns : Array(PatternSupport)
    getter total_patterns_explored : Int32
    getter mining_time : Time::Span

    def initialize(@patterns : Array(PatternSupport), @total_patterns_explored : Int32, @mining_time : Time::Span)
    end

    def frequent_patterns(min_support : Int32) : Array(PatternSupport)
      @patterns.select(&.meets_minimum_support?(min_support))
    end

    def to_s(io)
      io << "MiningResult("
      io << "patterns: #{@patterns.size}, "
      io << "explored: #{@total_patterns_explored}, "
      io << "time: #{@mining_time.total_milliseconds.round(2)}ms"
      io << ")"
    end
  end

  # Support calculator for patterns
  class SupportCalculator
    getter atomspace : AtomSpace::AtomSpace
    getter pattern_matcher : PatternMatching::PatternMatcher

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @pattern_matcher = PatternMatching::PatternMatcher.new(@atomspace)
    end

    # Calculate support for a pattern (number of data trees that match it)
    def calculate_support(pattern : PatternMatching::Pattern) : Int32
      begin
        matches = @pattern_matcher.match(pattern)
        matches.size
      rescue ex
        CogUtil::Logger.warn("Support calculation failed for pattern #{pattern.template}: #{ex.message}")
        0
      end
    end

    # Calculate support information for a pattern including frequency
    def calculate_pattern_support(pattern : PatternMatching::Pattern, database_size : Int32) : PatternSupport
      support = calculate_support(pattern)
      PatternSupport.new(pattern, support, database_size)
    end

    # Extract valuations for a pattern over the database
    def extract_valuations(pattern : PatternMatching::Pattern, data_atoms : Array(AtomSpace::Atom)) : Array(Valuation)
      valuations = Array(Valuation).new

      data_atoms.each do |data_atom|
        begin
          # Try to match the pattern against this data atom
          # Create a temporary atomspace with just this atom for matching
          temp_atomspace = AtomSpace::AtomSpace.new
          temp_atomspace.add_atom(data_atom)

          temp_matcher = PatternMatching::PatternMatcher.new(temp_atomspace)
          matches = temp_matcher.match(pattern)

          matches.each do |match|
            if match.success?
              valuations << Valuation.new(pattern, match, data_atom)
            end
          end
        rescue ex
          CogUtil::Logger.debug("Valuation extraction failed for atom #{data_atom}: #{ex.message}")
        end
      end

      valuations
    end
  end

  # Pattern specializer for creating more specific patterns
  class PatternSpecializer
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace)
    end

    # Determine shallow abstractions from a set of valuations
    # This identifies common structural patterns in the groundings
    def determine_shallow_abstractions(valuations : Array(Valuation)) : Array(ShallowAbstraction)
      abstractions = Array(ShallowAbstraction).new
      abstraction_freq = Hash(AtomSpace::Atom, Int32).new(0)

      valuations.each do |valuation|
        # Extract structural patterns from the grounding
        structural_atoms = extract_structural_atoms(valuation.grounding)

        structural_atoms.each do |atom|
          abstraction_freq[atom] += 1
        end
      end

      # Convert to shallow abstractions
      abstraction_freq.each do |atom, freq|
        if freq > 1 # Only consider abstractions that appear multiple times
          abstractions << ShallowAbstraction.new(atom, freq)
        end
      end

      # Sort by frequency (most frequent first)
      abstractions.sort! { |a, b| b.frequency <=> a.frequency }
      abstractions
    end

    # Extract structural atoms from a match result
    private def extract_structural_atoms(match : PatternMatching::MatchResult) : Array(AtomSpace::Atom)
      structural_atoms = Array(AtomSpace::Atom).new

      # Extract bound atoms from variable bindings
      match.bindings.each do |variable, atom|
        structural_atoms << atom

        # If the atom has outgoing links, extract those too
        if atom.responds_to?(:outgoing)
          atom.outgoing.each do |outgoing_atom|
            structural_atoms << outgoing_atom
          end
        end
      end

      # Extract matched atoms
      match.matched_atoms.each do |atom|
        structural_atoms << atom
      end

      structural_atoms.uniq
    end

    # Specialize a pattern by composing it with a shallow abstraction
    def specialize_pattern(base_pattern : PatternMatching::Pattern, abstraction : ShallowAbstraction) : PatternMatching::Pattern?
      begin
        # Create a specialized pattern by combining the base pattern with the abstraction
        # This is a simplified approach - in practice, this would involve more complex
        # composition logic based on the specific abstraction type

        if base_pattern.template.responds_to?(:outgoing) && abstraction.abstraction_atom.responds_to?(:outgoing)
          # Create a more complex pattern by combining structures
          specialized_template = create_specialized_template(base_pattern.template, abstraction.abstraction_atom)
          PatternMatching::Pattern.new(specialized_template)
        else
          # For simple cases, use the abstraction as a constraint
          specialized_pattern = PatternMatching::Pattern.new(base_pattern.template)
          # Add constraint based on the abstraction
          # This is a simplified implementation
          specialized_pattern
        end
      rescue ex
        CogUtil::Logger.debug("Pattern specialization failed: #{ex.message}")
        nil
      end
    end

    # Create a specialized template by combining base and abstraction
    private def create_specialized_template(base : AtomSpace::Atom, abstraction : AtomSpace::Atom) : AtomSpace::Atom
      # This is a simplified implementation
      # In practice, this would involve sophisticated pattern composition logic

      if base.type == abstraction.type && base.responds_to?(:outgoing) && abstraction.responds_to?(:outgoing)
        # Try to merge outgoing sets
        combined_outgoing = (base.outgoing + abstraction.outgoing).uniq
        case base.type
        when AtomSpace::AtomType::INHERITANCE_LINK
          AtomSpace::InheritanceLink.new(combined_outgoing[0], combined_outgoing[1])
        when AtomSpace::AtomType::EVALUATION_LINK
          AtomSpace::EvaluationLink.new(combined_outgoing[0], combined_outgoing[1])
        else
          base # Fallback to original
        end
      else
        base
      end
    end
  end

  # Main pattern mining engine
  class PatternMiner
    getter atomspace : AtomSpace::AtomSpace
    getter support_calculator : SupportCalculator
    getter pattern_specializer : PatternSpecializer

    @min_support : Int32
    @max_patterns : Int32
    @timeout_seconds : Int32?
    @discovered_patterns : Array(PatternSupport)
    @patterns_to_explore : Array(PatternMatching::Pattern)
    @explored_patterns : Set(String) # Track explored patterns by string representation

    def initialize(@atomspace : AtomSpace::AtomSpace, @min_support : Int32 = 2,
                   @max_patterns : Int32 = 1000, @timeout_seconds : Int32? = nil)
      @support_calculator = SupportCalculator.new(@atomspace)
      @pattern_specializer = PatternSpecializer.new(@atomspace)
      @discovered_patterns = Array(PatternSupport).new
      @patterns_to_explore = Array(PatternMatching::Pattern).new
      @explored_patterns = Set(String).new
    end

    # Mine patterns from the atomspace using the main algorithm
    def mine_patterns : MiningResult
      start_time = Time.instant
      patterns_explored = 0

      CogUtil::Logger.info("Starting pattern mining with min_support=#{@min_support}")

      # Step 1: Initialize with the Top pattern (most abstract)
      initialize_with_top_pattern

      # Main mining loop
      while !@patterns_to_explore.empty? && patterns_explored < @max_patterns
        break if check_timeout(start_time)

        # Step 1: Select a pattern from the collection
        current_pattern = @patterns_to_explore.shift
        pattern_key = pattern_to_key(current_pattern)

        # Skip if already explored
        next if @explored_patterns.includes?(pattern_key)
        @explored_patterns.add(pattern_key)

        patterns_explored += 1
        CogUtil::Logger.debug("Exploring pattern #{patterns_explored}: #{current_pattern.template}")

        # Step 2: Calculate support for this pattern
        database_size = @atomspace.size.to_i32
        pattern_support = @support_calculator.calculate_pattern_support(current_pattern, database_size)

        # Only proceed if pattern has minimum support
        if pattern_support.meets_minimum_support?(@min_support)
          @discovered_patterns << pattern_support

          # Step 3: Extract valuations for this pattern
          data_atoms = get_data_atoms
          valuations = @support_calculator.extract_valuations(current_pattern, data_atoms)

          # Step 4: Determine shallow abstractions
          abstractions = @pattern_specializer.determine_shallow_abstractions(valuations)

          # Step 5: Create specializations and add those with enough support
          abstractions.each do |abstraction|
            break if check_timeout(start_time)

            specialized_pattern = @pattern_specializer.specialize_pattern(current_pattern, abstraction)
            if specialized_pattern
              specialized_key = pattern_to_key(specialized_pattern)
              unless @explored_patterns.includes?(specialized_key)
                @patterns_to_explore << specialized_pattern
              end
            end
          end
        else
          CogUtil::Logger.debug("Pattern discarded - insufficient support: #{pattern_support.support}")
        end
      end

      mining_time = Time.instant - start_time
      CogUtil::Logger.info("Pattern mining completed: #{@discovered_patterns.size} patterns found, #{patterns_explored} explored")

      MiningResult.new(@discovered_patterns, patterns_explored, mining_time)
    end

    # Initialize mining with the most abstract pattern (Top)
    private def initialize_with_top_pattern
      # Create the Top pattern: Lambda(Variable("$X"), Present(Variable("$X")))
      var_x = AtomSpace::VariableNode.new("$X")
      top_pattern = PatternMatching::Pattern.new(var_x)
      @patterns_to_explore << top_pattern
      CogUtil::Logger.debug("Initialized with Top pattern")
    end

    # Get all data atoms from the atomspace for mining
    private def get_data_atoms : Array(AtomSpace::Atom)
      # Get all atoms from the atomspace
      # In practice, this might be filtered to specific types or criteria
      @atomspace.get_all_atoms
    end

    # Convert pattern to string key for tracking explored patterns
    private def pattern_to_key(pattern : PatternMatching::Pattern) : String
      # Simple string representation - in practice might need more sophisticated hashing
      "#{pattern.template.type}:#{pattern.template.to_s}:#{pattern.variables.size}"
    end

    # Check if mining has timed out
    private def check_timeout(start_time : Time::Instant) : Bool
      if timeout = @timeout_seconds
        elapsed = (Time.instant - start_time).total_seconds
        if elapsed > timeout
          CogUtil::Logger.warn("Pattern mining timed out after #{elapsed.round(2)} seconds")
          return true
        end
      end
      false
    end
  end

  # Utility functions for pattern mining
  module Utils
    # Create a top pattern that matches everything
    def self.create_top_pattern : PatternMatching::Pattern
      var_x = AtomSpace::VariableNode.new("$X")
      PatternMatching::Pattern.new(var_x)
    end

    # Create a pattern for inheritance relationships
    def self.create_inheritance_pattern : PatternMatching::Pattern
      var_x = AtomSpace::VariableNode.new("$X")
      var_y = AtomSpace::VariableNode.new("$Y")
      inheritance_link = AtomSpace::InheritanceLink.new(var_x, var_y)
      PatternMatching::Pattern.new(inheritance_link)
    end

    # Create a pattern for evaluation relationships
    def self.create_evaluation_pattern : PatternMatching::Pattern
      var_pred = AtomSpace::VariableNode.new("$P")
      var_args = AtomSpace::VariableNode.new("$A")
      evaluation_link = AtomSpace::EvaluationLink.new(var_pred, var_args)
      PatternMatching::Pattern.new(evaluation_link)
    end
  end
end
