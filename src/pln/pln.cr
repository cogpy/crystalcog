# Crystal implementation of PLN (Probabilistic Logic Networks)
# Converted from pln/opencog/pln/

require "../atomspace/atomspace_main"
require "../cogutil/cogutil"

module PLN
  VERSION = "0.1.0"

  # PLN strength formulas (Goertzel, Iklé, Goertzel and Heljakka,
  # "Probabilistic Logic Networks", 2008), under the usual independence
  # assumptions. `s_ab` reads P(B|A); `s_a` is the term probability P(A).
  #
  # A node carries a term probability when its truth value has confidence
  # above zero. Without term probabilities each formula falls back to the
  # form that needs none, so graphs of plain nodes reason as before.
  module Formulas
    EPSILON = 1.0e-9

    # P(B|not A) assumed by modus ponens when nothing better is known.
    BACKGROUND_PROBABILITY = 0.2

    def self.term_probability(atom : AtomSpace::Atom) : Float64?
      tv = atom.truth_value
      tv.confidence > 0.0 ? tv.strength.clamp(0.0, 1.0) : nil
    end

    # Whether P(B|A) = s_ab is possible at all given P(A) and P(B).
    def self.consistent?(s_a : Float64, s_b : Float64, s_ab : Float64) : Bool
      return true if s_a <= EPSILON
      lower = Math.max((s_a + s_b - 1.0) / s_a, 0.0)
      upper = Math.min(s_b / s_a, 1.0)
      s_ab >= lower - 1.0e-6 && s_ab <= upper + 1.0e-6
    end

    # A->B, B->C |- A->C:
    #   s_ac = s_ab*s_bc + (1 - s_ab)*(s_c - s_b*s_bc)/(1 - s_b)
    # The second term is the part of C reached from A outside B.
    def self.deduction(s_ab : Float64, s_bc : Float64, s_b : Float64? = nil, s_c : Float64? = nil) : Float64
      through_b = s_ab * s_bc
      return through_b.clamp(0.0, 1.0) unless s_b && s_c
      return through_b.clamp(0.0, 1.0) if s_b >= 1.0 - EPSILON

      outside_b = (s_c - s_b * s_bc) / (1.0 - s_b)
      (through_b + (1.0 - s_ab) * outside_b.clamp(0.0, 1.0)).clamp(0.0, 1.0)
    end

    # A->B |- B->A by Bayes' rule: s_ba = s_ab*s_a/s_b.
    def self.inversion(s_ab : Float64, s_a : Float64? = nil, s_b : Float64? = nil) : Float64
      return s_ab.clamp(0.0, 1.0) unless s_a && s_b
      return 0.0 if s_b <= EPSILON
      (s_ab * s_a / s_b).clamp(0.0, 1.0)
    end

    # A->B, C->B |- A->C: invert C->B to B->C, then deduce through B.
    def self.abduction(s_ab : Float64, s_cb : Float64, s_a : Float64? = nil,
                       s_b : Float64? = nil, s_c : Float64? = nil) : Float64
      unless s_a && s_b && s_c
        # No term probabilities: the odds that A and C agree about B.
        agree = s_ab * s_cb + (1.0 - s_ab) * (1.0 - s_cb)
        return agree > 0.0 ? (s_ab * s_cb / agree).clamp(0.0, 1.0) : 0.0
      end
      deduction(s_ab, inversion(s_cb, s_c, s_b), s_b, s_c)
    end

    # A->B, A->C |- B->C: invert A->B to B->A, then deduce through A.
    def self.induction(s_ab : Float64, s_ac : Float64, s_a : Float64? = nil,
                       s_b : Float64? = nil, s_c : Float64? = nil) : Float64
      unless s_a && s_b && s_c
        agree = s_ab * s_ac + (1.0 - s_ab) * (1.0 - s_ac)
        return agree > 0.0 ? (s_ab * s_ac / agree).clamp(0.0, 1.0) : 0.0
      end
      deduction(inversion(s_ab, s_a, s_b), s_ac, s_a, s_c)
    end

    # A->B, A |- B: s_b = s_ab*s_a + P(B|not A)*(1 - s_a).
    def self.modus_ponens(s_ab : Float64, s_a : Float64,
                          background : Float64 = BACKGROUND_PROBABILITY) : Float64
      (s_ab * s_a + background * (1.0 - s_a)).clamp(0.0, 1.0)
    end
  end

  # A per-iteration read view for the built-in inheritance rules. AtomSpace
  # exposes snapshot arrays and Link#outgoing returns a detached copy; this
  # keeps the repeated rule scans and copies local to PLN.
  #
  # PLN uses it only for its stock rules. Adding a custom rule selects the
  # direct public rule API, preserving historical custom-rule behavior.
  class InferenceContext
    getter facts : Array(AtomSpace::Atom)
    getter inheritance_links : Array(AtomSpace::Atom)

    @facts_by_handle : Hash(AtomSpace::Handle, AtomSpace::Atom)
    @inheritance_by_subject : Hash(AtomSpace::Handle, Array(AtomSpace::Atom))
    @inheritance_by_object : Hash(AtomSpace::Handle, Array(AtomSpace::Atom))
    @handle_identity_safe : Bool

    def initialize(atomspace : AtomSpace::AtomSpace, @facts : Array(AtomSpace::Atom))
      @facts_by_handle = Hash(AtomSpace::Handle, AtomSpace::Atom).new
      @facts.each { |atom| @facts_by_handle[atom.handle] = atom }
      @inheritance_links = [] of AtomSpace::Atom
      @inheritance_by_subject = Hash(AtomSpace::Handle, Array(AtomSpace::Atom)).new
      @inheritance_by_object = Hash(AtomSpace::Handle, Array(AtomSpace::Atom)).new
      @handle_identity_safe = true
      refresh_inheritance(atomspace)
    end

    # Rebuild the inheritance index from the AtomSpace.
    def refresh_inheritance(atomspace : AtomSpace::AtomSpace)
      @inheritance_links = [] of AtomSpace::Atom
      @inheritance_by_subject.clear
      @inheritance_by_object.clear
      @handle_identity_safe = true

      atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).each do |atom|
        add_inheritance(atom, atomspace)
      end
    end

    # Index one inheritance link accepted during this iteration. New links
    # go last, which is where the AtomSpace's own type index puts them, so
    # candidates keep their order without rebuilding the whole index.
    def add_inheritance(atom : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : Nil
      @inheritance_links << atom
      return unless atom.is_a?(AtomSpace::Link)
      return unless atom.arity == 2

      subject = atom[0]
      object = atom[1]
      # AtomSpace indexes links by child handle but does not canonicalize
      # supplied child atoms. If any link is detached, preserve the original
      # Atom#== matching semantics with the fallback arrays below.
      @handle_identity_safe &&= atomspace.contains?(subject) && atomspace.contains?(object)
      (@inheritance_by_subject[subject.handle] ||= [] of AtomSpace::Atom) << atom
      (@inheritance_by_object[object.handle] ||= [] of AtomSpace::Atom) << atom
    end

    def links_from(subject : AtomSpace::Atom) : Array(AtomSpace::Atom)
      return @inheritance_links unless @handle_identity_safe

      @inheritance_by_subject[subject.handle]? || [] of AtomSpace::Atom
    end

    def links_to(object : AtomSpace::Atom) : Array(AtomSpace::Atom)
      return @inheritance_links unless @handle_identity_safe

      @inheritance_by_object[object.handle]? || [] of AtomSpace::Atom
    end

    def handle_identity_safe? : Bool
      @handle_identity_safe
    end

    def fact(atom : AtomSpace::Atom) : AtomSpace::Atom?
      return @facts_by_handle[atom.handle]? if @handle_identity_safe

      @facts.find { |candidate| candidate == atom }
    end
  end

  # What the rules of one engine have derived, kept small because a dense
  # graph has far more derivations than links.
  #
  # - Which derivations were used. Each is one piece of evidence for its
  #   conclusion and must count once, however often the rule meets it.
  # - Which asserted links each link rests on. Two pieces of evidence are
  #   combined only when they share none: what is in a conclusion already
  #   is not counted again. That also stops a conclusion from coming back
  #   as evidence for its own premises: A->B gives B->A by inversion, and
  #   inverting that again says nothing new about A->B, nor does any
  #   longer way round.
  class Provenance
    DEDUCTION = 0_u64
    ABDUCTION = 1_u64
    INVERSION = 2_u64

    # One 64-bit key per derivation: the rule in the top two bits, then the
    # two premise handles. Exact while handles stay below 2^30; beyond that
    # two derivations may share a key and the later one is skipped.
    @used = Set(UInt64).new
    @parents = Hash(AtomSpace::Handle, {AtomSpace::Handle, AtomSpace::Handle}).new
    # What each link's truth value rests on: the asserted links behind it,
    # as their numbers in ascending order. An asserted link rests on itself
    # and gets its number the first time it is asked about.
    @evidence = Hash(AtomSpace::Handle, Array(Int32)).new
    @asserted = 0

    # True the first time this rule meets this pair of premises.
    def first_use?(rule : UInt64, premise : AtomSpace::Atom, other : AtomSpace::Atom = premise) : Bool
      @used.add?((rule << 62) ^ (premise.handle << 31) ^ other.handle)
    end

    # `conclusion` was drawn from these premises and rests on what they do.
    def record(conclusion : AtomSpace::Atom, premise : AtomSpace::Atom, other : AtomSpace::Atom = premise) : Nil
      @parents[conclusion.handle] = {premise.handle, other.handle}
      @evidence[conclusion.handle] = union(evidence(premise), evidence(other))
    end

    # `known` has taken the evidence of these premises as well.
    def revised(known : AtomSpace::Atom, premise : AtomSpace::Atom, other : AtomSpace::Atom = premise) : Nil
      gained = other.same?(premise) ? evidence(premise) : union(evidence(premise), evidence(other))
      @evidence[known.handle] = union(evidence(known), gained)
    end

    # The asserted links this link rests on, by number.
    def evidence(atom : AtomSpace::Atom) : Array(Int32)
      @evidence[atom.handle] ||= [@asserted += 1]
    end

    # Was `candidate` one of the links `derived` was drawn from?
    def parent?(candidate : AtomSpace::Atom, derived : AtomSpace::Atom) : Bool
      parents = @parents[derived.handle]? || return false
      parents[0] == candidate.handle || parents[1] == candidate.handle
    end

    # Does `derived` rest on any of what `other` rests on?
    def shares_evidence?(derived : AtomSpace::Atom, other : AtomSpace::Atom) : Bool
      overlap?(evidence(derived), evidence(other))
    end

    # May `evidence` (the premises of a new derivation) revise `known`?
    # Only when they rest on none of the asserted links `known` rests on.
    # Evidence that is already in a conclusion is not counted again, which
    # also keeps a conclusion from coming back, however far round, as
    # support for itself or for its own premises.
    def independent?(known : AtomSpace::Atom, *evidence : AtomSpace::Atom) : Bool
      mine = evidence(known)
      evidence.none? { |premise| overlap?(mine, evidence(premise)) }
    end

    # Two ascending lists have a number in common.
    private def overlap?(a : Array(Int32), b : Array(Int32)) : Bool
      i = j = 0
      while i < a.size && j < b.size
        x = a.unsafe_fetch(i)
        y = b.unsafe_fetch(j)
        return true if x == y
        if x < y
          i += 1
        else
          j += 1
        end
      end
      false
    end

    # Two ascending lists as one, each number once.
    private def union(a : Array(Int32), b : Array(Int32)) : Array(Int32)
      return a if a.same?(b)
      merged = Array(Int32).new(a.size + b.size)
      i = j = 0
      while i < a.size && j < b.size
        x = a.unsafe_fetch(i)
        y = b.unsafe_fetch(j)
        if x < y
          merged << x
          i += 1
        elsif y < x
          merged << y
          j += 1
        else
          merged << x
          i += 1
          j += 1
        end
      end
      while i < a.size
        merged << a.unsafe_fetch(i)
        i += 1
      end
      while j < b.size
        merged << b.unsafe_fetch(j)
        j += 1
      end
      merged
    end

    def derivations : Int32
      @used.size
    end
  end

  # PLN Rule interface
  abstract class PLNRule
    abstract def name : String
    abstract def applies_to?(premise : AtomSpace::Atom) : Bool
    abstract def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?

    # Custom rules retain the public apply contract. Built-in rules override
    # this to reuse the default engine's per-iteration inference context.
    def apply_with_context(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, context : InferenceContext) : AtomSpace::Atom?
      apply(premise, atomspace)
    end
  end

  # Deduction Rule: If A->B and B->C then A->C
  class DeductionRule < PLNRule
    # Shared by the rules of one engine, so each sees what the others derived.
    def initialize(@provenance : Provenance = Provenance.new)
    end

    def name : String
      "DeductionRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      # Check if we have two inheritance links that can be chained
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      apply_from_candidates(
        premise,
        atomspace,
        atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
      )
    end

    def apply_with_context(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, context : InferenceContext) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.arity == 2

      apply_from_candidates(premise, atomspace, context.links_from(premise[1]))
    end

    # Draws the first conclusion not yet in the AtomSpace, so every chain
    # through B gets its turn over successive calls. A chain that leads to
    # a conclusion already known revises that conclusion's truth value,
    # once. When nothing new is left, the first chain's conclusion is
    # returned as it stands.
    private def apply_from_candidates(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, inheritance_links : Array(AtomSpace::Atom)) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.arity == 2

      # Look for another inheritance link with matching middle term.
      a, b = premise[0], premise[1]
      first_conclusion : AtomSpace::Atom? = nil

      inheritance_links.each do |link|
        next unless link.is_a?(AtomSpace::Link)
        next unless link.arity == 2
        next unless b == link[0] # Found matching chain A->B, B->C

        if known = atomspace.find_link(AtomSpace::AtomType::INHERITANCE_LINK, a, link[1])
          first_conclusion ||= known
          # A conclusion is not evidence for itself or for its own premises.
          if @provenance.first_use?(Provenance::DEDUCTION, premise, link) && @provenance.independent?(known, premise, link)
            known.truth_value = PLN.revise_truth_values(known.truth_value, *conclusion_values(premise, link))
            @provenance.revised(known, premise, link)
          end
          next
        end

        @provenance.first_use?(Provenance::DEDUCTION, premise, link)
        strength, confidence = conclusion_values(premise, link)
        conclusion = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, link[1]],
          AtomSpace::SimpleTruthValue.new(strength, confidence))
        @provenance.record(conclusion, premise, link)
        return conclusion
      end

      first_conclusion
    end

    # Strength and confidence of A->C from A->B and B->C.
    private def conclusion_values(premise : AtomSpace::Link, link : AtomSpace::Link) : {Float64, Float64}
      tv_ab = premise.truth_value
      tv_bc = link.truth_value

      new_strength = Formulas.deduction(tv_ab.strength, tv_bc.strength,
        Formulas.term_probability(premise[1]), Formulas.term_probability(link[1]))
      new_confidence = tv_ab.confidence * tv_bc.confidence * 0.9 # Discount factor
      {new_strength, new_confidence}
    end
  end

  # Inversion Rule: If A->B then B->A (with inverted strength)
  class InversionRule < PLNRule
    # Shared by the rules of one engine, so each sees what the others derived.
    def initialize(@provenance : Provenance = Provenance.new)
    end

    def name : String
      "InversionRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.arity == 2

      a, b = premise[0], premise[1]

      # Bayes' rule when both terms carry a probability; otherwise the
      # strength is kept and only the confidence is discounted.
      tv = premise.truth_value
      inverted_strength = Formulas.inversion(tv.strength,
        Formulas.term_probability(a), Formulas.term_probability(b))
      inverted_confidence = tv.confidence * 0.8 # Discount for inversion

      inverted_tv = AtomSpace::SimpleTruthValue.new(
        inverted_strength.clamp(0.0, 1.0),
        inverted_confidence.clamp(0.0, 1.0)
      )

      # B->A may be known already, asserted or derived another way. This
      # link is then one more piece of evidence for it, counted once.
      if known = atomspace.find_link(AtomSpace::AtomType::INHERITANCE_LINK, b, a)
        if @provenance.first_use?(Provenance::INVERSION, premise) && @provenance.independent?(known, premise)
          known.truth_value = PLN.revise_truth_values(known.truth_value, inverted_tv)
          @provenance.revised(known, premise)
        end
        return known
      end

      @provenance.first_use?(Provenance::INVERSION, premise)
      inverse = atomspace.add_link(
        AtomSpace::AtomType::INHERITANCE_LINK,
        [b, a],
        inverted_tv
      )
      @provenance.record(inverse, premise)
      inverse
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
      return nil unless premise.arity == 2

      # premise is A->B
      a, b = premise[0], premise[1]

      # Look for A in the atomspace (as a fact)
      atoms = atomspace.get_all_atoms
      atoms.each do |atom|
        # Check if this atom is A with sufficient confidence
        if atom == a && atom.truth_value.confidence > 0.5
          # We have both A->B and A, so we can conclude B
          tv_ab = premise.truth_value
          tv_a = atom.truth_value

          # P(B) = P(B|A) * P(A) + P(B|¬A) * P(¬A)
          new_strength = Formulas.modus_ponens(tv_ab.strength, tv_a.strength)
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

    def apply_with_context(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, context : InferenceContext) : AtomSpace::Atom?
      # Detached consequents may become new facts earlier in this iteration.
      # The historical API scans the live graph, not its initial fact snapshot.
      return apply(premise, atomspace) unless context.handle_identity_safe?

      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.arity == 2

      a, b = premise[0], premise[1]
      fact = context.fact(a)
      return nil unless fact
      return nil unless fact.truth_value.confidence > 0.5

      tv_ab = premise.truth_value
      tv_a = fact.truth_value
      new_strength = Formulas.modus_ponens(tv_ab.strength, tv_a.strength)
      new_confidence = [tv_ab.confidence, tv_a.confidence].min * 0.9
      new_tv = AtomSpace::SimpleTruthValue.new(new_strength, new_confidence)

      existing_b = atomspace.get_nodes_by_name(b.name, b.type).first?
      if existing_b
        if new_tv.confidence > existing_b.truth_value.confidence
          existing_b.truth_value = new_tv
        end
        existing_b
      else
        atomspace.add_node(b.type, b.name, new_tv)
      end
    end
  end

  # Abduction Rule: If A->B and C->B then A->C
  class AbductionRule < PLNRule
    # Shared by the rules of one engine, so each sees what the others derived.
    def initialize(@provenance : Provenance = Provenance.new)
    end

    def name : String
      "AbductionRule"
    end

    def applies_to?(premise : AtomSpace::Atom) : Bool
      # Applies to inheritance links
      premise.is_a?(AtomSpace::Link) &&
        premise.type == AtomSpace::AtomType::INHERITANCE_LINK
    end

    def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
      apply_from_candidates(
        premise,
        atomspace,
        atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
      )
    end

    def apply_with_context(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, context : InferenceContext) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.arity == 2

      apply_from_candidates(premise, atomspace, context.links_to(premise[1]))
    end

    # As for deduction: the first conclusion that is new; a pair of
    # premises that leads to a known conclusion revises it once.
    private def apply_from_candidates(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, inheritance_links : Array(AtomSpace::Atom)) : AtomSpace::Atom?
      return nil unless premise.is_a?(AtomSpace::Link)
      return nil unless premise.arity == 2

      # premise is A->B
      a, b = premise[0], premise[1]
      first_conclusion : AtomSpace::Atom? = nil

      inheritance_links.each do |link|
        next unless link.is_a?(AtomSpace::Link)
        next unless link.arity == 2
        next if link == premise # Don't use the same premise

        c = link[0]
        # Found C->B where B matches and C is different from A
        next unless b == link[1] && a != c

        if known = atomspace.find_link(AtomSpace::AtomType::INHERITANCE_LINK, a, c)
          first_conclusion ||= known
          if @provenance.first_use?(Provenance::ABDUCTION, premise, link) && @provenance.independent?(known, premise, link)
            known.truth_value = PLN.revise_truth_values(known.truth_value, *conclusion_values(premise, link))
            @provenance.revised(known, premise, link)
          end
          next
        end

        @provenance.first_use?(Provenance::ABDUCTION, premise, link)
        strength, confidence = conclusion_values(premise, link)
        conclusion = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, c],
          AtomSpace::SimpleTruthValue.new(strength, confidence))
        @provenance.record(conclusion, premise, link)
        return conclusion
      end

      first_conclusion
    end

    # Strength and confidence of A->C from A->B and C->B.
    private def conclusion_values(premise : AtomSpace::Link, link : AtomSpace::Link) : {Float64, Float64}
      tv_ab = premise.truth_value
      tv_cb = link.truth_value

      new_strength = Formulas.abduction(tv_ab.strength, tv_cb.strength,
        Formulas.term_probability(premise[0]), Formulas.term_probability(premise[1]), Formulas.term_probability(link[0]))
      new_confidence = Math.min(tv_ab.confidence, tv_cb.confidence) * 0.6 # Lower confidence for abduction
      {new_strength.clamp(0.0, 1.0), new_confidence.clamp(0.0, 1.0)}
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
    revise_truth_values(tv1, tv2.strength, tv2.confidence)
  end

  # The same, with the second truth value given as two numbers so that a
  # rule revising many conclusions need not build an object for each.
  def self.revise_truth_values(tv1 : AtomSpace::TruthValue, strength2 : Float64, confidence2 : Float64) : AtomSpace::SimpleTruthValue
    c1 = tv1.confidence
    c2 = confidence2
    total_c = c1 + c2 - c1 * c2
    return AtomSpace::SimpleTruthValue.new(tv1.strength, c1) if total_c <= 0.0

    # Confidence-weighted strength
    w1 = c1 / (c1 + c2)
    w2 = c2 / (c1 + c2)
    strength = w1 * tv1.strength + w2 * strength2
    AtomSpace::SimpleTruthValue.new(strength.clamp(0.0, 1.0), total_c.clamp(0.0, 1.0))
  end

  # PLN Reasoning Engine
  class PLNEngine
    @rules : Array(PLNRule)
    @has_custom_rules : Bool

    def initialize(@atomspace : AtomSpace::AtomSpace)
      provenance = Provenance.new
      @rules = [
        DeductionRule.new(provenance),
        InversionRule.new(provenance),
        ModusPonensRule.new,
        AbductionRule.new(provenance),
      ] of PLNRule
      @has_custom_rules = false
    end

    # Opt in to the revision, conditional, evaluation and higher-order rules.
    # They rescan the AtomSpace per premise and may update existing truth
    # values, so they run on the direct-scan path rather than the stock context.
    def add_advanced_rules : self
      add_rule(RevisionRule.new)
      add_rule(ConditionalRule.new)
      add_rule(EvaluationRule.new)
      add_rule(HigherOrderRule.new)
      self
    end

    def add_rule(rule : PLNRule)
      @rules << rule
      @has_custom_rules = true
    end

    def reason(max_iterations : Int32 = 10) : Array(AtomSpace::Atom)
      new_atoms = [] of AtomSpace::Atom
      iterations = 0

      while iterations < max_iterations
        iteration_new_atoms = [] of AtomSpace::Atom
        initial_atomspace_size = @atomspace.size

        # Apply rules to a snapshot of atoms. The stock rule set uses the
        # PLN-local context; any caller-added rule retains direct scan behavior.
        iteration_atoms = @atomspace.get_all_atoms
        context = @has_custom_rules ? nil : InferenceContext.new(@atomspace, iteration_atoms)

        iteration_atoms.each do |atom|
          @rules.each do |rule|
            if rule.applies_to?(atom)
              new_atom = if context
                           rule.apply_with_context(atom, @atomspace, context)
                         else
                           rule.apply(atom, @atomspace)
                         end
              if new_atom
                # Check if this actually added a new atom to the atomspace
                if @atomspace.size > initial_atomspace_size
                  iteration_new_atoms << new_atom
                  initial_atomspace_size = @atomspace.size # Update for next check
                  if context && new_atom.type == AtomSpace::AtomType::INHERITANCE_LINK
                    context.add_inheritance(new_atom, @atomspace)
                  end
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

      # Try to derive the goal from existing premises via known rules
      find_premises_for_goal(goal).each do |premise|
        @rules.each do |rule|
          next unless rule.applies_to?(premise)
          derived = rule.apply(premise, @atomspace)
          next unless derived

          # Goal reached if we produced an equivalent atom (same type/structure)
          if atoms_match_goal?(derived, goal)
            return true
          end
        end
      end

      # One more forward-ish sweep: run a single reasoning iteration and re-check
      reason(1)
      @atomspace.contains?(goal) || find_equivalent(goal) != nil
    end

    # Find premises in the atomspace that could produce the goal under PLN rules
    private def find_premises_for_goal(goal : AtomSpace::Atom) : Array(AtomSpace::Atom)
      premises = [] of AtomSpace::Atom

      case goal
      when AtomSpace::Link
        return premises unless goal.outgoing.size == 2
        target_a, target_b = goal.outgoing[0], goal.outgoing[1]

        case goal.type
        when AtomSpace::AtomType::INHERITANCE_LINK
          # Deduction: A->B, B->C => A->C  — look for middle term B
          inheritance_links = @atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
          inheritance_links.each do |link|
            next unless link.is_a?(AtomSpace::Link) && link.outgoing.size == 2
            # A->B where A matches goal source
            if link.outgoing[0] == target_a
              middle = link.outgoing[1]
              # Need B->C
              has_bc = inheritance_links.any? do |other|
                other.is_a?(AtomSpace::Link) && other.outgoing.size == 2 &&
                  other.outgoing[0] == middle && other.outgoing[1] == target_b
              end
              premises << link if has_bc
            end
          end

          # Inversion: B->A could produce A->B
          inheritance_links.each do |link|
            next unless link.is_a?(AtomSpace::Link) && link.outgoing.size == 2
            if link.outgoing[0] == target_b && link.outgoing[1] == target_a
              premises << link
            end
          end

          # Abduction: A->B and C->B can relate A and C
          inheritance_links.each do |link|
            next unless link.is_a?(AtomSpace::Link) && link.outgoing.size == 2
            if link.outgoing[0] == target_a
              premises << link
            end
          end
        else
          # Generic: any atom of matching premise-friendly types
          @atomspace.get_atoms_by_type(goal.type).each { |a| premises << a }
        end
      else
        # Node goals: look for inheritance links that conclude the node via modus ponens
        inheritance_links = @atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
        inheritance_links.each do |link|
          next unless link.is_a?(AtomSpace::Link) && link.outgoing.size == 2
          premises << link if link.outgoing[1] == goal
        end
      end

      premises.uniq!
      premises
    end

    private def atoms_match_goal?(derived : AtomSpace::Atom, goal : AtomSpace::Atom) : Bool
      return true if derived == goal
      return false unless derived.type == goal.type

      if derived.link? && goal.link?
        return false unless derived.outgoing.size == goal.outgoing.size
        derived.outgoing.zip(goal.outgoing).all? { |d, g| d == g }
      elsif derived.responds_to?(:name) && goal.responds_to?(:name)
        derived.name == goal.name
      else
        false
      end
    end

    private def find_equivalent(goal : AtomSpace::Atom) : AtomSpace::Atom?
      @atomspace.get_atoms_by_type(goal.type).find { |atom| atoms_match_goal?(atom, goal) }
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

  # Engine with the stock rules plus the advanced rule set.
  def self.create_advanced_engine(atomspace : AtomSpace::AtomSpace) : PLNEngine
    PLNEngine.new(atomspace).add_advanced_rules
  end
end
