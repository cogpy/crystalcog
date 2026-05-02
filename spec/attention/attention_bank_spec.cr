require "spec"
require "../../src/attention/attention_bank"

describe Attention::AttentionBank do
  describe "initialization" do
    it "creates attention bank" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.should_not be_nil
    end

    it "has default STI and LTI funds" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.sti_funds.should eq(10000)
      bank.lti_funds.should eq(10000)
    end

    it "allows custom attentional focus sizes" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace, 50, 10)

      bank.af_max_size.should eq(50)
      bank.af_min_size.should eq(10)
    end

    it "starts with empty attentional focus" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.attentional_focus.should be_empty
    end
  end

  describe "attention values" do
    it "sets attention values" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      concept = atomspace.add_concept_node("test")

      av = AtomSpace::AttentionValue.new(100_i16, 50_i16)
      bank.set_attention_value(concept.handle, av)
      retrieved_av = bank.get_attention_value(concept.handle)
      retrieved_av.should_not be_nil
    end

    it "returns nil attention value for unknown handle" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.get_attention_value(9999_u64).should be_nil
    end

    it "returns false when setting AV for nonexistent atom" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      av = AtomSpace::AttentionValue.new(100_i16, 50_i16)

      result = bank.set_attention_value(9999_u64, av)
      result.should be_false
    end

    it "stimulates atoms" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      concept = atomspace.add_concept_node("test")

      bank.stimulate(concept.handle, 50_i16)
      av = bank.get_attention_value(concept.handle)
      av.should_not be_nil
      av.not_nil!.sti.should eq(50)
    end

    it "accumulates STI when stimulated multiple times" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      concept = atomspace.add_concept_node("test")

      bank.stimulate(concept.handle, 30_i16)
      bank.stimulate(concept.handle, 20_i16)
      av = bank.get_attention_value(concept.handle)
      av.not_nil!.sti.should eq(50)
    end

    it "updates stored attention value when set again" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      concept = atomspace.add_concept_node("test")

      av1 = AtomSpace::AttentionValue.new(100_i16, 50_i16)
      bank.set_attention_value(concept.handle, av1)

      av2 = AtomSpace::AttentionValue.new(200_i16, 80_i16)
      bank.set_attention_value(concept.handle, av2)

      retrieved = bank.get_attention_value(concept.handle)
      retrieved.not_nil!.sti.should eq(200)
      retrieved.not_nil!.lti.should eq(80)
    end
  end

  describe "attentional focus" do
    it "atom is added to attentional focus when STI is set" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      concept = atomspace.add_concept_node("test")

      av = AtomSpace::AttentionValue.new(100_i16, 50_i16)
      bank.set_attention_value(concept.handle, av)

      bank.in_attentional_focus?(concept.handle).should be_true
    end

    it "atom is not in attentional focus initially" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      concept = atomspace.add_concept_node("test")

      bank.in_attentional_focus?(concept.handle).should be_false
    end

    it "get_af_min_sti returns MIN_STI when focus is empty" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.get_af_min_sti.should eq(Attention::ECANParams::MIN_STI)
    end

    it "get_af_max_sti returns MIN_STI when focus is empty" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.get_af_max_sti.should eq(Attention::ECANParams::MIN_STI)
    end

    it "get_af_min_sti and get_af_max_sti return correct values" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      c1 = atomspace.add_concept_node("low")
      c2 = atomspace.add_concept_node("high")

      bank.set_attention_value(c1.handle, AtomSpace::AttentionValue.new(50_i16, 0_i16))
      bank.set_attention_value(c2.handle, AtomSpace::AttentionValue.new(200_i16, 0_i16))

      bank.get_af_max_sti.should eq(200)
      bank.get_af_min_sti.should eq(50)
    end
  end

  describe "fund management" do
    it "add_sti_funds increases STI funds" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      initial = bank.sti_funds

      bank.add_sti_funds(500_i16)
      bank.sti_funds.should eq(initial + 500)
    end

    it "add_lti_funds increases LTI funds" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      initial = bank.lti_funds

      bank.add_lti_funds(300_i16)
      bank.lti_funds.should eq(initial + 300)
    end

    it "subtract_sti_funds decreases STI funds" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      initial = bank.sti_funds

      bank.subtract_sti_funds(100_i16)
      bank.sti_funds.should eq(initial - 100)
    end
  end

  describe "wages" do
    it "calculate_sti_wage returns 0 for empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.calculate_sti_wage.should eq(0)
    end

    it "calculate_sti_wage returns positive value when atoms exist" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      atomspace.add_concept_node("test")

      bank.calculate_sti_wage.should be > 0
    end

    it "calculate_lti_wage returns 0 for empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      bank.calculate_lti_wage.should eq(0)
    end
  end

  describe "statistics" do
    it "get_statistics returns expected keys" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      stats = bank.get_statistics
      stats.has_key?("sti_funds").should be_true
      stats.has_key?("lti_funds").should be_true
      stats.has_key?("af_size").should be_true
      stats.has_key?("af_max_size").should be_true
      stats.has_key?("atomspace_size").should be_true
      stats.has_key?("sti_wage").should be_true
    end

    it "get_statistics reflects current state" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      concept = atomspace.add_concept_node("test")

      av = AtomSpace::AttentionValue.new(100_i16, 50_i16)
      bank.set_attention_value(concept.handle, av)

      stats = bank.get_statistics
      stats["atomspace_size"].should eq(1)
      stats["af_size"].should be >= 0
    end
  end
end
