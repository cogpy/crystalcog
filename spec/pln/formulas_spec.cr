require "spec"
require "../../src/pln/pln"

describe PLN::Formulas do
  it "reads a term probability only from nodes that carry one" do
    space = AtomSpace::AtomSpace.new
    plain = space.add_concept_node("plain")
    known = space.add_concept_node("known", AtomSpace::SimpleTruthValue.new(0.3, 0.8))
    PLN::Formulas.term_probability(plain).should be_nil
    PLN::Formulas.term_probability(known).should eq(0.3)
  end

  it "deduces through the middle term and around it" do
    # Without term probabilities only the path through B counts.
    PLN::Formulas.deduction(0.8, 0.9).should be_close(0.72, 1e-12)
    # 0.72 + (1 - 0.8) * (0.6 - 0.5*0.9) / (1 - 0.5)
    PLN::Formulas.deduction(0.8, 0.9, 0.5, 0.6).should be_close(0.78, 1e-12)
    # C wholly inside B: nothing of C lies outside B.
    PLN::Formulas.deduction(0.8, 0.9, 0.5, 0.45).should be_close(0.72, 1e-12)
    # B is everything, so the formula has no "outside B" to divide by.
    PLN::Formulas.deduction(0.8, 0.9, 1.0, 0.9).should be_close(0.72, 1e-12)
    PLN::Formulas.deduction(1.0, 1.0, 0.5, 0.7).should eq(1.0)
  end

  it "matches the frequencies of a population built on its independence assumption" do
    # Membership of C depends on B alone, as the deduction formula assumes.
    random = Random.new(2008)
    s_a, s_ab, s_ab_out, s_bc, s_bc_out = 0.3, 0.7, 0.2, 0.8, 0.1
    a = b = c = ab = bc = ac = 0
    200_000.times do
      in_a = random.rand < s_a
      in_b = random.rand < (in_a ? s_ab : s_ab_out)
      in_c = random.rand < (in_b ? s_bc : s_bc_out)
      a += 1 if in_a
      b += 1 if in_b
      c += 1 if in_c
      ab += 1 if in_a && in_b
      bc += 1 if in_b && in_c
      ac += 1 if in_a && in_c
    end
    total = 200_000.0
    predicted = PLN::Formulas.deduction(ab / a, bc / b, b / total, c / total)
    predicted.should be_close(ac / a, 0.01)
    # The product alone misses the members of C outside B.
    (ab / a * bc / b).should be < ac / a - 0.02

    # Bayes: P(A|B) from P(B|A).
    PLN::Formulas.inversion(ab / a, a / total, b / total).should be_close(ab / b, 1e-9)
  end

  it "inverts with Bayes' rule and keeps the strength when the terms are unknown" do
    PLN::Formulas.inversion(0.8, 0.3, 0.6).should be_close(0.4, 1e-12)
    PLN::Formulas.inversion(0.8).should eq(0.8)
    PLN::Formulas.inversion(0.8, 0.3, 0.0).should eq(0.0)
    PLN::Formulas.inversion(0.9, 0.9, 0.3).should eq(1.0) # clamped: the inputs are inconsistent
    PLN::Formulas.consistent?(0.9, 0.3, 0.9).should be_false
    PLN::Formulas.consistent?(0.3, 0.6, 0.8).should be_true
    PLN::Formulas.consistent?(0.8, 0.9, 0.5).should be_false # A and B must overlap more
  end

  it "builds abduction and induction from inversion and deduction" do
    # A->B, C->B |- A->C: B->C = 0.5*0.4/0.5 = 0.4, then deduce through B.
    PLN::Formulas.abduction(0.8, 0.5, 0.2, 0.5, 0.4).should be_close(
      PLN::Formulas.deduction(0.8, 0.4, 0.5, 0.4), 1e-12)
    PLN::Formulas.abduction(0.8, 0.5, 0.2, 0.5, 0.4).should be_close(0.4, 1e-12)
    # A->B, A->C |- B->C: B->A = 0.8*0.2/0.5 = 0.32, then deduce through A.
    PLN::Formulas.induction(0.8, 0.6, 0.2, 0.5, 0.4).should be_close(
      PLN::Formulas.deduction(0.32, 0.6, 0.2, 0.4), 1e-12)
    # Without term probabilities: the odds that the two premises agree.
    PLN::Formulas.abduction(0.9, 0.8).should be_close(0.72 / (0.72 + 0.02), 1e-12)
    PLN::Formulas.abduction(1.0, 0.0).should eq(0.0)
    PLN::Formulas.induction(0.9, 0.8).should be_close(0.72 / 0.74, 1e-12)
  end

  it "applies modus ponens with a background probability" do
    PLN::Formulas.modus_ponens(0.9, 1.0).should eq(0.9)
    PLN::Formulas.modus_ponens(0.9, 0.5).should be_close(0.55, 1e-12)
    PLN::Formulas.modus_ponens(0.9, 0.5, background: 0.0).should be_close(0.45, 1e-12)
  end
