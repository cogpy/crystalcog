# Crystal implementation of PLN (Probabilistic Logic Networks)
# Converted from pln/opencog/pln/

require "../atomspace/atomspace_main"
require "../cogutil/cogutil"

module PLN
  VERSION = "0.1.0"

  # PLN Rule interface
  abstract class PLNRule
    abstract def name : String
    abstract def applies_to?(premise : AtomSpace::Atom) : Bool
    abstract def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
  end

  # Deduction Rule: If A->B and B->C then A->C
  class DeductionRule < PLNRule
    def name : String
      "DeductionRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      # Check if we have two inheritance links that can be chained
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.outgoing.size == 2

      # Look for another inheritance link with matching middle term
      a, b = premise.outgoing[0], premise.outgoing[1]

      # Find B->C links where B matches our B
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

      inheritance_links.each do |link|
        next unless link.is_a?(AtomSpace::Link)
        next unless link.outgoing.size == 2

        b2, c = link.outgoing[0], link.outgoing[1]

        if b == b2 # Found matching chain A->B, B->C
          # Calculate new truth value using PLN formula
          tv_ab = premise.truth_value
          tv_bc = link.truth_value

          # PLN deduction formula (simplified)
          new_strength = tv_ab.strength * tv_bc.strength
          new_confidence = tv_ab.confidence * tv_bc.confidence * 0.9 # Discount factor

          new_tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

          # Create A->C link
          return atomspace.add_link(
            AtomSpace::AtomType::INHERITANCE_LINK,
            [a, c],
            new_tv
          )
        end
      end

      nil
    end
  end

  # Inversion Rule: If A->B then B->A (with inverted strength)
  class InversionRule < PLNRule
    def name : String
      "InversionRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.outgoing.size == 2

      a, b = premise.outgoing[0], premise.outgoing[1]

      # Create inverted truth value
      tv = premise.truth_value
      inverted_strength = 1.0 / (1.0 + (1.0 - tv.strength) / tv.strength)
      inverted_confidence = tv.confidence * 0.8 # Discount for inversion

      inverted_tv = AtomSpace::SimpleTruthValue.new(inverted_strength, inverted_confidence)

      # Create B->A link
      atomspace.add_link(
        AtomSpace::AtomType::INHERITANCE_LINK,
        [b, a],
        inverted_tv
      )
    end
  end

  # Modus Ponens Rule: If A->B and A then B
  class ModusPonensRule < PLNRule
    def name : String
      "ModusPonensRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      # Applies to inheritance links (implications)
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.outgoing.size == 2

      # premise is A->B
      a, b = premise.outgoing[0], premise.outgoing[1]

      # Look for A in the atomspace (as a fact)
      atoms = atomspace.get_all_atoms
      atoms.each do |atom|
        # Check if this atom is A with sufficient confidence
        if atom == a && atom.truth_value.confidence > 0.5
          # We have both A->B and A, so we can conclude B
          tv_ab = premise.truth_value
          tv_a = atom.truth_value

          # Modus ponens strength formula (simplified)
          # P(B) = P(B|A) * P(A) + P(B|¬A) * P(¬A)
          # We assume P(B|¬A) = 0.2 (default background probability)
          p_b_given_a = tv_ab.strength
          p_a = tv_a.strength
          p_not_a = 1.0 - p_a
          p_b_given_not_a = 0.2 # Background probability

          new_strength = p_b_given_a * p_a + p_b_given_not_a * p_not_a
          new_confidence = [tv_ab.confidence, tv_a.confidence].min * 0.9 # Discount factor

          new_tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

          # Check if B already exists, if not create it as a new fact
          existing_b = atomspace.get_nodes_by_name(b.name, b.type).first?
          if existing_b
            # Update existing B with new truth value if it's more confident
            if new_tv.confidence > existing_b.truth_value.confidence
              existing_b.truth_value = new_tv
            end
            return existing_b
          else
            # Create new B fact
            return atomspace.add_node(b.type, b.name, new_tv)
          end
        end
      end

      nil
    end
  end

  # Abduction Rule: If A->B and C->B then A->C
  class AbductionRule < PLNRule
    def name : String
      "AbductionRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      # Applies to inheritance links
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.outgoing.size == 2

      # premise is A->B
      a, b = premise.outgoing[0], premise.outgoing[1]

      # Look for C->B (another link with same consequent B)
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

      inheritance_links.each do |link|
        next unless link.is_a?(AtomSpace::Link)
        next unless link.outgoing.size == 2
        next if link == premise # Don't use the same premise

        c, b2 = link.outgoing[0], link.outgoing[1]

        if b == b2 && a != c # Found C->B where B matches and C is different from A
          # Apply abduction: conclude A->C
          tv_ab = premise.truth_value
          tv_cb = link.truth_value

          # Abduction formula (simplified from OpenCog PLN)
          # Based on the idea that if both A and C lead to B,
          # then A and C might be related
          s_a = tv_ab.strength
          s_ab = tv_ab.strength
          s_c = tv_cb.strength
          s_cb = tv_cb.strength

          # Simplified abduction strength calculation
          # This is a basic version - the full OpenCog formula is more complex
          new_strength = (s_ab * s_cb) / (s_ab * s_cb + (1 - s_ab) * (1 - s_cb))
          new_confidence = [tv_ab.confidence, tv_cb.confidence].min * 0.6 # Lower confidence for abduction

          new_tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

          # Create A->C link (avoid creating A->A)
          if a != c
            return atomspace.add_link(
              AtomSpace::AtomType::INHERITANCE_LINK,
              [a, c],
              new_tv
            )
          end
        end
      end

      nil
    end
  end

  # Revision Rule: combine two truth values for the same statement
  # TV_rev = revision(TV1, TV2) with confidence-weighted strength
  class RevisionRule < PLNRule
    def name : String
      "RevisionRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      true # Can revise any atom that has a duplicate
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      # Find another atom with same structure but different TV
      candidates = if premise.is_a?(AtomSpace::Node)
                     atomspace.get_nodes_by_name(premise.name, premise.type)
                   else
                     atomspace.get_atoms_by_type(premise.type).select { |a| a == premise || structurally_equal?(a, premise) }
                   end

      candidates.each do |other|
        next if other.handle == premise.handle
        next unless structurally_equal?(other, premise)

        revised = PLN.revise_truth_values(premise.truth_value, other.truth_value)
        if revised.confidence > premise.truth_value.confidence
          premise.truth_value = revised
          return premise
        end
      end

      nil
    end

    private def structurally_equal?(a : AtomSpace::Atom, b : AtomSpace::Atom) : Bool
      return false unless a.type == b.type
      if a.is_a?(AtomSpace::Node) && b.is_a?(AtomSpace::Node)
        a.name == b.name
      elsif a.is_a?(AtomSpace::Link) && b.is_a?(AtomSpace::Link)
        a.outgoing.size == b.outgoing.size &&
          a.outgoing.zip(b.outgoing).all? { |x, y| structurally_equal?(x, y) }
      else
        false
      end
    end
  end

  # Conditional reasoning: P(B|A) from implication and evidence
  class ConditionalRule < PLNRule
    def name : String
      "ConditionalRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      premise.is_a?(AtomSpace::Link) &&
        (premise.type == AtomSpace::AtomType::INHERITANCE_LINK ||
          premise.type == AtomSpace::AtomType::IMPLICATION_LINK)
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.outgoing.size == 2

      a, b = premise.outgoing[0], premise.outgoing[1]
      tv_impl = premise.truth_value

      # Look for evidence about A
      evidence = if a.is_a?(AtomSpace::Node)
                   atomspace.get_nodes_by_name(a.name, a.type).first?
                 else
                   a
                 end
      return nil unless evidence

      # P(B|A) approximated by implication strength; update B's TV
      p_b_given_a = tv_impl.strength
      p_a = evidence.truth_value.strength
      p_b = p_b_given_a * p_a + 0.1 * (1.0 - p_a) # weak background
      conf = Math.min(tv_impl.confidence, evidence.truth_value.confidence) * 0.85

      new_tv = AtomSpace::SimpleTruthValue.new(p_b.clamp(0.0, 1.0), conf.clamp(0.0, 1.0))

      if b.is_a?(AtomSpace::Node)
        atomspace.add_node(b.type, b.name, new_tv)
      else
        atomspace.add_link(b.type, b.as(AtomSpace::Link).outgoing, new_tv)
      end
    end
  end

  # Evaluation Rule: evaluate a predicate application against known facts
  class EvaluationRule < PLNRule
    def name : String
      "EvaluationRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::EVALUATION_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.outgoing.size >= 2

      # If evaluation already has high confidence, nothing to do
      return nil if premise.truth_value.confidence >= 0.95

      # Look for similar evaluations (same predicate) to estimate TV
      pred = premise.outgoing[0]
      similar = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).select do |link|
        link.is_a?(AtomSpace::Link) && link.outgoing.size >= 1 && link.outgoing[0] == pred && link.handle != premise.handle
      end

      return nil if similar.empty?

      avg_s = similar.sum { |l| l.truth_value.strength } / similar.size
      avg_c = similar.sum { |l| l.truth_value.confidence } / similar.size * 0.7
      new_tv = AtomSpace::SimpleTruthValue.new(avg_s.clamp(0.0, 1.0), avg_c.clamp(0.0, 1.0))

      if new_tv.confidence > premise.truth_value.confidence
        premise.truth_value = new_tv
        premise
      else
        nil
      end
    end
  end

  # Fuzzy membership: map continuous values to graded membership truth values
  module FuzzyMembership
    # Triangular membership function centered at c with half-width w
    def self.triangular(x : Float64, center : Float64, width : Float64) : Float64
      return 0.0 if width <= 0.0
      dist = (x - center).abs
      return 0.0 if dist >= width
      1.0 - dist / width
    end

    # Trapezoidal membership
    def self.trapezoidal(x : Float64, a : Float64, b : Float64, c : Float64, d : Float64) : Float64
      return 0.0 if x < a || x > d
      return (x - a) / (b - a) if x < b && b > a
      return 1.0 if x <= c
      return (d - x) / (d - c) if d > c
      0.0
    end

    # Gaussian membership
    def self.gaussian(x : Float64, mean : Float64, sigma : Float64) : Float64
      return 0.0 if sigma <= 0.0
      Math.exp(-0.5 * ((x - mean) / sigma) ** 2)
    end

    # Convert membership grade to a SimpleTruthValue
    def self.to_truth_value(membership : Float64, confidence : Float64 = 0.9) : AtomSpace::SimpleTruthValue
      AtomSpace::SimpleTruthValue.new(membership.clamp(0.0, 1.0), confidence.clamp(0.0, 1.0))
    end
  end

  # Joint probability inference from independent (or weakly dependent) factors
  module JointProbability
    # Independent joint: P(A and B) = P(A) * P(B)
    def self.independent(tv_a : AtomSpace::TruthValue, tv_b : AtomSpace::TruthValue) : AtomSpace::SimpleTruthValue
      s = tv_a.strength * tv_b.strength
      c = tv_a.confidence * tv_b.confidence
      AtomSpace::SimpleTruthValue.new(s.clamp(0.0, 1.0), c.clamp(0.0, 1.0))
    end

    # Noisy-OR: P(A or B) = 1 - (1-P(A))*(1-P(B))
    def self.noisy_or(tv_a : AtomSpace::TruthValue, tv_b : AtomSpace::TruthValue) : AtomSpace::SimpleTruthValue
      s = 1.0 - (1.0 - tv_a.strength) * (1.0 - tv_b.strength)
      c = Math.min(tv_a.confidence, tv_b.confidence)
      AtomSpace::SimpleTruthValue.new(s.clamp(0.0, 1.0), c.clamp(0.0, 1.0))
    end

    # Conditional joint using P(A|B) approx: P(A and B) = P(A|B) * P(B)
    def self.conditional(tv_a_given_b : AtomSpace::TruthValue, tv_b : AtomSpace::TruthValue) : AtomSpace::SimpleTruthValue
      s = tv_a_given_b.strength * tv_b.strength
      c = tv_a_given_b.confidence * tv_b.confidence
      AtomSpace::SimpleTruthValue.new(s.clamp(0.0, 1.0), c.clamp(0.0, 1.0))
    end
  end

  # Higher-order reasoning: apply rules to links about links (meta-statements)
  class HigherOrderRule < PLNRule
    def name : String
      "HigherOrderRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      return false unless premise.is_a?(AtomSpace::Link)
      # Higher-order if any outgoing atom is itself a link
      premise.outgoing.any? { |o| o.is_a?(AtomSpace::Link) }
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.outgoing.size == 2

      # If we have Implication(Inheritance(A,B), Inheritance(B,C)),
      # try to conclude Inheritance(A,C) with discounted confidence
      left, right = premise.outgoing[0], premise.outgoing[1]
      return nil unless left.is_a?(AtomSpace::Link) && right.is_a?(AtomSpace::Link)
      return nil unless left.type == AtomSpace::AtomType::INHERITANCE_LINK
      return nil unless right.type == AtomSpace::AtomType::INHERITANCE_LINK
      return nil unless left.outgoing.size == 2 && right.outgoing.size == 2

      a, b1 = left.outgoing[0], left.outgoing[1]
      b2, c = right.outgoing[0], right.outgoing[1]
      return nil unless b1 == b2

      s = premise.truth_value.strength * left.truth_value.strength * right.truth_value.strength
      conf = premise.truth_value.confidence * 0.5
      new_tv = AtomSpace::SimpleTruthValue.new(s.clamp(0.0, 1.0), conf.clamp(0.0, 1.0))

      atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, c], new_tv)
    end
  end

  # PLN truth value revision formula (OpenCog-style)
  def self.revise_truth_values(tv1 : AtomSpace::TruthValue, tv2 : AtomSpace::TruthValue) : AtomSpace::SimpleTruthValue
    c1 = tv1.confidence
    c2 = tv2.confidence
    total_c = c1 + c2 - c1 * c2
    return AtomSpace::SimpleTruthValue.new(tv1.strength, c1) if total_c <= 0.0

    # Confidence-weighted strength
    w1 = c1 / (c1 + c2)
    w2 = c2 / (c1 + c2)
    strength = w1 * tv1.strength + w2 * tv2.strength
    AtomSpace::SimpleTruthValue.new(strength.clamp(0.0, 1.0), total_c.clamp(0.0, 1.0))
  end

  # PLN Reasoning Engine
  class PLNEngine
    @rules : Array(PLNRule)

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @rules = [
        DeductionRule.new,
        InversionRule.new,
        ModusPonensRule.new,
        AbductionRule.new,
        RevisionRule.new,
        ConditionalRule.new,
        EvaluationRule.new,
        HigherOrderRule.new,
      ] of PLNRule
    end

    def add_rule(rule : PLNRule)
      @rules << rule
    end

    def reason(max_iterations : Int32 = 10) : Array(AtomSpace::Atom)
      new_atoms = [] of AtomSpace::Atom
      iterations = 0

      while iterations < max_iterations
        iteration_new_atoms = [] of AtomSpace::Atom
        initial_atomspace_size = @atomspace.size

        # Apply rules to all atoms
        @atomspace.get_all_atoms.each do |atom|
          @rules.each do |rule|
            if rule.applies_to?(atom)
              new_atom = rule.apply(atom, @atomspace)
              if new_atom
                # Check if this actually added a new atom to the atomspace
                if @atomspace.size > initial_atomspace_size
                  iteration_new_atoms << new_atom
                  initial_atomspace_size = @atomspace.size # Update for next check
                  CogUtil::Logger.debug("PLN: Applied #{rule.name} to #{atom}, created #{new_atom}")
                end
              end
            end
          end
        end

        # If no new atoms were created, we're done
        break if iteration_new_atoms.empty?

        new_atoms.concat(iteration_new_atoms)
        iterations += 1
      end

      CogUtil::Logger.info("PLN: Generated #{new_atoms.size} new atoms in #{iterations} iterations")
      new_atoms
    end

    # Forward chaining inference
    def forward_chain(target_type : AtomSpace::AtomType, max_steps : Int32 = 5) : Array(AtomSpace::Atom)
      results = [] of AtomSpace::Atom

      max_steps.times do
        step_results = reason(1)
        break if step_results.empty?

        step_results.each do |atom|
          results << atom if atom.type == target_type
        end
      end

      results
    end

    # Backward chaining inference
    def backward_chain(goal : AtomSpace::Atom) : Bool
      # Check if goal already exists
      return true if @atomspace.contains?(goal)

      # Try to derive the goal using available rules
      @rules.each do |rule|
        # This is a simplified backward chaining
        # In practice, this would be more sophisticated
        if rule.applies_to?(goal)
          premises = find_premises_for_goal(goal, rule)
          premises.each do |premise|
            if @atomspace.contains?(premise)
              derived = rule.apply(premise, @atomspace)
              return true if derived && derived == goal
            end
          end
        end
      end

      false
    end

    private def find_premises_for_goal(goal : AtomSpace::Atom, rule : PLNRule) : Array(AtomSpace::Atom)
      # This would contain rule-specific logic to find premises
      # that could lead to the goal
      [] of AtomSpace::Atom
    end
  end

  # Initialize PLN module
  def self.initialize
    CogUtil::Logger.info("PLN #{VERSION} initialized")
  end

  # Convenience method to create PLN engine
  def self.create_engine(atomspace : AtomSpace::AtomSpace) : PLNEngine
    PLNEngine.new(atomspace)
  end
end
