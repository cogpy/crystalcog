# Attention-based query optimization
# Ranks and prunes candidate atoms for pattern matching using STI/LTI

require "./attention"
require "./attention_bank"
require "../pattern_matching/pattern_matching"

module Attention
  # Uses attention values to optimize pattern matching queries by
  # prioritizing high-STI candidates and pruning low-importance atoms.
  class AttentionQueryOptimizer
    getter bank : AttentionBank
    getter min_sti : Int16
    getter prefer_focus : Bool

    def initialize(@bank : AttentionBank, @min_sti : Int16 = 0_i16, @prefer_focus : Bool = true)
    end

    # Rank atoms by attention importance (highest first)
    def rank_by_attention(atoms : Array(AtomSpace::Atom)) : Array(AtomSpace::Atom)
      atoms.sort_by do |atom|
        av = @bank.get_attention_value(atom.handle)
        sti = av ? av.sti.to_i32 : 0
        lti = av ? av.lti.to_i32 : 0
        # Higher importance first => negate for ascending sort
        -(sti * 10 + lti)
      end
    end

    # Filter atoms below the STI threshold
    def filter_by_sti(atoms : Array(AtomSpace::Atom)) : Array(AtomSpace::Atom)
      atoms.select do |atom|
        av = @bank.get_attention_value(atom.handle)
        av.nil? ? @min_sti <= 0 : av.sti >= @min_sti
      end
    end

    # Prefer atoms in attentional focus; fall back to full ranked list
    def prioritize_focus(atoms : Array(AtomSpace::Atom)) : Array(AtomSpace::Atom)
      return rank_by_attention(atoms) unless @prefer_focus

      in_focus = [] of AtomSpace::Atom
      outside = [] of AtomSpace::Atom

      atoms.each do |atom|
        if @bank.in_attentional_focus?(atom.handle)
          in_focus << atom
        else
          outside << atom
        end
      end

      rank_by_attention(in_focus) + rank_by_attention(outside)
    end

    # Optimize a candidate set for matching: filter + prioritize
    def optimize_candidates(atoms : Array(AtomSpace::Atom)) : Array(AtomSpace::Atom)
      filtered = filter_by_sti(atoms)
      prioritize_focus(filtered)
    end

    # Run pattern match with attention-guided candidate ordering.
    # Uses a standard matcher but pre-stimulates high-importance match results.
    def optimized_match(pattern : PatternMatching::Pattern, max_results : Int32 = 100) : Array(PatternMatching::MatchResult)
      matcher = PatternMatching::PatternMatcher.new(@bank.atomspace, max_results)
      results = matcher.match(pattern)

      # Rank results by average STI of matched atoms
      scored = results.map do |result|
        avg_sti = if result.matched_atoms.empty?
                    0.0
                  else
                    total = result.matched_atoms.sum do |atom|
                      av = @bank.get_attention_value(atom.handle)
                      av ? av.sti.to_f64 : 0.0
                    end
                    total / result.matched_atoms.size
                  end
        {result, avg_sti}
      end

      scored.sort_by { |_, sti| -sti }.map { |r, _| r }
    end

    # Estimate query cost based on attention distribution of candidates
    def estimate_cost(candidate_count : Int32, focus_fraction : Float64 = 0.0) : Float64
      # Lower cost when more candidates are in focus (can short-circuit)
      base = candidate_count.to_f64
      focus_bonus = focus_fraction.clamp(0.0, 1.0) * 0.5
      base * (1.0 - focus_bonus)
    end

    # Select top-k atoms by STI for focused subgraph queries
    def top_k_by_sti(k : Int32) : Array(AtomSpace::Atom)
      scored = [] of Tuple(AtomSpace::Atom, Int16)

      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        sti = av ? av.sti : 0_i16
        scored << {atom, sti}
      end

      scored.sort_by { |_, sti| -sti.to_i32 }.first(k).map { |a, _| a }
    end
  end
end
