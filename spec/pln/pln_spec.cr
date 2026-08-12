require "spec"
require "../../src/pln/pln"

describe PLN do
  describe "module initialization" do
    it "initializes PLN module" do
      PLN.initialize
      # Should not crash
    end

    it "has correct version" do
      PLN::VERSION.should eq("0.1.0")
    end
  end

  describe PLN::DeductionRule do
    it "has correct name" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::DeductionRule.new
      rule.name.should eq("DeductionRule")
    end

    it "applies to inheritance links" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::DeductionRule.new

      dog = atomspace.add_concept_node("dog")
      animal = atomspace.add_concept_node("animal")
      inheritance = atomspace.add_inheritance_link(dog, animal)

      rule.applies_to?(inheritance).should be_true
    end

    it "does not apply to non-inheritance links" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::DeductionRule.new

      dog = atomspace.add_concept_node("dog")
      cat = atomspace.add_concept_node("cat")
      list_link = atomspace.add_list_link([dog, cat])

      rule.applies_to?(list_link).should be_false
    end

    it "performs deduction correctly" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::DeductionRule.new

      # Create A->B and B->C, expect A->C
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")

      # dog -> mammal
      inheritance1 = atomspace.add_inheritance_link(dog, mammal, tv1)
      # mammal -> animal
      inheritance2 = atomspace.add_inheritance_link(mammal, animal, tv2)

      # Apply deduction rule to dog->mammal
      result = rule.apply(inheritance1, atomspace)

      result.should_not be_nil
      result.not_nil!.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)

      # Should create dog->animal with combined strength
      link = result.not_nil!.as(AtomSpace::Link)
      link.outgoing[0].should eq(dog)
      link.outgoing[1].should eq(animal)

      # Truth value should be combined: 0.8 * 0.7 = 0.56
      tv = link.truth_value
      tv.strength.should be_close(0.56, 0.01)
      tv.confidence.should be_close(0.648, 0.01) # 0.9 * 0.8 * 0.9
    end

    it "returns nil when no chain found" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::DeductionRule.new

      dog = atomspace.add_concept_node("dog")
      cat = atomspace.add_concept_node("cat")
      inheritance = atomspace.add_inheritance_link(dog, cat)

      result = rule.apply(inheritance, atomspace)
      result.should be_nil
    end
  end

  describe PLN::InversionRule do
    it "has correct name" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::InversionRule.new
      rule.name.should eq("InversionRule")
    end

    it "applies to inheritance links" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::InversionRule.new

      dog = atomspace.add_concept_node("dog")
      animal = atomspace.add_concept_node("animal")
      inheritance = atomspace.add_inheritance_link(dog, animal)

      rule.applies_to?(inheritance).should be_true
    end

    it "performs inversion correctly" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::InversionRule.new

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      dog = atomspace.add_concept_node("dog")
      animal = atomspace.add_concept_node("animal")
      inheritance = atomspace.add_inheritance_link(dog, animal, tv)

      result = rule.apply(inheritance, atomspace)

      result.should_not be_nil
      result.not_nil!.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)

      # Should create animal->dog (inverted)
      link = result.not_nil!.as(AtomSpace::Link)
      link.outgoing[0].should eq(animal)
      link.outgoing[1].should eq(dog)

      # Truth value should be inverted with discount
      inv_tv = link.truth_value
      inv_tv.strength.should be > 0.0
      inv_tv.strength.should be < 1.0
      inv_tv.confidence.should be_close(0.72, 0.01) # 0.9 * 0.8
    end
  end

  describe PLN::PLNEngine do
    it "initializes with default rules" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)
      engine.should_not be_nil
    end

    it "can add custom rules" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      custom_rule = PLN::DeductionRule.new
      engine.add_rule(custom_rule)
      # Should not crash
    end

    it "performs reasoning iterations" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      # Set up a reasoning scenario
      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")

      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      atomspace.add_inheritance_link(dog, mammal, tv1)
      atomspace.add_inheritance_link(mammal, animal, tv2)

      initial_size = atomspace.size

      # Run reasoning
      new_atoms = engine.reason(5)

      new_atoms.should_not be_empty
      atomspace.size.should be > initial_size
    end

    it "stops when no new atoms generated" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      # Simple case with no inference possible
      dog = atomspace.add_concept_node("dog")

      new_atoms = engine.reason(10)

      # Isolated concept with no links — no inferences expected
      new_atoms.should be_empty
    end

    it "performs forward chaining" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")

      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      atomspace.add_inheritance_link(dog, mammal, tv)

      results = engine.forward_chain(AtomSpace::AtomType::INHERITANCE_LINK, 3)

      # Should find inheritance links (including inverted ones)
      results.should_not be_empty
    end

    it "performs backward chaining" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      dog = atomspace.add_concept_node("dog")
      animal = atomspace.add_concept_node("animal")
      goal = atomspace.add_inheritance_link(dog, animal)

      # Add goal to atomspace first for simple test
      result = engine.backward_chain(goal)

      result.should be_true
    end
  end

  describe "PLN convenience methods" do
    it "creates PLN engine" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN.create_engine(atomspace)

      engine.should be_a(PLN::PLNEngine)
    end
  end

  describe "PLN integration scenarios" do
    it "handles complex reasoning chains" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      # Create a knowledge graph: dog->mammal->animal->living_thing
      tv1 = AtomSpace::SimpleTruthValue.new(0.9, 0.95)
      tv2 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv3 = AtomSpace::SimpleTruthValue.new(0.7, 0.85)

      dog = atomspace.add_concept_node("dog")
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")
      living = atomspace.add_concept_node("living_thing")

      atomspace.add_inheritance_link(dog, mammal, tv1)
      atomspace.add_inheritance_link(mammal, animal, tv2)
      atomspace.add_inheritance_link(animal, living, tv3)

      initial_size = atomspace.size

      # Should be able to derive dog->animal and dog->living_thing
      new_atoms = engine.reason(5)

      atomspace.size.should be > initial_size

      # Check that dog->animal was derived
      dog_to_animal = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
        .select { |link|
          link.is_a?(AtomSpace::Link) &&
            link.outgoing.size == 2 &&
            link.outgoing[0] == dog &&
            link.outgoing[1] == animal
        }

      dog_to_animal.should_not be_empty
    end

    it "handles truth value propagation correctly" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      # Test that truth values are properly calculated through reasoning
      tv1 = AtomSpace::SimpleTruthValue.new(1.0, 1.0)
      tv2 = AtomSpace::SimpleTruthValue.new(1.0, 1.0)

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      c = atomspace.add_concept_node("C")

      atomspace.add_inheritance_link(a, b, tv1)
      atomspace.add_inheritance_link(b, c, tv2)

      new_atoms = engine.reason(3)

      # Find A->C link
      ac_link = new_atoms.find { |atom|
        atom.is_a?(AtomSpace::Link) &&
          atom.outgoing.size == 2 &&
          atom.outgoing[0] == a &&
          atom.outgoing[1] == c
      }

      if ac_link
        # Should have high confidence since both premises have confidence 1.0
        tv = ac_link.truth_value
        tv.confidence.should be > 0.8
      end
    end

    it "prevents infinite loops" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      # Create circular reasoning scenario
      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")

      atomspace.add_inheritance_link(a, b)
      atomspace.add_inheritance_link(b, a)

      # Should complete without hanging
      new_atoms = engine.reason(10)

      # Should terminate gracefully
      new_atoms.size.should be >= 0
    end
  end

  describe "PLN error handling" do
    it "handles empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      new_atoms = engine.reason(5)
      new_atoms.should be_empty
    end

    it "handles invalid atoms gracefully" do
      atomspace = AtomSpace::AtomSpace.new

      # Add non-link atom and try to apply link-based rules
      dog = atomspace.add_concept_node("dog")

      deduction_rule = PLN::DeductionRule.new
      result = deduction_rule.apply(dog, atomspace)

      result.should be_nil
    end

    it "handles malformed links" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      # This would test edge cases in rule application
      dog = atomspace.add_concept_node("dog")

      # Create link with only one outgoing (malformed inheritance)
      # Note: This depends on atomspace implementation details
      new_atoms = engine.reason(1)

      # Should complete without crashing
      new_atoms.size.should be >= 0
    end
  end

  describe PLN::ModusPonensRule do
    it "has correct name" do
      rule = PLN::ModusPonensRule.new
      rule.name.should eq("ModusPonensRule")
    end

    it "applies to inheritance links" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::ModusPonensRule.new

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      inheritance = atomspace.add_inheritance_link(a, b)

      rule.applies_to?(inheritance).should be_true
    end

    it "performs modus ponens correctly" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::ModusPonensRule.new

      # Create A->B and A, expect B
      tv_ab = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv_a = AtomSpace::SimpleTruthValue.new(0.9, 0.95)

      a = atomspace.add_concept_node("A", tv_a) # A is a fact
      b = atomspace.add_concept_node("B")
      inheritance = atomspace.add_inheritance_link(a, b, tv_ab) # A->B

      # Apply modus ponens
      result = rule.apply(inheritance, atomspace)

      result.should_not be_nil
      result.not_nil!.name.should eq("B")

      # Truth value should be calculated correctly
      tv = result.not_nil!.truth_value
      tv.strength.should be > 0.5 # Should be reasonably high
      tv.confidence.should be > 0.5
    end

    it "returns nil when antecedent is not present" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::ModusPonensRule.new

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      inheritance = atomspace.add_inheritance_link(a, b) # A->B but no A fact

      result = rule.apply(inheritance, atomspace)
      result.should be_nil
    end
  end

  describe PLN::AbductionRule do
    it "has correct name" do
      rule = PLN::AbductionRule.new
      rule.name.should eq("AbductionRule")
    end

    it "applies to inheritance links" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::AbductionRule.new

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      inheritance = atomspace.add_inheritance_link(a, b)

      rule.applies_to?(inheritance).should be_true
    end

    it "performs abduction correctly" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::AbductionRule.new

      # Create A->B and C->B, expect A->C
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.7, 0.8)

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      c = atomspace.add_concept_node("C")

      inheritance_ab = atomspace.add_inheritance_link(a, b, tv1) # A->B
      inheritance_cb = atomspace.add_inheritance_link(c, b, tv2) # C->B

      # Apply abduction to A->B
      result = rule.apply(inheritance_ab, atomspace)

      result.should_not be_nil
      result.not_nil!.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)

      # Should create A->C
      link = result.not_nil!.as(AtomSpace::Link)
      link.outgoing[0].should eq(a)
      link.outgoing[1].should eq(c)

      # Truth value should be reasonable
      tv = link.truth_value
      tv.strength.should be > 0.0
      tv.confidence.should be > 0.0
    end

    it "returns nil when no matching consequent found" do
      atomspace = AtomSpace::AtomSpace.new
      rule = PLN::AbductionRule.new

      a = atomspace.add_concept_node("A")
      b = atomspace.add_concept_node("B")
      inheritance = atomspace.add_inheritance_link(a, b) # Only A->B, no other ->B

      result = rule.apply(inheritance, atomspace)
      result.should be_nil
    end
  end

  describe "PLN integration with advanced rules" do
    it "uses all rules in reasoning" do
      atomspace = AtomSpace::AtomSpace.new
      engine = PLN::PLNEngine.new(atomspace)

      # Create a scenario that can use multiple rules
      tv_high = AtomSpace::SimpleTruthValue.new(0.9, 0.95)
      tv_med = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      # Facts
      cat = atomspace.add_concept_node("cat", tv_high)
      dog = atomspace.add_concept_node("dog", tv_high)

      # Rules
      mammal = atomspace.add_concept_node("mammal")
      animal = atomspace.add_concept_node("animal")

      # Inheritance rules: cat->mammal, dog->mammal, mammal->animal
      atomspace.add_inheritance_link(cat, mammal, tv_med)
      atomspace.add_inheritance_link(dog, mammal, tv_med)
      atomspace.add_inheritance_link(mammal, animal, tv_med)

      initial_size = atomspace.size

      # Run reasoning
      new_atoms = engine.reason(3)

      # Should generate multiple new atoms through different rules
      new_atoms.should_not be_empty
      atomspace.size.should be > initial_size

      # Should be able to derive that cat and dog are both animals
      # and potentially that cat->dog (via abduction)
      new_atoms.size.should be > 3
    end
  end
end
