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

  # Surprisingness (novelty) scorer for patterns.
  # Based on the I-Surprisingness measure from the OpenCog miner:
  # a pattern is surprising when its observed frequency deviates from
  # the frequency expected under an independence assumption.
  class SurprisingnessScorer
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace)
    end

    # Compute I-Surprisingness of a pattern given the frequencies of its
    # component sub-patterns. Returns a value in [0, 1] where higher
    # values indicate more surprising (novel) patterns.
    def i_surprisingness(observed_frequency : Float64, component_frequencies : Array(Float64)) : Float64
      return 0.0 if component_frequencies.empty?

      # Expected frequency under independence assumption
      expected = component_frequencies.reduce(1.0) { |acc, f| acc * f }

      # Normalized deviation from expectation
      max_freq = Math.max(observed_frequency, expected)
      return 0.0 if max_freq <= 0.0

      ((observed_frequency - expected).abs / max_freq).clamp(0.0, 1.0)
    end

    # Score a discovered pattern's surprisingness relative to the database.
    # Uses per-variable marginal frequencies as the independence baseline.
    def score(pattern_support : PatternSupport, database_size : Int32) : Float64
      return 0.0 if database_size <= 0

      # Marginal frequency of each variable in the pattern approximated
      # by the fraction of atoms of the same type as the template
      template = pattern_support.pattern.template
      same_type_count = @atomspace.get_atoms_by_type(template.type).size
      marginal = same_type_count.to_f / database_size.to_f

      num_vars = Math.max(pattern_support.pattern.variables.size, 1)
      component_frequencies = Array(Float64).new(num_vars, marginal.clamp(0.0, 1.0))

      i_surprisingness(pattern_support.frequency, component_frequencies)
    end

    # Rank patterns by surprisingness (most surprising first)
    def rank_patterns(patterns : Array(PatternSupport), database_size : Int32) : Array(Tuple(PatternSupport, Float64))
      scored = patterns.map { |p| {p, score(p, database_size)} }
      scored.sort_by { |_, s| -s }
    end
  end

  # Streaming pattern miner: processes atoms incrementally as they arrive,
  # maintaining approximate pattern frequency counts over a sliding window.
  # Suitable for continuously updated atomspaces where full re-mining is
  # too expensive.
  class StreamingPatternMiner
    getter atomspace : AtomSpace::AtomSpace
    getter window_size : Int32
    getter min_support : Int32

    # Sliding window of recently observed atoms
    @window : Deque(AtomSpace::Atom)
    # Approximate frequency counts of structural pattern keys
    @pattern_counts : Hash(String, Int32)
    # Representative atom for each pattern key
    @pattern_examples : Hash(String, AtomSpace::Atom)
    @total_processed : Int64

    def initialize(@atomspace : AtomSpace::AtomSpace, @window_size : Int32 = 1000, @min_support : Int32 = 2)
      raise MiningException.new("window_size must be positive") if @window_size <= 0
      @window = Deque(AtomSpace::Atom).new
      @pattern_counts = Hash(String, Int32).new(0)
      @pattern_examples = Hash(String, AtomSpace::Atom).new
      @total_processed = 0_i64
    end

    def total_processed : Int64
      @total_processed
    end

    def window_count : Int32
      @window.size
    end

    # Process a single incoming atom, updating the sliding window and counts
    def process_atom(atom : AtomSpace::Atom)
      @total_processed += 1

      # Evict oldest atom when window is full
      if @window.size >= @window_size
        evicted = @window.shift
        key = structural_key(evicted)
        @pattern_counts[key] -= 1
        if @pattern_counts[key] <= 0
          @pattern_counts.delete(key)
          @pattern_examples.delete(key)
        end
      end

      @window << atom
      key = structural_key(atom)
      @pattern_counts[key] += 1
      @pattern_examples[key] = atom unless @pattern_examples.has_key?(key)
    end

    # Process a batch of atoms
    def process_atoms(atoms : Array(AtomSpace::Atom))
      atoms.each { |atom| process_atom(atom) }
    end

    # Return currently frequent structural patterns in the window
    def frequent_patterns : Array(PatternSupport)
      results = Array(PatternSupport).new
      window_total = @window.size

      @pattern_counts.each do |key, count|
        next if count < @min_support
        example = @pattern_examples[key]?
        next unless example

        pattern = abstract_pattern_for(example)
        results << PatternSupport.new(pattern, count, window_total)
      end

      results.sort_by { |ps| -ps.support }
    end

    # Detect newly emerging patterns: patterns whose support crossed the
    # minimum threshold within the current window.
    def emerging_patterns(previous_counts : Hash(String, Int32)) : Array(PatternSupport)
      frequent_patterns.select do |ps|
        key = structural_key(ps.pattern.template)
        (previous_counts[key]? || 0) < @min_support
      end
    end

    # Snapshot of current pattern counts (for emerging pattern comparison)
    def counts_snapshot : Hash(String, Int32)
      @pattern_counts.dup
    end

    def reset
      @window.clear
      @pattern_counts.clear
      @pattern_examples.clear
      @total_processed = 0_i64
    end

    # Structural key abstracting an atom to its type shape
    private def structural_key(atom : AtomSpace::Atom) : String
      if atom.is_a?(AtomSpace::Link)
        inner = atom.outgoing.map { |o| o.type.to_s }.join(",")
        "#{atom.type}(#{inner})"
      else
        atom.type.to_s
      end
    end

    # Build an abstract (variabilized) pattern matching atoms with the same
    # structural shape as the example.
    private def abstract_pattern_for(example : AtomSpace::Atom) : PatternMatching::Pattern
      if example.is_a?(AtomSpace::Link)
        vars = example.outgoing.map_with_index do |_, i|
          AtomSpace::VariableNode.new("$S#{i}").as(AtomSpace::Atom)
        end
        template = AtomSpace::Link.new(example.type, vars)
        PatternMatching::Pattern.new(template)
      else
        PatternMatching::Pattern.new(AtomSpace::VariableNode.new("$S"))
      end
    end
  end

  # Pattern evaluation metrics for ranking and filtering discovered patterns
  struct PatternMetrics
    getter support : Int32
    getter frequency : Float64
    getter surprisingness : Float64
    getter confidence : Float64
    getter lift : Float64
    getter conviction : Float64

    def initialize(@support : Int32, @frequency : Float64,
                   @surprisingness : Float64 = 0.0,
                   @confidence : Float64 = 0.0,
                   @lift : Float64 = 0.0,
                   @conviction : Float64 = 0.0)
    end

    # Composite quality score combining multiple metrics
    def quality_score(w_freq : Float64 = 0.3, w_surprise : Float64 = 0.3,
                      w_conf : Float64 = 0.2, w_lift : Float64 = 0.2) : Float64
      (w_freq * @frequency) +
        (w_surprise * @surprisingness) +
        (w_conf * @confidence) +
        (w_lift * Math.min(@lift / 10.0, 1.0))
    end
  end

  # Evaluates mined patterns with association-rule style metrics
  class PatternEvaluator
    getter atomspace : AtomSpace::AtomSpace
    getter surprisingness_scorer : SurprisingnessScorer

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @surprisingness_scorer = SurprisingnessScorer.new(@atomspace)
    end

    # Evaluate a single pattern support entry
    def evaluate(pattern_support : PatternSupport, database_size : Int32,
                 antecedent_support : Int32? = nil, consequent_support : Int32? = nil) : PatternMetrics
      surprise = @surprisingness_scorer.score(pattern_support, database_size)

      conf = 0.0
      lift = 0.0
      conviction = 0.0

      if (ant = antecedent_support) && ant > 0
        conf = pattern_support.support.to_f / ant.to_f
      end

      if (cons = consequent_support) && database_size > 0 && cons > 0
        expected = cons.to_f / database_size.to_f
        lift = expected > 0 ? conf / expected : 0.0
        conviction = if conf < 1.0 && expected < 1.0
                       (1.0 - expected) / (1.0 - conf)
                     else
                       conf >= 1.0 ? Float64::INFINITY : 0.0
                     end
        conviction = 0.0 unless conviction.finite?
      end

      PatternMetrics.new(
        pattern_support.support,
        pattern_support.frequency,
        surprise,
        conf.clamp(0.0, 1.0),
        lift,
        conviction
      )
    end

    # Rank patterns by composite quality
    def rank(patterns : Array(PatternSupport), database_size : Int32) : Array(Tuple(PatternSupport, PatternMetrics))
      scored = patterns.map { |p| {p, evaluate(p, database_size)} }
      scored.sort_by { |_, m| -m.quality_score }
    end
  end

  # Frequent itemset miner (Apriori-style) over AtomSpace concept co-occurrence.
  # Treats each link's outgoing concept names as a transaction.
  class FrequentItemsetMiner
    getter atomspace : AtomSpace::AtomSpace
    getter min_support : Int32
    getter max_itemset_size : Int32

    def initialize(@atomspace : AtomSpace::AtomSpace, @min_support : Int32 = 2, @max_itemset_size : Int32 = 4)
      raise MiningException.new("min_support must be positive") if @min_support <= 0
      raise MiningException.new("max_itemset_size must be positive") if @max_itemset_size <= 0
    end

    # Extract transactions: each link contributes the set of concept node names it contains
    def transactions : Array(Set(String))
      txns = [] of Set(String)

      @atomspace.get_all_atoms.each do |atom|
        next unless atom.is_a?(AtomSpace::Link)
        names = collect_concept_names(atom)
        txns << names.to_set unless names.empty?
      end

      txns
    end

    # Run Apriori frequent itemset mining
    def mine : Array(Tuple(Set(String), Int32))
      txns = transactions
      return [] of Tuple(Set(String), Int32) if txns.empty?

      # Count singletons
      item_counts = Hash(String, Int32).new(0)
      txns.each { |t| t.each { |item| item_counts[item] += 1 } }

      frequent = [] of Tuple(Set(String), Int32)
      current_level = [] of Set(String)

      item_counts.each do |item, count|
        if count >= @min_support
          s = Set{item}
          frequent << {s, count}
          current_level << s
        end
      end

      k = 2
      while k <= @max_itemset_size && !current_level.empty?
        candidates = generate_candidates(current_level, k)
        next_level = [] of Set(String)

        candidates.each do |candidate|
          count = txns.count { |t| candidate.subset_of?(t) }
          if count >= @min_support
            frequent << {candidate, count}
            next_level << candidate
          end
        end

        current_level = next_level
        k += 1
      end

      frequent.sort_by { |_, c| -c }
    end

    # Convert frequent itemsets into PatternSupport objects
    def mine_as_patterns : Array(PatternSupport)
      db_size = Math.max(@atomspace.size.to_i32, 1)
      mine.map do |itemset, support|
        # Represent itemset as a ListLink of concept nodes (variables for generality)
        atoms = itemset.map { |name| AtomSpace::ConceptNode.new(name).as(AtomSpace::Atom) }
        template = if atoms.size == 1
                     atoms.first
                   else
                     AtomSpace::ListLink.new(atoms)
                   end
        pattern = PatternMatching::Pattern.new(template)
        PatternSupport.new(pattern, support, db_size)
      end
    end

    private def collect_concept_names(link : AtomSpace::Link) : Array(String)
      names = [] of String
      link.outgoing.each do |child|
        case child
        when AtomSpace::Link
          names.concat(collect_concept_names(child))
        when AtomSpace::Node
          names << child.name if child.type == AtomSpace::AtomType::CONCEPT_NODE
        end
      end
      names
    end

    private def generate_candidates(prev_level : Array(Set(String)), k : Int32) : Array(Set(String))
      candidates = [] of Set(String)
      n = prev_level.size

      (0...n).each do |i|
        ((i + 1)...n).each do |j|
          union = prev_level[i] | prev_level[j]
          next unless union.size == k
          # Apriori prune: all (k-1) subsets should be frequent
          if all_subsets_frequent?(union, prev_level)
            candidates << union unless candidates.includes?(union)
          end
        end
      end

      candidates
    end

    private def all_subsets_frequent?(itemset : Set(String), prev_level : Array(Set(String))) : Bool
      items = itemset.to_a
      items.each_index do |i|
        subset = itemset.dup
        subset.delete(items[i])
        return false unless prev_level.any? { |p| p == subset }
      end
      true
    end
  end

  # Knowledge discovery pipeline: mine -> evaluate -> rank -> optionally assert
  class KnowledgeDiscoveryPipeline
    getter atomspace : AtomSpace::AtomSpace
    getter min_support : Int32
    getter min_quality : Float64

    def initialize(@atomspace : AtomSpace::AtomSpace, @min_support : Int32 = 2, @min_quality : Float64 = 0.1)
    end

    # Run full discovery: frequent itemsets + pattern mining + evaluation
    def discover(max_patterns : Int32 = 100) : Array(Tuple(PatternSupport, PatternMetrics))
      results = [] of Tuple(PatternSupport, PatternMetrics)
      db_size = Math.max(@atomspace.size.to_i32, 1)
      evaluator = PatternEvaluator.new(@atomspace)

      # 1. Frequent itemsets
      itemset_miner = FrequentItemsetMiner.new(@atomspace, @min_support)
      itemset_patterns = itemset_miner.mine_as_patterns
      itemset_patterns.each do |ps|
        metrics = evaluator.evaluate(ps, db_size)
        results << {ps, metrics} if metrics.quality_score >= @min_quality
      end

      # 2. Classic pattern miner (bounded)
      miner = PatternMiner.new(@atomspace, @min_support, max_patterns, 5)
      mining_result = miner.mine_patterns
      mining_result.patterns.each do |ps|
        metrics = evaluator.evaluate(ps, db_size)
        results << {ps, metrics} if metrics.quality_score >= @min_quality
      end

      # 3. Streaming snapshot of current atomspace
      streamer = StreamingPatternMiner.new(@atomspace, 1000, @min_support)
      streamer.process_atoms(@atomspace.get_all_atoms)
      streamer.frequent_patterns.each do |ps|
        metrics = evaluator.evaluate(ps, db_size)
        results << {ps, metrics} if metrics.quality_score >= @min_quality
      end

      results.sort_by { |_, m| -m.quality_score }.first(max_patterns)
    end

    # Assert high-quality patterns into AtomSpace as EvaluationLinks
    def assert_discoveries(discoveries : Array(Tuple(PatternSupport, PatternMetrics)),
                           min_quality : Float64 = @min_quality) : Int32
      count = 0
      discoveries.each do |ps, metrics|
        next if metrics.quality_score < min_quality

        pred = @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "discovered_pattern")
        quality_node = @atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          "quality_#{metrics.quality_score.round(3)}"
        )
        list = @atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [ps.pattern.template, quality_node])
        tv = AtomSpace::SimpleTruthValue.new(metrics.frequency.clamp(0.0, 1.0), metrics.confidence.clamp(0.0, 1.0))
        @atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [pred, list], tv)
        count += 1
      end
      count
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
