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

describe "PLN rules with several second premises" do
  it "draws a new conclusion on each application until none is left" do
    space = AtomSpace::AtomSpace.new
    tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
    a = space.add_concept_node("a")
    b = space.add_concept_node("b")
    premise = space.add_inheritance_link(a, b, tv)
    targets = %w(c1 c2 c3).map { |name| space.add_concept_node(name) }
    targets.each { |target| space.add_inheritance_link(b, target, tv) }
    rule = PLN::DeductionRule.new

    drawn = Array.new(3) { rule.apply(premise, space).not_nil!.to_s }
    drawn.should eq(targets.map { |target| %((INHERITANCELINK (CONCEPTNODE "a") #{target})) })
    size = space.size

    # Nothing new is left: the first conclusion comes back and nothing is added.
    rule.apply(premise, space).not_nil!.to_s.should eq(drawn.first)
    space.size.should eq(size)
    space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, targets.last]).not_nil!.truth_value.strength.should be_close(0.64, 1e-12)
  end

  it "does the same for abduction" do
    space = AtomSpace::AtomSpace.new
    tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
    a = space.add_concept_node("a")
    b = space.add_concept_node("b")
    premise = space.add_inheritance_link(a, b, tv)
    others = %w(c1 c2).map { |name| space.add_concept_node(name) }
    others.each { |other| space.add_inheritance_link(other, b, tv) }
    rule = PLN::AbductionRule.new

    2.times { rule.apply(premise, space).should_not be_nil }
    others.each { |other| space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, other]).should_not be_nil }
  end

  it "finds links without creating or changing anything" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("a")
    b = space.add_concept_node("b")
    link = space.add_inheritance_link(a, b, AtomSpace::SimpleTruthValue.new(0.8, 0.9))
    before = AtomSpace::ConceptNode.new("probe").handle
    space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, b]).should be(link)
    space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [b, a]).should be_nil
    space.find_link(AtomSpace::AtomType::LIST_LINK, [a, b]).should be_nil
    # No atom was built for the lookups.
    (AtomSpace::ConceptNode.new("probe").handle - before).should eq(1)
    link.truth_value.confidence.should eq(0.9)
  end
end