end

describe "PLN rules with term probabilities" do
  it "uses the full deduction formula when the nodes carry probabilities" do
    space = AtomSpace::AtomSpace.new
    tv = ->(s : Float64, c : Float64) { AtomSpace::SimpleTruthValue.new(s, c) }
    penguin = space.add_concept_node("penguin", tv.call(0.01, 0.9))
    bird = space.add_concept_node("bird", tv.call(0.5, 0.9))
    animal = space.add_concept_node("animal", tv.call(0.6, 0.9))
    premise = space.add_inheritance_link(penguin, bird, tv.call(0.8, 0.9))
    space.add_inheritance_link(bird, animal, tv.call(0.9, 0.9))

    conclusion = PLN::DeductionRule.new.apply(premise, space).not_nil!
    conclusion.to_s.should eq(%((INHERITANCELINK (CONCEPTNODE "penguin") (CONCEPTNODE "animal"))))
    conclusion.truth_value.strength.should be_close(0.78, 1e-12)
    conclusion.truth_value.confidence.should be_close(0.9 * 0.9 * 0.9, 1e-12)

    inverted = PLN::InversionRule.new.apply(premise, space).not_nil!
    inverted.to_s.should eq(%((INHERITANCELINK (CONCEPTNODE "bird") (CONCEPTNODE "penguin"))))
    inverted.truth_value.strength.should be_close(0.8 * 0.01 / 0.5, 1e-12)
  end

  it "keeps the product and the unchanged inverse for plain nodes" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("a")
    b = space.add_concept_node("b")
    c = space.add_concept_node("c")
    premise = space.add_inheritance_link(a, b, AtomSpace::SimpleTruthValue.new(0.8, 0.9))
    space.add_inheritance_link(b, c, AtomSpace::SimpleTruthValue.new(0.9, 0.9))

    PLN::DeductionRule.new.apply(premise, space).not_nil!.truth_value.strength.should be_close(0.72, 1e-12)
    PLN::InversionRule.new.apply(premise, space).not_nil!.truth_value.strength.should be_close(0.8, 1e-12)
  end
end

describe PLN::InferenceContext do
  it "indexes a link added during an iteration without a rebuild" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("a")
    b = space.add_concept_node("b")
    c = space.add_concept_node("c")
    ab = space.add_inheritance_link(a, b)
    context = PLN::InferenceContext.new(space, space.get_all_atoms)
    context.links_from(a).should eq([ab])
    context.links_to(c).should be_empty

    bc = space.add_inheritance_link(b, c)
    context.add_inheritance(bc, space)
    context.links_from(b).should eq([bc])
    context.links_to(c).should eq([bc])
    # Same order as the AtomSpace's own type index.
    context.inheritance_links.should eq(space.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK))

    context.refresh_inheritance(space)
    context.inheritance_links.should eq([ab, bc])
    context.links_from(a).should eq([ab])
  end

  it "closes a 300-link chain graph quickly" do
    space = AtomSpace::AtomSpace.new
    nodes = Array.new(300) { |i| space.add_concept_node("n#{i}") }
    random = Random.new(7)
    600.times { space.add_inheritance_link(nodes.sample(random), nodes.sample(random), AtomSpace::SimpleTruthValue.new(0.8, 0.9)) }
    engine = PLN.create_engine(space)
    elapsed = Time.measure { engine.reason(3) }
    space.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).size.should be > 2000
    elapsed.should be < 20.seconds
  end
end
