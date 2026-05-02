require "spec"
require "../../src/attention/allocation_engine"

describe Attention::AllocationEngine do
  describe "initialization" do
    it "creates allocation engine" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      engine.should_not be_nil
    end

    it "has default parameters" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      engine.bank.should_not be_nil
      engine.diffusion.should_not be_nil
      engine.rent_collector.should_not be_nil
    end

    it "initializes with default goals" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      engine.active_goals.should_not be_empty
      engine.active_goals.has_key?(Attention::Goal::Reasoning).should be_true
      engine.active_goals.has_key?(Attention::Goal::Learning).should be_true
      engine.active_goals.has_key?(Attention::Goal::Memory).should be_true
    end
  end

  describe "allocation functionality" do
    it "performs attention allocation" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      concept = atomspace.add_concept_node("test")

      engine.allocate_attention(1)
      # Should not crash
    end

    it "respects cycle limits" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      engine.allocate_attention(3)
      # Should not crash or hang
    end

    it "returns results hash from allocate_attention" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      result = engine.allocate_attention(1)
      result.should be_a(Hash(String, Float64))
    end
  end

  describe "goal management" do
    it "set_goal updates individual goal weight" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      engine.set_goal(Attention::Goal::Reasoning, 2.0)
      engine.active_goals[Attention::Goal::Reasoning].should eq(2.0)
    end

    it "set_goals replaces all goal weights" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      new_goals = {Attention::Goal::Processing => 1.5}
      engine.set_goals(new_goals)

      engine.active_goals.size.should eq(1)
      engine.active_goals[Attention::Goal::Processing].should eq(1.5)
    end

    it "set_goals clears previous goals" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      engine.set_goals({Attention::Goal::Adaptation => 0.9})
      engine.active_goals.has_key?(Attention::Goal::Reasoning).should be_false
    end
  end

  describe "apply_goal_boosting" do
    it "returns a hash with expected keys" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      result = engine.apply_goal_boosting
      result.has_key?("total_boosts").should be_true
      result.has_key?("atoms_boosted").should be_true
    end

    it "does not crash on empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      result = engine.apply_goal_boosting
      result["total_boosts"].should eq(0.0)
    end
  end

  describe "calculate_priorities" do
    it "returns a hash with expected keys" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      result = engine.calculate_priorities
      result.has_key?("average_priority").should be_true
      result.has_key?("max_priority").should be_true
      result.has_key?("total_atoms").should be_true
    end

    it "returns zero priorities for empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      result = engine.calculate_priorities
      result["average_priority"].should eq(0.0)
      result["total_atoms"].should eq(0.0)
    end

    it "total_atoms matches atomspace size" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)
      3.times { |i| atomspace.add_concept_node("node_#{i}") }

      result = engine.calculate_priorities
      result["total_atoms"].should eq(3.0)
    end
  end

  describe "calculate_atom_priority" do
    it "returns 0 when no attention value set" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)
      concept = atomspace.add_concept_node("test")

      priority = engine.calculate_atom_priority(concept.handle, nil)
      priority.should eq(0.0)
    end

    it "returns positive priority for atom with positive STI" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)
      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(100_i16, 50_i16)

      priority = engine.calculate_atom_priority(concept.handle, av)
      priority.should be > 0.0
    end

    it "VLTI flag adds to priority" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)
      concept = atomspace.add_concept_node("test")

      av_no_vlti = AtomSpace::AttentionValue.new(0_i16, 0_i16, false)
      av_vlti = AtomSpace::AttentionValue.new(0_i16, 0_i16, true)

      p_no_vlti = engine.calculate_atom_priority(concept.handle, av_no_vlti)
      p_vlti = engine.calculate_atom_priority(concept.handle, av_vlti)

      p_vlti.should be > p_no_vlti
    end
  end

  describe "focus_attention" do
    it "stimulates target atoms" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)
      concept = atomspace.add_concept_node("test")

      engine.focus_attention([concept.handle], 50_i16)

      av = engine.bank.get_attention_value(concept.handle)
      av.should_not be_nil
      av.not_nil!.sti.should be > 0
    end

    it "does not crash with empty target list" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      engine.focus_attention([] of AtomSpace::Handle)
      # Should not crash
      true.should be_true
    end
  end

  describe "get_allocation_statistics" do
    it "returns hash with expected keys" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)

      stats = engine.get_allocation_statistics
      stats.has_key?("bank_sti_funds").should be_true
      stats.has_key?("bank_lti_funds").should be_true
      stats.has_key?("bank_af_size").should be_true
      stats.has_key?("active_goals").should be_true
    end

    it "active_goals reflects actual goal count" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)
      engine.set_goals({Attention::Goal::Reasoning => 1.0, Attention::Goal::Learning => 0.5})

      stats = engine.get_allocation_statistics
      stats["active_goals"].should eq(2.0)
    end
  end

  describe "Goal enum" do
    it "each goal has a positive boost_factor" do
      [
        Attention::Goal::Reasoning,
        Attention::Goal::Learning,
        Attention::Goal::Memory,
        Attention::Goal::Adaptation,
        Attention::Goal::Processing,
      ].each do |goal|
        goal.boost_factor.should be > 0.0
        goal.boost_factor.should be <= 1.0
      end
    end
  end

  describe "to_s" do
    it "returns a descriptive string" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention::AllocationEngine.new(atomspace)
      result = engine.to_s

      result.should contain("AllocationEngine")
    end
  end
end
