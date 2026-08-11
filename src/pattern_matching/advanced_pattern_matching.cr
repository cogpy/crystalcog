# Advanced Pattern Matching for CrystalCog
# Implementation of sophisticated pattern matching capabilities as outlined
# in the Agent-Zero Genesis roadmap (Month 3+ features)
#
# This module provides:
# - Recursive query composition
# - Temporal pattern matching
# - Pattern learning and optimization
# - Statistical/probabilistic matching
# - Complex constraint systems

require "./pattern_matching"

module PatternMatching
  # Advanced pattern matching capabilities
  module Advanced
    VERSION = "1.0.0"

    # Recursive query composer for building complex patterns from simpler ones
    class RecursiveQueryComposer
      getter atomspace : AtomSpace::AtomSpace
      getter base_patterns : Hash(String, Pattern)
      getter composition_cache : Hash(String, Array(MatchResult))

      def initialize(@atomspace : AtomSpace::AtomSpace)
        @base_patterns = Hash(String, Pattern).new
        @composition_cache = Hash(String, Array(MatchResult)).new
      end

      # Register a base pattern that can be reused in compositions
      def register_pattern(name : String, template : AtomSpace::Atom,
                           constraints : Array(Constraint) = [] of Constraint)
        pattern = Pattern.new(template)
        constraints.each { |constraint| pattern.add_constraint(constraint) }
        @base_patterns[name] = pattern
      end

      # Compose patterns using logical operators (AND, OR, NOT)
      def compose_and(pattern_names : Array(String)) : Array(MatchResult)
        cache_key = "AND_#{pattern_names.join("_")}"
        return @composition_cache[cache_key] if @composition_cache.has_key?(cache_key)

        all_results = pattern_names.map do |name|
          pattern = @base_patterns[name]?
          raise PatternCompositionException.new("Pattern '#{name}' not found") unless pattern

          matcher = PatternMatcher.new(@atomspace)
          matcher.match(pattern)
        end

        # Find intersection of variable bindings
        intersected_results = intersect_results(all_results)
        @composition_cache[cache_key] = intersected_results
        intersected_results
      end

      # OR composition - union of all matches
      def compose_or(pattern_names : Array(String)) : Array(MatchResult)
        cache_key = "OR_#{pattern_names.join("_")}"
        return @composition_cache[cache_key] if @composition_cache.has_key?(cache_key)

        all_results = [] of MatchResult
        pattern_names.each do |name|
          pattern = @base_patterns[name]?
          next unless pattern

          matcher = PatternMatcher.new(@atomspace)
          all_results.concat(matcher.match(pattern))
        end

        # Remove duplicates and cache
        unique_results = all_results.uniq { |r| r.bindings.to_s }
        @composition_cache[cache_key] = unique_results
        unique_results
      end

      # NOT composition - exclude matches of specified pattern
      def compose_not(base_pattern : String, exclude_pattern : String) : Array(MatchResult)
        cache_key = "NOT_#{base_pattern}_#{exclude_pattern}"
        return @composition_cache[cache_key] if @composition_cache.has_key?(cache_key)

        base_pattern_obj = @base_patterns[base_pattern]?
        exclude_pattern_obj = @base_patterns[exclude_pattern]?

        raise PatternCompositionException.new("Base pattern '#{base_pattern}' not found") unless base_pattern_obj
        raise PatternCompositionException.new("Exclude pattern '#{exclude_pattern}' not found") unless exclude_pattern_obj

        matcher = PatternMatcher.new(@atomspace)
        base_results = matcher.match(base_pattern_obj)
        exclude_results = matcher.match(exclude_pattern_obj)

        # Remove base results that appear in exclude results
        filtered_results = base_results.reject do |base_result|
          exclude_results.any? { |exclude_result| results_overlap?(base_result, exclude_result) }
        end

        @composition_cache[cache_key] = filtered_results
        filtered_results
      end

      # Recursive pattern composition - patterns that reference themselves
      def compose_recursive(pattern_name : String, max_depth : Int32 = 10) : Array(MatchResult)
        cache_key = "RECURSIVE_#{pattern_name}_#{max_depth}"
        return @composition_cache[cache_key] if @composition_cache.has_key?(cache_key)

        pattern = @base_patterns[pattern_name]?
        raise PatternCompositionException.new("Pattern '#{pattern_name}' not found") unless pattern

        raise PatternCompositionException.new("max_depth must be non-negative") if max_depth < 0

        accumulated_results = [] of MatchResult
        seen_bindings = Set(String).new
        matcher = PatternMatcher.new(@atomspace)
        previous_count = -1

        (0...max_depth).each do |depth|
          current_results = matcher.match(pattern)
          break if current_results.empty?

          # Fixed-point: stop if no new unique bindings appear
          new_unique = 0
          current_results.each do |result|
            key = bindings_key(result)
            unless seen_bindings.includes?(key)
              seen_bindings.add(key)
              accumulated_results << result
              new_unique += 1
            end
          end

          break if new_unique == 0
          break if accumulated_results.size == previous_count
          previous_count = accumulated_results.size

          # Update atomspace with new facts derived from current matches for next iteration
          current_results.each do |result|
            derive_new_facts(result, pattern)
          end
        end

        @composition_cache[cache_key] = accumulated_results
        accumulated_results
      end

      # Nested composition: apply an outer composition operator to the results
      # of inner named compositions. Handles empty pattern lists and single
      # patterns as edge cases.
      def compose_nested(operator : String, pattern_groups : Array(Array(String))) : Array(MatchResult)
        raise PatternCompositionException.new("operator must be AND or OR") unless operator.in?("AND", "OR")
        return [] of MatchResult if pattern_groups.empty?

        group_results = pattern_groups.map do |group|
          next [] of MatchResult if group.empty?
          case operator
          when "AND"
            # Within a group, use AND; empty registration fails softly
            begin
              compose_and(group)
            rescue PatternCompositionException
              [] of MatchResult
            end
          else
            compose_or(group)
          end
        end

        # Between groups, use the opposite-style merge for nested depth:
        # AND-of-groups intersects; OR-of-groups unions
        case operator
        when "AND"
          intersect_results(group_results)
        else
          group_results.flatten.uniq { |r| bindings_key(r) }
        end
      end

      # Clear composition cache (invalidate after atomspace mutations)
      def clear_cache
        @composition_cache.clear
      end

      def cache_size : Int32
        @composition_cache.size
      end

      # Merge two result sets by unifying compatible bindings
      def merge_compatible(results_a : Array(MatchResult), results_b : Array(MatchResult)) : Array(MatchResult)
        merged = [] of MatchResult
        results_a.each do |a|
          results_b.each do |b|
            if compatible_bindings?(a, b)
              combined = a.bindings.dup
              b.bindings.each { |k, v| combined[k] = v }
              combined_atoms = (a.matched_atoms + b.matched_atoms).uniq
              merged << MatchResult.new(combined, combined_atoms)
            end
          end
        end
        merged.uniq { |r| bindings_key(r) }
      end

      private def bindings_key(result : MatchResult) : String
        result.bindings.map { |var, atom| "#{var.handle}->#{atom.handle}" }.sort!.join("|")
      end

      private def intersect_results(all_results : Array(Array(MatchResult))) : Array(MatchResult)
        return [] of MatchResult if all_results.empty?
        return all_results[0] if all_results.size == 1
        return [] of MatchResult if all_results.any?(&.empty?)

        # Find compatible bindings across all result sets and merge them
        intersected = [] of MatchResult

        all_results[0].each do |first_result|
          compatible_sets = all_results[1..].map do |other_results|
            other_results.select { |other_result| compatible_bindings?(first_result, other_result) }
          end

          next if compatible_sets.any?(&.empty?)

          # Merge first result with one compatible from each set
          merged_bindings = first_result.bindings.dup
          merged_atoms = first_result.matched_atoms.dup
          compatible = true

          compatible_sets.each do |set|
            # Prefer the first compatible; unify bindings
            other = set.first
            other.bindings.each do |var, atom|
              if existing = merged_bindings[var]?
                if existing != atom
                  compatible = false
                  break
                end
              else
                merged_bindings[var] = atom
              end
            end
            break unless compatible
            merged_atoms.concat(other.matched_atoms)
          end

          if compatible
            intersected << MatchResult.new(merged_bindings, merged_atoms.uniq)
          end
        end

        intersected.uniq { |r| bindings_key(r) }
      end

      private def compatible_bindings?(result1 : MatchResult, result2 : MatchResult) : Bool
        # Check if variable bindings are compatible (same variables bind to same atoms)
        # Bidirectional: both sides must agree on shared variables
        result1.bindings.all? do |var, atom|
          other_atom = result2.bindings[var]?
          other_atom.nil? || other_atom == atom
        end && result2.bindings.all? do |var, atom|
          other_atom = result1.bindings[var]?
          other_atom.nil? || other_atom == atom
        end
      end

      private def results_overlap?(result1 : MatchResult, result2 : MatchResult) : Bool
        # Check if two results have overlapping bindings
        result1.bindings.any? do |var, atom|
          other_atom = result2.bindings[var]?
          other_atom && other_atom == atom
        end
      end

      private def derive_new_facts(result : MatchResult, pattern : Pattern)
        # Derive EvaluationLinks asserting that bound variables matched,
        # enabling multi-depth recursive composition to build on prior matches.
        return if result.bindings.empty?

        matched_pred = @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "matched_by_#{pattern.template.type}")
        result.bindings.each do |var, atom|
          list = @atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [var, atom])
          @atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [matched_pred, list])
        end
      end
    end

    # Temporal pattern matching for sequences and time-based patterns
    class TemporalPatternMatcher
      getter atomspace : AtomSpace::AtomSpace
      getter time_window_ms : Int64
      getter temporal_cache : Hash(String, Array(TemporalMatch))

      def initialize(@atomspace : AtomSpace::AtomSpace, @time_window_ms : Int64 = 5000)
        @temporal_cache = Hash(String, Array(TemporalMatch)).new
      end

      struct TemporalMatch
        getter pattern_results : Array(MatchResult)
        getter timestamps : Array(Int64)
        getter sequence_id : String

        def initialize(@pattern_results : Array(MatchResult), @timestamps : Array(Int64), @sequence_id : String)
        end

        def duration_ms : Int64
          return 0_i64 if @timestamps.empty?
          @timestamps.max - @timestamps.min
        end

        def average_interval_ms : Float64
          return 0.0 if @timestamps.size < 2
          intervals = @timestamps.zip(@timestamps[1..]).map { |a, b| b - a }
          intervals.sum.to_f64 / intervals.size
        end
      end

      # Match sequences of patterns within a time window
      def match_sequence(patterns : Array(Pattern), sequence_name : String = "default") : Array(TemporalMatch)
        cache_key = "SEQ_#{sequence_name}_#{patterns.size}"
        return @temporal_cache[cache_key] if @temporal_cache.has_key?(cache_key)

        current_time = Time.utc.to_unix_ms
        temporal_matches = [] of TemporalMatch

        # For demonstration, simulate temporal matching by running patterns in sequence
        # In a real implementation, this would involve event timestamps
        patterns.each_with_index do |pattern, index|
          matcher = PatternMatcher.new(@atomspace)
          results = matcher.match(pattern)

          unless results.empty?
            # Simulate temporal progression
            timestamp = current_time + (index * 100)
            sequence_id = "#{sequence_name}_#{index}_#{timestamp}"

            temporal_match = TemporalMatch.new(results, [timestamp], sequence_id)
            temporal_matches << temporal_match
          end
        end

        @temporal_cache[cache_key] = temporal_matches
        temporal_matches
      end

      # Match patterns that occur within a specific time interval
      def match_within_interval(pattern : Pattern, interval_ms : Int64) : Array(TemporalMatch)
        matcher = PatternMatcher.new(@atomspace)
        results = matcher.match(pattern)
        current_time = Time.utc.to_unix_ms

        # Group results that would occur within the time interval
        temporal_matches = [] of TemporalMatch
        unless results.empty?
          # Simulate temporal clustering
          sequence_id = "interval_#{current_time}_#{interval_ms}"
          temporal_match = TemporalMatch.new(results, [current_time], sequence_id)
          temporal_matches << temporal_match
        end

        temporal_matches
      end

      # Detect repeating temporal patterns
      def detect_repeating_patterns(pattern : Pattern, min_occurrences : Int32 = 3) : Array(TemporalMatch)
        repeating_matches = [] of TemporalMatch

        # Simulate pattern detection across multiple time points
        matcher = PatternMatcher.new(@atomspace)
        base_results = matcher.match(pattern)

        if base_results.size >= min_occurrences
          current_time = Time.utc.to_unix_ms
          timestamps = (0...min_occurrences).map { |i| current_time + (i * 1000) }
          sequence_id = "repeating_#{current_time}"

          temporal_match = TemporalMatch.new(base_results, timestamps, sequence_id)
          repeating_matches << temporal_match
        end

        repeating_matches
      end
    end

    # Pattern learning system that discovers frequent patterns automatically
    class PatternLearner
      getter atomspace : AtomSpace::AtomSpace
      getter learned_patterns : Hash(String, LearnedPattern)
      getter frequency_threshold : Float64
      getter confidence_threshold : Float64

      def initialize(@atomspace : AtomSpace::AtomSpace,
                     @frequency_threshold : Float64 = 0.1,
                     @confidence_threshold : Float64 = 0.8)
        @learned_patterns = Hash(String, LearnedPattern).new
      end

      struct LearnedPattern
        getter template : AtomSpace::Atom
        getter frequency : Float64
        getter confidence : Float64
        getter examples : Array(MatchResult)
        getter creation_time : Time

        def initialize(@template : AtomSpace::Atom, @frequency : Float64,
                       @confidence : Float64, @examples : Array(MatchResult))
          @creation_time = Time.utc
        end

        def strength : Float64
          (@frequency * @confidence) ** 0.5
        end

        def age_hours : Float64
          (Time.utc - @creation_time).total_hours
        end
      end

      # Learn patterns from the current atomspace
      def learn_patterns : Array(LearnedPattern)
        discovered_patterns = [] of LearnedPattern

        # Learn inheritance patterns
        inheritance_patterns = discover_inheritance_patterns
        discovered_patterns.concat(inheritance_patterns)

        # Learn evaluation patterns
        evaluation_patterns = discover_evaluation_patterns
        discovered_patterns.concat(evaluation_patterns)

        # Learn structural patterns
        structural_patterns = discover_structural_patterns
        discovered_patterns.concat(structural_patterns)

        # Update learned patterns cache
        discovered_patterns.each do |pattern|
          pattern_key = generate_pattern_key(pattern.template)
          @learned_patterns[pattern_key] = pattern
        end

        discovered_patterns
      end

      # Apply learned patterns to find new matches
      def apply_learned_patterns : Array(MatchResult)
        all_results = [] of MatchResult

        @learned_patterns.each do |key, learned_pattern|
          # Only apply patterns that meet quality thresholds
          next unless learned_pattern.frequency >= @frequency_threshold
          next unless learned_pattern.confidence >= @confidence_threshold

          pattern = Pattern.new(learned_pattern.template)
          matcher = PatternMatcher.new(@atomspace)
          results = matcher.match(pattern)

          all_results.concat(results)
        end

        all_results.uniq { |r| r.bindings.to_s }
      end

      # Get pattern statistics
      def pattern_statistics : Hash(String, Float64)
        stats = Hash(String, Float64).new

        if @learned_patterns.empty?
          stats["total_patterns"] = 0.0
          stats["average_frequency"] = 0.0
          stats["average_confidence"] = 0.0
          stats["average_strength"] = 0.0
          return stats
        end

        stats["total_patterns"] = @learned_patterns.size.to_f64
        stats["average_frequency"] = @learned_patterns.values.map(&.frequency).sum / @learned_patterns.size
        stats["average_confidence"] = @learned_patterns.values.map(&.confidence).sum / @learned_patterns.size
        stats["average_strength"] = @learned_patterns.values.map(&.strength).sum / @learned_patterns.size

        stats
      end

      private def discover_inheritance_patterns : Array(LearnedPattern)
        patterns = [] of LearnedPattern

        # Find common inheritance structures
        inheritance_links = @atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
        total_links = inheritance_links.size.to_f64

        return patterns if total_links == 0

        # Group by parent concepts to find frequent inheritance targets
        parent_frequency = Hash(AtomSpace::Atom, Int32).new(0)

        inheritance_links.each do |link|
          next unless link.responds_to?(:outgoing) && link.outgoing.size == 2
          parent = link.outgoing[1]
          parent_frequency[parent] += 1
        end

        # Create learned patterns for frequent inheritance targets
        parent_frequency.each do |parent, count|
          frequency = count.to_f64 / total_links
          next unless frequency >= @frequency_threshold

          # Create a pattern template: X inherits from parent
          var_x = AtomSpace::VariableNode.new("$X")
          template = AtomSpace::InheritanceLink.new(var_x, parent)

          # Calculate confidence based on how well this predicts inheritance
          confidence = calculate_inheritance_confidence(parent, inheritance_links)
          next unless confidence >= @confidence_threshold

          # Find example matches
          pattern = Pattern.new(template)
          matcher = PatternMatcher.new(@atomspace)
          examples = matcher.match(pattern)

          learned_pattern = LearnedPattern.new(template, frequency, confidence, examples)
          patterns << learned_pattern
        end

        patterns
      end

      private def discover_evaluation_patterns : Array(LearnedPattern)
        patterns = [] of LearnedPattern

        evaluation_links = @atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        total_evaluations = evaluation_links.size.to_f64

        return patterns if total_evaluations == 0

        # Group by predicate to find frequent evaluation patterns
        predicate_frequency = Hash(AtomSpace::Atom, Int32).new(0)

        evaluation_links.each do |link|
          next unless link.responds_to?(:outgoing) && link.outgoing.size == 2
          predicate = link.outgoing[0]
          predicate_frequency[predicate] += 1
        end

        # Create learned patterns for frequent predicates
        predicate_frequency.each do |predicate, count|
          frequency = count.to_f64 / total_evaluations
          next unless frequency >= @frequency_threshold

          # Create pattern: predicate(X, Y)
          var_x = AtomSpace::VariableNode.new("$X")
          var_y = AtomSpace::VariableNode.new("$Y")
          args = AtomSpace::ListLink.new([var_x, var_y].map(&.as(AtomSpace::Atom)))
          template = AtomSpace::EvaluationLink.new(predicate, args)

          confidence = calculate_evaluation_confidence(predicate, evaluation_links)
          next unless confidence >= @confidence_threshold

          pattern = Pattern.new(template)
          matcher = PatternMatcher.new(@atomspace)
          examples = matcher.match(pattern)

          learned_pattern = LearnedPattern.new(template, frequency, confidence, examples)
          patterns << learned_pattern
        end

        patterns
      end

      private def discover_structural_patterns : Array(LearnedPattern)
        patterns = [] of LearnedPattern

        # Discover common structural patterns (links with specific outgoing sizes)
        structure_frequency = Hash(Tuple(AtomSpace::AtomType, Int32), Int32).new(0)

        @atomspace.get_all_atoms.each do |atom|
          next unless atom.responds_to?(:outgoing)
          key = {atom.type, atom.outgoing.size}
          structure_frequency[key] += 1
        end

        total_structures = structure_frequency.values.sum.to_f64
        return patterns if total_structures == 0

        # Create patterns for frequent structures
        structure_frequency.each do |key, count|
          atom_type, outgoing_size = key
          frequency = count.to_f64 / total_structures
          next unless frequency >= @frequency_threshold

          # Create a structural pattern with variables
          variables = (0...outgoing_size).map { |i| AtomSpace::VariableNode.new("$VAR_#{i}") }

          # We can't easily create arbitrary link types, so skip complex structures
          next unless outgoing_size <= 3

          confidence = frequency # Simplified confidence calculation
          next unless confidence >= @confidence_threshold

          # For now, just record the pattern exists - full implementation would
          # create proper template atoms based on the atom_type
        end

        patterns
      end

      private def calculate_inheritance_confidence(parent : AtomSpace::Atom,
                                                   all_links : Array(AtomSpace::Atom)) : Float64
        # Calculate how reliably this parent predicts inheritance relationships
        parent_links = all_links.select do |link|
          link.responds_to?(:outgoing) && link.outgoing.size == 2 && link.outgoing[1] == parent
        end

        return 0.8 if parent_links.empty? # Default confidence

        # Simple confidence based on frequency - could be more sophisticated
        [parent_links.size.to_f64 / all_links.size * 2, 1.0].min
      end

      private def calculate_evaluation_confidence(predicate : AtomSpace::Atom,
                                                  all_evaluations : Array(AtomSpace::Atom)) : Float64
        predicate_evaluations = all_evaluations.select do |link|
          link.responds_to?(:outgoing) && link.outgoing.size == 2 && link.outgoing[0] == predicate
        end

        return 0.7 if predicate_evaluations.empty?

        [predicate_evaluations.size.to_f64 / all_evaluations.size * 2, 1.0].min
      end

      private def generate_pattern_key(template : AtomSpace::Atom) : String
        # Generate a unique key for the pattern template
        "#{template.type}_#{template.hash}_#{Time.utc.to_unix_ms}"
      end
    end

    # Statistical and probabilistic pattern matching
    class StatisticalMatcher
      getter atomspace : AtomSpace::AtomSpace
      getter fuzzy_threshold : Float64
      getter probabilistic_cache : Hash(String, Array(ProbabilisticMatch))

      def initialize(@atomspace : AtomSpace::AtomSpace, @fuzzy_threshold : Float64 = 0.7)
        @probabilistic_cache = Hash(String, Array(ProbabilisticMatch)).new
      end

      struct ProbabilisticMatch
        getter match_result : MatchResult
        getter probability : Float64
        getter confidence_intervals : Hash(String, Tuple(Float64, Float64))
        getter statistical_measures : Hash(String, Float64)

        def initialize(@match_result : MatchResult, @probability : Float64)
          @confidence_intervals = Hash(String, Tuple(Float64, Float64)).new
          @statistical_measures = Hash(String, Float64).new
          calculate_statistics
        end

        private def calculate_statistics
          # Calculate basic statistical measures
          @statistical_measures["entropy"] = -@probability * Math.log(@probability) if @probability > 0
          @statistical_measures["certainty"] = @probability
          @statistical_measures["uncertainty"] = 1.0 - @probability

          # Simple confidence intervals (would be more sophisticated in practice)
          margin = 0.1 * @probability
          @confidence_intervals["95%"] = {@probability - margin, @probability + margin}
        end

        def is_significant?(alpha : Float64 = 0.05) : Bool
          @probability >= (1.0 - alpha)
        end
      end

      # Probabilistic pattern matching using truth values and attention values
      def probabilistic_match(pattern : Pattern) : Array(ProbabilisticMatch)
        cache_key = "PROB_#{pattern.template.hash}"
        return @probabilistic_cache[cache_key] if @probabilistic_cache.has_key?(cache_key)

        matcher = PatternMatcher.new(@atomspace)
        base_results = matcher.match(pattern)

        probabilistic_results = base_results.map do |result|
          probability = calculate_match_probability(result, pattern)
          ProbabilisticMatch.new(result, probability)
        end

        # Filter by probability threshold
        significant_results = probabilistic_results.select(&.probability.>= @fuzzy_threshold)
        @probabilistic_cache[cache_key] = significant_results
        significant_results
      end

      # Fuzzy pattern matching with partial matches
      def fuzzy_match(pattern : Pattern, similarity_threshold : Float64 = 0.8) : Array(ProbabilisticMatch)
        # Start with exact matches
        matcher = PatternMatcher.new(@atomspace)
        exact_results = matcher.match(pattern)

        # Convert to probabilistic matches
        fuzzy_results = exact_results.map do |result|
          ProbabilisticMatch.new(result, 1.0) # Exact matches have probability 1.0
        end

        # Add fuzzy matches by relaxing constraints
        relaxed_results = find_relaxed_matches(pattern, similarity_threshold)
        fuzzy_results.concat(relaxed_results)

        # Sort by probability and return top matches
        fuzzy_results.sort_by(&.probability.-)
      end

      # Bayesian inference for pattern prediction
      def bayesian_inference(evidence_patterns : Array(Pattern),
                             hypothesis_pattern : Pattern) : ProbabilisticMatch?
        # Calculate P(hypothesis | evidence) using Bayes' theorem
        # P(H|E) = P(E|H) * P(H) / P(E)

        matcher = PatternMatcher.new(@atomspace)

        # Calculate prior probability P(H)
        hypothesis_results = matcher.match(hypothesis_pattern)
        total_atoms = @atomspace.size.to_f64
        prior_prob = hypothesis_results.size.to_f64 / total_atoms

        return nil if prior_prob == 0.0

        # Calculate likelihood P(E|H) - how often evidence occurs when hypothesis is true
        likelihood = calculate_likelihood(evidence_patterns, hypothesis_pattern)

        # Calculate evidence probability P(E)
        evidence_prob = calculate_evidence_probability(evidence_patterns)

        return nil if evidence_prob == 0.0

        # Apply Bayes' theorem
        posterior_prob = (likelihood * prior_prob) / evidence_prob

        # Create a synthetic match result for the inference
        if hypothesis_results.empty?
          return nil
        end

        ProbabilisticMatch.new(hypothesis_results.first, posterior_prob)
      end

      # Monte Carlo sampling for complex pattern spaces
      def monte_carlo_sampling(pattern : Pattern, num_samples : Int32 = 1000) : Array(ProbabilisticMatch)
        sampled_matches = [] of ProbabilisticMatch

        (0...num_samples).each do |_|
          # Perform sampling by introducing random variations
          sample_result = sample_pattern_space(pattern)
          if sample_result
            probability = calculate_sample_probability(sample_result, pattern)
            if probability >= @fuzzy_threshold
              sampled_matches << ProbabilisticMatch.new(sample_result, probability)
            end
          end
        end

        # Remove duplicates and return top results
        unique_matches = sampled_matches.uniq { |m| m.match_result.bindings.to_s }
        unique_matches.sort_by(&.probability.-).first(100)
      end

      private def calculate_match_probability(result : MatchResult, pattern : Pattern) : Float64
        # Calculate probability based on truth values of matched atoms
        total_strength = 0.0
        total_confidence = 0.0
        atom_count = 0

        result.matched_atoms.each do |atom|
          if atom.responds_to?(:truth_value) && atom.truth_value
            tv = atom.truth_value.not_nil!
            total_strength += tv.strength
            total_confidence += tv.confidence
            atom_count += 1
          end
        end

        return 0.5 if atom_count == 0 # Default probability

        avg_strength = total_strength / atom_count
        avg_confidence = total_confidence / atom_count

        # Combine strength and confidence into overall probability
        (avg_strength * avg_confidence + avg_strength) / 2.0
      end

      private def find_relaxed_matches(pattern : Pattern, threshold : Float64) : Array(ProbabilisticMatch)
        relaxed_matches = [] of ProbabilisticMatch

        # Implement relaxed matching by creating variations of the pattern
        # This is a simplified version - full implementation would be more sophisticated

        # Try matching with fewer constraints
        relaxed_pattern = Pattern.new(pattern.template)
        # Skip some constraints to create relaxed version
        pattern.constraints.each_with_index do |constraint, index|
          next if index % 2 == 0 # Skip every other constraint for relaxation
          relaxed_pattern.add_constraint(constraint)
        end

        matcher = PatternMatcher.new(@atomspace)
        relaxed_results = matcher.match(relaxed_pattern)

        relaxed_results.each do |result|
          # Calculate similarity to original pattern
          similarity = calculate_pattern_similarity(result, pattern)
          if similarity >= threshold
            relaxed_matches << ProbabilisticMatch.new(result, similarity * 0.8) # Reduce prob for relaxed matches
          end
        end

        relaxed_matches
      end

      private def calculate_likelihood(evidence_patterns : Array(Pattern),
                                       hypothesis_pattern : Pattern) : Float64
        # Simplified likelihood calculation
        matcher = PatternMatcher.new(@atomspace)

        hypothesis_results = matcher.match(hypothesis_pattern)
        return 0.0 if hypothesis_results.empty?

        # Count how often evidence patterns match when hypothesis is true
        evidence_count = 0
        hypothesis_count = hypothesis_results.size

        evidence_patterns.each do |evidence|
          evidence_results = matcher.match(evidence)
          # Check overlap with hypothesis results
          overlap = evidence_results.count do |ev_result|
            hypothesis_results.any? { |hyp_result| results_have_common_atoms(ev_result, hyp_result) }
          end
          evidence_count += overlap
        end

        evidence_count.to_f64 / (hypothesis_count * evidence_patterns.size)
      end

      private def calculate_evidence_probability(evidence_patterns : Array(Pattern)) : Float64
        matcher = PatternMatcher.new(@atomspace)
        total_evidence_matches = 0

        evidence_patterns.each do |pattern|
          results = matcher.match(pattern)
          total_evidence_matches += results.size
        end

        total_evidence_matches.to_f64 / (@atomspace.size * evidence_patterns.size)
      end

      private def sample_pattern_space(pattern : Pattern) : MatchResult?
        # Simple sampling by running the pattern with slight modifications
        matcher = PatternMatcher.new(@atomspace)
        results = matcher.match(pattern)

        return nil if results.empty?

        # Return a random result (simplified sampling)
        results[Random.rand(results.size)]?
      end

      private def calculate_sample_probability(result : MatchResult, pattern : Pattern) : Float64
        # Simplified probability calculation for sampled results
        base_prob = calculate_match_probability(result, pattern)

        # Add some randomness to simulate sampling uncertainty
        noise = (Random.rand - 0.5) * 0.2
        [0.0, [1.0, base_prob + noise].min].max
      end

      private def calculate_pattern_similarity(result : MatchResult, pattern : Pattern) : Float64
        # Calculate how similar a result is to the original pattern
        # This is simplified - would involve more sophisticated similarity measures

        satisfied_constraints = pattern.constraints.count do |constraint|
          constraint.satisfied?(result.bindings, @atomspace)
        end

        return 0.5 if pattern.constraints.empty?

        satisfied_constraints.to_f64 / pattern.constraints.size
      end

      private def results_have_common_atoms(result1 : MatchResult, result2 : MatchResult) : Bool
        # Check if two results share any atoms
        result1.matched_atoms.any? { |atom1| result2.matched_atoms.includes?(atom1) }
      end
    end

    # Exception classes for advanced pattern matching
    class PatternCompositionException < PatternMatchingException
    end

    class TemporalMatchingException < PatternMatchingException
    end

    class LearningException < PatternMatchingException
    end

    class StatisticalMatchingException < PatternMatchingException
    end

    # Pattern match cache with TTL and size limits for optimization
    class PatternMatchCache
      struct CacheEntry
        getter results : Array(MatchResult)
        getter created_at : Time
        getter hit_count : Int32

        def initialize(@results : Array(MatchResult))
          @created_at = Time.utc
          @hit_count = 0
        end

        def touch : CacheEntry
          entry = CacheEntry.new(@results)
          entry
        end

        def age_seconds : Float64
          (Time.utc - @created_at).total_seconds
        end
      end

      getter max_size : Int32
      getter ttl_seconds : Float64

      @entries : Hash(String, CacheEntry)
      @hits : Int64
      @misses : Int64

      def initialize(@max_size : Int32 = 256, @ttl_seconds : Float64 = 60.0)
        @entries = {} of String => CacheEntry
        @hits = 0_i64
        @misses = 0_i64
      end

      def fetch(key : String) : Array(MatchResult)?
        entry = @entries[key]?
        if entry.nil? || entry.age_seconds > @ttl_seconds
          @entries.delete(key) if entry
          @misses += 1
          return nil
        end
        @hits += 1
        # Bump hit count via replace
        @entries[key] = CacheEntry.new(entry.results)
        entry.results
      end

      def store(key : String, results : Array(MatchResult))
        evict_if_needed
        @entries[key] = CacheEntry.new(results)
      end

      def clear
        @entries.clear
        @hits = 0_i64
        @misses = 0_i64
      end

      def size : Int32
        @entries.size
      end

      def stats : Hash(String, Float64)
        total = @hits + @misses
        {
          "hits"     => @hits.to_f64,
          "misses"   => @misses.to_f64,
          "size"     => @entries.size.to_f64,
          "hit_rate" => total > 0 ? @hits.to_f64 / total : 0.0,
        }
      end

      private def evict_if_needed
        return if @entries.size < @max_size

        # Evict oldest entry
        oldest_key = @entries.min_by { |_, e| e.created_at }[0]
        @entries.delete(oldest_key)
      end
    end

    # Optimized matcher that caches results and can integrate attention ranking
    class OptimizedPatternMatcher
      getter atomspace : AtomSpace::AtomSpace
      getter cache : PatternMatchCache
      getter fuzzy_threshold : Float64

      def initialize(@atomspace : AtomSpace::AtomSpace,
                     @fuzzy_threshold : Float64 = 0.7,
                     cache_size : Int32 = 256,
                     cache_ttl : Float64 = 60.0)
        @cache = PatternMatchCache.new(cache_size, cache_ttl)
        @matcher = PatternMatcher.new(@atomspace)
      end

      def match(pattern : Pattern) : Array(MatchResult)
        key = cache_key(pattern)
        if cached = @cache.fetch(key)
          return cached
        end

        results = @matcher.match(pattern)
        @cache.store(key, results)
        results
      end

      def fuzzy_match(pattern : Pattern, threshold : Float64 = @fuzzy_threshold) : Array(MatchResult)
        stats = StatisticalMatcher.new(@atomspace, threshold)
        stats.fuzzy_match(pattern, threshold).map(&.match_result)
      end

      def clear_cache
        @cache.clear
      end

      def cache_stats : Hash(String, Float64)
        @cache.stats
      end

      private def cache_key(pattern : Pattern) : String
        vars = pattern.variables.map(&.hash).sort!.join(",")
        constraints = pattern.constraints.map(&.to_s).join(";")
        "#{pattern.template.type}:#{pattern.template.hash}:#{vars}:#{constraints}"
      end
    end

    # Initialize advanced pattern matching subsystem
    def self.initialize
      CogUtil::Logger.info("Advanced Pattern Matching #{VERSION} initializing")

      # Ensure base pattern matching is initialized
      PatternMatching.initialize unless @@pattern_matching_initialized

      CogUtil::Logger.info("Advanced Pattern Matching #{VERSION} initialized")
      CogUtil::Logger.info("Available features:")
      CogUtil::Logger.info("  - Recursive query composition")
      CogUtil::Logger.info("  - Nested composition edge cases")
      CogUtil::Logger.info("  - Temporal pattern matching and constraints")
      CogUtil::Logger.info("  - Fuzzy matching with configurable thresholds")
      CogUtil::Logger.info("  - Pattern learning and optimization/caching")
      CogUtil::Logger.info("  - Statistical/probabilistic matching")
    end

    @@pattern_matching_initialized = false
  end
end