describe "PLN evidence from several derivations" do
  it "revises a conclusion once for each chain that leads to it" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("a")
    c = space.add_concept_node("c")
    first = space.add_concept_node("b1")
    second = space.add_concept_node("b2")
    ab1 = space.add_inheritance_link(a, first, AtomSpace::SimpleTruthValue.new(0.9, 0.8))
    space.add_inheritance_link(first, c, AtomSpace::SimpleTruthValue.new(0.9, 0.8))
    ab2 = space.add_inheritance_link(a, second, AtomSpace::SimpleTruthValue.new(0.5, 0.6))
    space.add_inheritance_link(second, c, AtomSpace::SimpleTruthValue.new(0.6, 0.5))
    rule = PLN::DeductionRule.new

    conclusion = rule.apply(ab1, space).not_nil!
    conclusion.truth_value.strength.should be_close(0.81, 1e-12)
    conclusion.truth_value.confidence.should be_close(0.576, 1e-12)

    # The second chain says 0.3 with confidence 0.27; the two are revised.
    rule.apply(ab2, space).should be(conclusion)
    c1, c2 = 0.576, 0.27
    conclusion.truth_value.confidence.should be_close(c1 + c2 - c1 * c2, 1e-12)
    conclusion.truth_value.strength.should be_close((0.81 * c1 + 0.3 * c2) / (c1 + c2), 1e-12)

    # Seeing the same chains again adds nothing.
    settled = {conclusion.truth_value.strength, conclusion.truth_value.confidence}
    3.times { rule.apply(ab1, space); rule.apply(ab2, space) }
    {conclusion.truth_value.strength, conclusion.truth_value.confidence}.should eq(settled)
  end

  it "counts a derivation as evidence for a conclusion that was asserted" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("a")
    b = space.add_concept_node("b")
    c = space.add_concept_node("c")
    premise = space.add_inheritance_link(a, b, AtomSpace::SimpleTruthValue.new(1.0, 0.9))
    space.add_inheritance_link(b, c, AtomSpace::SimpleTruthValue.new(1.0, 0.9))
    asserted = space.add_inheritance_link(a, c, AtomSpace::SimpleTruthValue.new(0.6, 0.5))
    rule = PLN::DeductionRule.new

    rule.apply(premise, space).should be(asserted)
    derived = 0.9 * 0.9 * 0.9
    asserted.truth_value.confidence.should be_close(0.5 + derived - 0.5 * derived, 1e-12)
    asserted.truth_value.strength.should be_close((0.6 * 0.5 + 1.0 * derived) / (0.5 + derived), 1e-12)
    rule.apply(premise, space)
    asserted.truth_value.confidence.should be_close(0.5 + derived - 0.5 * derived, 1e-12)
  end

  it "does not let a link's own inverse raise its confidence" do
    space = AtomSpace::AtomSpace.new
    a = space.add_concept_node("a")
    b = space.add_concept_node("b")
    link = space.add_inheritance_link(a, b, AtomSpace::SimpleTruthValue.new(0.8, 0.9))

    PLN.create_engine(space).reason(5)
    inverse = space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [b, a]).not_nil!
    inverse.truth_value.confidence.should be_close(0.72, 1e-12)
    {link.truth_value.strength, link.truth_value.confidence}.should eq({0.8, 0.9})
  end

  it "keeps asserted premises of a chain as they were" do
    space = AtomSpace::AtomSpace.new
    nodes = %w(a b c).map { |name| space.add_concept_node(name) }
    ab = space.add_inheritance_link(nodes[0], nodes[1], AtomSpace::SimpleTruthValue.new(0.8, 0.9))
    bc = space.add_inheritance_link(nodes[1], nodes[2], AtomSpace::SimpleTruthValue.new(0.7, 0.9))
    PLN.create_engine(space).reason(1)
    # One round of conclusions drawn from them leaves the two premises alone.
    {ab.truth_value.strength, ab.truth_value.confidence}.should eq({0.8, 0.9})
    {bc.truth_value.strength, bc.truth_value.confidence}.should eq({0.7, 0.9})
  end

  it "does not let a conclusion come back as evidence for its own premises, however far round" do
    space = AtomSpace::AtomSpace.new
    nodes = %w(a b c).map { |name| space.add_concept_node(name, AtomSpace::SimpleTruthValue.new(0.5, 0.9)) }
    ab = space.add_inheritance_link(nodes[0], nodes[1], AtomSpace::SimpleTruthValue.new(0.8, 0.9))
    bc = space.add_inheritance_link(nodes[1], nodes[2], AtomSpace::SimpleTruthValue.new(0.7, 0.9))
    # Everything the engine can conclude here rests on these two links:
    # a->c, then c->a, then c->b from c->a and a->b, whose inverse is b->c
    # again. That circle is three derivations long.
    PLN.create_engine(space).reason(12)
    space.find_link(AtomSpace::AtomType::INHERITANCE_LINK, [nodes[2], nodes[1]]).should_not be_nil
    {ab.truth_value.strength, ab.truth_value.confidence}.should eq({0.8, 0.9})
    {bc.truth_value.strength, bc.truth_value.confidence}.should eq({0.7, 0.9})
  end

  it "settles: more iterations change nothing once every derivation is counted" do
    space = AtomSpace::AtomSpace.new
    nodes = %w(a b c d).map { |name| space.add_concept_node(name, AtomSpace::SimpleTruthValue.new(0.5, 0.9)) }
    3.times { |i| space.add_inheritance_link(nodes[i], nodes[i + 1], AtomSpace::SimpleTruthValue.new(0.8, 0.9)) }
    engine = PLN.create_engine(space)
    engine.reason(40)
    settled = space.get_all_atoms.map { |atom| {atom.to_s, atom.truth_value.strength, atom.truth_value.confidence} }.sort
    engine.reason(10)
    space.get_all_atoms.map { |atom| {atom.to_s, atom.truth_value.strength, atom.truth_value.confidence} }.sort.should eq(settled)
  end
end

