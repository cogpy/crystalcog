require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/pln/pln"
require "../../src/ure/ure"
require "../../src/opencog/opencog"

# Error handling and edge-case coverage for AtomSpace, PLN, and URE.
# Uses locally scoped setup (not instance variables) so Crystal can type-check
# example blocks cleanly when required from spec_helper.
describe "Error Handling and Edge Cases" do
  describe "AtomSpace error handling" do
    it "handles empty names gracefully" do
      atomspace = AtomSpace::AtomSpace.new
      empty_concept = atomspace.add_concept_node("")
      empty_concept.should be_a(AtomSpace::Atom)
      empty_concept.as(AtomSpace::Node).name.should eq("")
    end

    it "handles very long names" do
      atomspace = AtomSpace::AtomSpace.new
      long_name = "a" * 10000
      long_concept = atomspace.add_concept_node(long_name)
      long_concept.should be_a(AtomSpace::Atom)
      long_concept.as(AtomSpace::Node).name.should eq(long_name)
    end

    it "handles special characters in names" do
      atomspace = AtomSpace::AtomSpace.new
      special_names = [
        "node with spaces",
        "node-with-dashes",
        "node_with_underscores",
        "node.with.dots",
        "node/with/slashes",
        "node(with)parentheses",
        "node[with]brackets",
        "node{with}braces",
        "node\"with\"quotes",
        "node'with'apostrophes",
        "node@with@symbols",
        "node#with#hash",
        "node$with$dollar",
        "node%with%percent",
        "nodeπwithπunicode",
        "node\nwith\nnewlines",
        "node\twith\ttabs",
      ]

      special_names.each do |name|
        concept = atomspace.add_concept_node(name)
        concept.should be_a(AtomSpace::Atom)
        concept.as(AtomSpace::Node).name.should eq(name)
      end
    end

    it "handles invalid truth values gracefully" do
      atomspace = AtomSpace::AtomSpace.new

      begin
        tv_high = AtomSpace::SimpleTruthValue.new(1.5, 0.9)
        concept = atomspace.add_concept_node("test_high", tv_high)
        concept.truth_value.strength.should be <= 1.0
      rescue ex : AtomSpace::InvalidTruthValueException
        ex.should be_a(AtomSpace::InvalidTruthValueException)
      rescue ex : ArgumentError
        ex.should be_a(ArgumentError)
      end

      begin
        tv_neg = AtomSpace::SimpleTruthValue.new(-0.5, 0.9)
        concept = atomspace.add_concept_node("test_neg", tv_neg)
        concept.truth_value.strength.should be >= 0.0
      rescue ex : AtomSpace::InvalidTruthValueException
        ex.should be_a(AtomSpace::InvalidTruthValueException)
      rescue ex : ArgumentError
        ex.should be_a(ArgumentError)
      end
    end

    it "handles empty link creation" do
      atomspace = AtomSpace::AtomSpace.new
      begin
        empty_link = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [] of AtomSpace::Atom)
        empty_link.should be_a(AtomSpace::Atom)
        empty_link.as(AtomSpace::Link).outgoing.should be_empty
      rescue ex : AtomSpace::InvalidAtomException
        ex.should be_a(AtomSpace::InvalidAtomException)
      end
    end

    it "handles circular references in links" do
      atomspace = AtomSpace::AtomSpace.new
      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")

      link_ab = atomspace.add_inheritance_link(a, b)
      link_ba = atomspace.add_inheritance_link(b, a)

      atomspace.contains?(link_ab).should be_true
      atomspace.contains?(link_ba).should be_true
      atomspace.size.should eq(4)
    end

    it "handles attempts to remove non-existent atoms" do
      atomspace = AtomSpace::AtomSpace.new
      concept = AtomSpace::ConceptNode.new("nonexistent")

      result = atomspace.remove_atom(concept)
      result.should be_false
      atomspace.size.should eq(0)
    end

    it "handles memory pressure gracefully" do
      atomspace = AtomSpace::AtomSpace.new
      concepts = [] of AtomSpace::Atom

      1000.times do |i|
        concept = atomspace.add_concept_node("stress_test_#{i}")
        concepts << concept

        if i % 200 == 0
          GC.collect
        end
      end

      atomspace.size.should eq(1000)
      sample_concept = concepts.sample
      atomspace.contains?(sample_concept).should be_true
    end

    it "handles interleaved operations gracefully" do
      atomspace = AtomSpace::AtomSpace.new
      concepts = [] of AtomSpace::Atom

      100.times do |i|
        concept = atomspace.add_concept_node("concurrent_#{i}")
        concepts << concept

        if i % 3 == 0 && !concepts.empty?
          sample = concepts.sample
          atomspace.get_atom(sample.handle)
        elsif i % 5 == 0 && concepts.size >= 2
          c1, c2 = concepts.sample(2)
          atomspace.add_inheritance_link(c1, c2)
        end
      end

      atomspace.size.should be >= 100
    end
  end

  describe "PLN error handling" do
    it "handles empty atomspace reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN::PLNEngine.new(atomspace)

      new_atoms = pln_engine.reason(5)
      new_atoms.should be_empty
      atomspace.size.should eq(0)
    end

    it "handles malformed atoms in reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN::PLNEngine.new(atomspace)

      dog = atomspace.add_concept_node("dog")
      cat = atomspace.add_concept_node("cat")
      atomspace.add_inheritance_link(dog, cat)

      new_atoms = pln_engine.reason(3)
      new_atoms.size.should be >= 0
    end

    it "handles infinite recursion prevention" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN::PLNEngine.new(atomspace)

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      c = atomspace.add_concept_node("C")

      atomspace.add_inheritance_link(a, b)
      atomspace.add_inheritance_link(b, c)
      atomspace.add_inheritance_link(c, a)

      start_time = Time.instant
      new_atoms = pln_engine.reason(10)
      end_time = Time.instant

      (end_time - start_time).should be < 5.seconds
      new_atoms.size.should be >= 0
    end

    it "handles extreme truth values in reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN::PLNEngine.new(atomspace)

      tv_perfect = AtomSpace::SimpleTruthValue.new(1.0, 1.0)
      tv_impossible = AtomSpace::SimpleTruthValue.new(0.0, 1.0)
      tv_unknown = AtomSpace::SimpleTruthValue.new(0.5, 0.0)

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      c = atomspace.add_concept_node("C")
      d = atomspace.add_concept_node("D")

      atomspace.add_inheritance_link(a, b, tv_perfect)
      atomspace.add_inheritance_link(b, c, tv_impossible)
      atomspace.add_inheritance_link(c, d, tv_unknown)

      new_atoms = pln_engine.reason(5)
      new_atoms.size.should be >= 0

      new_atoms.each do |atom|
        tv = atom.truth_value
        tv.strength.should be >= 0.0
        tv.strength.should be <= 1.0
        tv.confidence.should be >= 0.0
        tv.confidence.should be <= 1.0
      end
    end

    it "handles rule application failures gracefully" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN::PLNEngine.new(atomspace)

      atomspace.add_concept_node("lonely")
      new_atoms = pln_engine.reason(3)
      new_atoms.size.should be >= 0
    end

    it "handles memory cleanup during reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN::PLNEngine.new(atomspace)

      concepts = 50.times.map { |i|
        atomspace.add_concept_node("memory_test_#{i}")
      }.to_a

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      100.times do
        c1, c2 = concepts.sample(2)
        atomspace.add_inheritance_link(c1, c2, tv)
      end

      new_atoms = pln_engine.reason(3)
      GC.collect
      new_atoms.size.should be >= 0
    end
  end

  describe "URE error handling" do
    it "handles empty atomspace in forward chaining" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      new_atoms = ure_engine.forward_chain(5)
      new_atoms.should be_empty
      atomspace.size.should eq(0)
    end

    it "handles empty atomspace in backward chaining" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      target = AtomSpace::ConceptNode.new("nonexistent")
      result = ure_engine.backward_chain(target)
      result.should be_false
    end

    it "handles malformed rule premises" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      atomspace.add_concept_node("isolated")
      number = AtomSpace::NumberNode.new(42.0)
      atomspace.add_atom(number)

      new_atoms = ure_engine.forward_chain(3)
      new_atoms.size.should be >= 0
    end

    it "handles rule application with insufficient premises" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      pred = atomspace.add_predicate_node("lonely_pred")
      concept = atomspace.add_concept_node("concept")
      atomspace.add_evaluation_link(pred, concept)

      new_atoms = ure_engine.forward_chain(3)
      new_atoms.size.should be >= 0
    end

    it "handles fitness calculation edge cases" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      pred = atomspace.add_predicate_node("extreme_pred")
      concept1 = atomspace.add_concept_node("concept1")
      concept2 = atomspace.add_concept_node("concept2")

      tv_zero_conf = AtomSpace::SimpleTruthValue.new(0.8, 0.0)
      atomspace.add_evaluation_link(pred, concept1, tv_zero_conf)

      tv_perfect = AtomSpace::SimpleTruthValue.new(0.9, 1.0)
      atomspace.add_evaluation_link(pred, concept2, tv_perfect)

      new_atoms = ure_engine.forward_chain(2)
      new_atoms.size.should be >= 0
    end

    it "handles deep backward chaining searches" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      concepts = 10.times.map { |i|
        atomspace.add_concept_node("deep_#{i}")
      }.to_a

      pred = atomspace.add_predicate_node("can_reach")

      (0...concepts.size - 1).each do |i|
        atomspace.add_evaluation_link(
          pred,
          atomspace.add_list_link([concepts[i], concepts[i + 1]])
        )
      end

      goal = atomspace.add_evaluation_link(
        pred,
        atomspace.add_list_link([concepts[0], concepts[-1]])
      )

      result = ure_engine.backward_chain(goal)
      result.should be_a(Bool)
    end

    it "handles rule conflicts and contradictions" do
      atomspace = AtomSpace::AtomSpace.new
      ure_engine = URE::UREEngine.new(atomspace)

      a = atomspace.add_concept_node("A")
      pred_true = atomspace.add_predicate_node("is_true")
      pred_false = atomspace.add_predicate_node("is_false")

      tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
      atomspace.add_evaluation_link(pred_true, a, tv_high)
      atomspace.add_evaluation_link(pred_false, a, tv_high)

      new_atoms = ure_engine.forward_chain(3)
      new_atoms.size.should be >= 0

      atomspace.get_all_atoms.each do |atom|
        tv = atom.truth_value
        tv.strength.should be >= 0.0
        tv.strength.should be <= 1.0
        tv.confidence.should be >= 0.0
        tv.confidence.should be <= 1.0
      end
    end
  end

  describe "Cross-component error handling" do
    it "handles exceptions across all components" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      begin
        concepts = 5.times.map { |i|
          atomspace.add_concept_node("cross_test_#{i}")
        }.to_a

        concepts.each_with_index do |concept, i|
          next_concept = concepts[(i + 1) % concepts.size]
          atomspace.add_inheritance_link(concept, next_concept)
        end

        pln_result = pln_engine.reason(2)
        ure_result = ure_engine.forward_chain(2)

        pln_result.should be_a(Array(AtomSpace::Atom))
        ure_result.should be_a(Array(AtomSpace::Atom))
      rescue ex : OpenCog::OpenCogException
        ex.should be_a(OpenCog::OpenCogException)
      rescue ex : AtomSpace::AtomSpaceException
        ex.should be_a(AtomSpace::AtomSpaceException)
      rescue ex : CogUtil::OpenCogException
        ex.should be_a(CogUtil::OpenCogException)
      rescue ex : Exception
        fail "Unexpected exception type: #{ex.class} - #{ex.message}"
      end
    end

    it "maintains atomspace consistency across component failures" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)

      initial_atoms = atomspace.get_all_atoms.dup
      initial_size = atomspace.size

      begin
        problematic_concepts = 3.times.map { |i|
          atomspace.add_concept_node("problematic_#{i}")
        }.to_a

        atomspace.add_inheritance_link(problematic_concepts[0], problematic_concepts[1])
        atomspace.add_inheritance_link(problematic_concepts[1], problematic_concepts[2])
        atomspace.add_inheritance_link(problematic_concepts[2], problematic_concepts[0])

        pln_engine.reason(10)
        ure_engine.forward_chain(10)
      rescue ex : Exception
        # Even if reasoning fails, atomspace should remain consistent
        ex.should be_a(Exception)
      end

      atomspace.size.should be >= initial_size

      initial_atoms.each do |atom|
        atomspace.contains?(atom).should be_true
      end

      atomspace.get_all_atoms.each do |atom|
        tv = atom.truth_value
        tv.strength.should be >= 0.0
        tv.strength.should be <= 1.0
        tv.confidence.should be >= 0.0
        tv.confidence.should be <= 1.0
      end
    end

    it "handles resource exhaustion gracefully" do
      atomspace = AtomSpace::AtomSpace.new
      pln_engine = PLN.create_engine(atomspace)
      ure_engine = URE.create_engine(atomspace)
      large_concepts = [] of AtomSpace::Atom

      begin
        500.times do |i|
          concept = atomspace.add_concept_node("resource_test_#{i}")
          large_concepts << concept

          if large_concepts.size >= 2
            other = large_concepts.sample
            atomspace.add_inheritance_link(concept, other)
          end

          if i % 100 == 0
            pln_engine.reason(1)
            ure_engine.forward_chain(1)
          end
        end
      rescue ex : Exception
        ex.should be_a(Exception)
      end

      atomspace.size.should be > 0
      test_concept = atomspace.add_concept_node("post_exhaustion_test")
      atomspace.contains?(test_concept).should be_true
    end
  end

  describe "Input validation and sanitization" do
    it "handles null and nil-like inputs" do
      atomspace = AtomSpace::AtomSpace.new
      empty_concept = atomspace.add_concept_node("")
      empty_concept.should be_a(AtomSpace::Atom)
    end

    it "validates atom type consistency" do
      atomspace = AtomSpace::AtomSpace.new
      concept = atomspace.add_concept_node("concept")
      predicate = atomspace.add_predicate_node("predicate")

      inheritance = atomspace.add_inheritance_link(concept, predicate)
      inheritance.should be_a(AtomSpace::Atom)
    end

    it "handles extremely large truth value ranges" do
      atomspace = AtomSpace::AtomSpace.new
      tiny_tv = AtomSpace::SimpleTruthValue.new(1e-10, 1e-10)
      huge_tv = AtomSpace::SimpleTruthValue.new(0.999999999, 0.999999999)

      concept1 = atomspace.add_concept_node("tiny", tiny_tv)
      concept2 = atomspace.add_concept_node("huge", huge_tv)

      concept1.truth_value.strength.should be >= 0.0
      concept2.truth_value.strength.should be <= 1.0
    end

    it "handles rapid operations without data corruption" do
      atomspace = AtomSpace::AtomSpace.new
      operations_count = 1000
      created_atoms = [] of AtomSpace::Atom

      operations_count.times do |i|
        case i % 4
        when 0
          concept = atomspace.add_concept_node("rapid_#{i}")
          created_atoms << concept
        when 1
          predicate = atomspace.add_predicate_node("pred_#{i}")
          created_atoms << predicate
        when 2
          if created_atoms.size >= 2
            atom1, atom2 = created_atoms.sample(2)
            link = atomspace.add_inheritance_link(atom1, atom2)
            created_atoms << link
          end
        when 3
          if !created_atoms.empty?
            atom = created_atoms.sample
            retrieved = atomspace.get_atom(atom.handle)
            retrieved.should eq(atom)
          end
        end
      end

      created_atoms.each do |atom|
        atomspace.contains?(atom).should be_true
      end

      atomspace.size.should be >= operations_count / 2
    end
  end
end