describe PLN::Provenance do
  it "counts each derivation once and remembers what each link was drawn from" do
    space = AtomSpace::AtomSpace.new
    nodes = %w(a b c d).map { |name| space.add_concept_node(name) }
    ab = space.add_inheritance_link(nodes[0], nodes[1])
    bc = space.add_inheritance_link(nodes[1], nodes[2])
    ac = space.add_inheritance_link(nodes[0], nodes[2])
    cd = space.add_inheritance_link(nodes[2], nodes[3])
    ad = space.add_inheritance_link(nodes[0], nodes[3])
    provenance = PLN::Provenance.new
    provenance.record(ac, ab, bc)
    provenance.record(ad, ac, cd)

    provenance.first_use?(PLN::Provenance::DEDUCTION, ab, bc).should be_true
    provenance.first_use?(PLN::Provenance::DEDUCTION, ab, bc).should be_false
    # The other order and another rule are different derivations.
    provenance.first_use?(PLN::Provenance::DEDUCTION, bc, ab).should be_true
    provenance.first_use?(PLN::Provenance::ABDUCTION, ab, bc).should be_true
    provenance.first_use?(PLN::Provenance::INVERSION, ab).should be_true
    provenance.derivations.should eq(4)

    provenance.parent?(ab, ac).should be_true
    provenance.parent?(ac, ab).should be_false
    provenance.parent?(ab, ad).should be_false # a grandparent
    # ac may not revise ab, which it came from; cd is unrelated to ab.
    provenance.independent?(ab, ac, cd).should be_false
    provenance.independent?(ab, cd).should be_true
    provenance.independent?(ab, ab).should be_false

    # ad came from ac, which came from ab: ad rests on ab two steps back.
    provenance.shares_evidence?(ad, ab).should be_true
    provenance.shares_evidence?(ad, bc).should be_true
    provenance.shares_evidence?(ac, cd).should be_false
    provenance.independent?(ab, ad).should be_false
    provenance.independent?(cd, ad).should be_false
    provenance.independent?(cd, ac).should be_true
    # Asserted links rest on themselves: numbered as they are first met.
    provenance.evidence(ab).size.should eq(1)
    provenance.evidence(ad).should eq((provenance.evidence(ab) + provenance.evidence(bc) + provenance.evidence(cd)).sort)
  end

  it "combines only evidence that shares no asserted link" do
    space = AtomSpace::AtomSpace.new
    nodes = %w(a b c d e).map { |name| space.add_concept_node(name) }
    ab = space.add_inheritance_link(nodes[0], nodes[1])
    bc = space.add_inheritance_link(nodes[1], nodes[2])
    ac = space.add_inheritance_link(nodes[0], nodes[2])
    ad = space.add_inheritance_link(nodes[0], nodes[3])
    dc = space.add_inheritance_link(nodes[3], nodes[2])
    ce = space.add_inheritance_link(nodes[2], nodes[4])
    ae = space.add_inheritance_link(nodes[0], nodes[4])
    provenance = PLN::Provenance.new
    provenance.record(ac, ab, bc)
    provenance.record(ae, ac, ce)

    # A second chain to a->c through d shares nothing with the first.
    provenance.independent?(ac, ad, dc).should be_true
    provenance.revised(ac, ad, dc)
    provenance.shares_evidence?(ac, ad).should be_true
    # It is in a->c now and is not counted into it again.
    provenance.independent?(ac, ad, dc).should be_false
    # a->e was drawn before the revision and still rests on the first chain only.
    provenance.shares_evidence?(ae, dc).should be_false
    # Evidence that overlaps in part is not combined either: a->e rests on a->b.
    provenance.independent?(ac, ae).should be_false
    provenance.independent?(ad, ae).should be_true

    # An asserted link that was revised rests on what revised it as well.
    provenance.revised(ce, ab)
    provenance.shares_evidence?(ce, ab).should be_true
    provenance.shares_evidence?(ce, bc).should be_false
  end

  it "stays quick when links rest on many others" do
    space = AtomSpace::AtomSpace.new
    origin = space.add_concept_node("origin")
    links = Array(AtomSpace::Atom).new(2001) { |i| space.add_inheritance_link(origin, space.add_concept_node("n#{i}")) }
    provenance = PLN::Provenance.new
    # Each link drawn from the one before and a fresh asserted one.
    derived = links[0]
    (1..1000).each do |i|
      provenance.record(links[1000 + i], derived, links[i])
      derived = links[1000 + i]
    end
    provenance.evidence(derived).size.should eq(1001)
    started = Time.monotonic
    20_000.times { provenance.independent?(links[0], derived).should be_false }
    20_000.times { provenance.independent?(links[2000], links[1500]).should be_false }
    (Time.monotonic - started).should be < 5.seconds
  end
end
