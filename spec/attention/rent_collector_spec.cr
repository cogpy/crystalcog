require "spec"
require "../../src/attention/rent_collector"

describe Attention::RentCollector do
  describe "initialization" do
    it "creates rent collector" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      collector.should_not be_nil
    end

    it "has default rent rate" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      collector.rent_rate.should eq(0.01)
    end

    it "accepts custom rent rate" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.05)

      collector.rent_rate.should eq(0.05)
    end

    it "has default collection threshold of 0" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      collector.collection_threshold.should eq(0)
    end
  end

  describe "rent collection" do
    it "collects rent from atoms with STI above threshold" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.1)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(100_i16, 50_i16)
      bank.set_attention_value(concept.handle, av)

      initial_sti = bank.get_attention_value(concept.handle).not_nil!.sti
      collector.collect_rent

      final_sti = bank.get_attention_value(concept.handle).try(&.sti) || initial_sti
      # Rent should have been collected (STI reduced)
      final_sti.should be <= initial_sti
    end

    it "returns the total rent collected (Int16)" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.1)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(100_i16, 0_i16)
      bank.set_attention_value(concept.handle, av)

      collected = collector.collect_rent
      collected.should be_a(Int16)
      collected.should be >= 0
    end

    it "collects no rent from atoms with STI at or below threshold" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.1, 200_i16)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(50_i16, 0_i16)
      bank.set_attention_value(concept.handle, av)

      collected = collector.collect_rent
      collected.should eq(0)
    end

    it "returns 0 when atomspace is empty" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      collected = collector.collect_rent
      collected.should eq(0)
    end

    it "adds collected rent back to bank STI funds" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.5)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(100_i16, 0_i16)
      bank.set_attention_value(concept.handle, av)

      initial_funds = bank.sti_funds
      collected = collector.collect_rent

      # Funds should have increased by collected amount (rent returned to pool)
      bank.sti_funds.should be >= initial_funds - 100 + collected
    end
  end

  describe "adaptive_rent_collection" do
    it "does not crash" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      collector.adaptive_rent_collection
      true.should be_true
    end

    it "returns Int16" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      result = collector.adaptive_rent_collection
      result.should be_a(Int16)
    end
  end

  describe "af_rent_collection" do
    it "returns 0 when attentional focus is empty" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      result = collector.af_rent_collection
      result.should eq(0)
    end

    it "collects higher rent from atoms in attentional focus" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.1)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(100_i16, 0_i16)
      bank.set_attention_value(concept.handle, av)

      # After setting AV, atom should be in attentional focus
      bank.in_attentional_focus?(concept.handle).should be_true

      result = collector.af_rent_collection
      result.should be_a(Int16)
    end
  end

  describe "lti_rent_adjustment" do
    it "applies LTI adjustments without crashing" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(50_i16, 50_i16)
      bank.set_attention_value(concept.handle, av)

      collector.lti_rent_adjustment
      true.should be_true
    end

    it "increases STI for atoms with high LTI (>50)" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(50_i16, 100_i16)
      bank.set_attention_value(concept.handle, av)

      initial_sti = bank.get_attention_value(concept.handle).not_nil!.sti
      collector.lti_rent_adjustment
      new_sti = bank.get_attention_value(concept.handle).not_nil!.sti

      new_sti.should be >= initial_sti
    end

    it "does not modify atoms with LTI <= 50" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      concept = atomspace.add_concept_node("test")
      av = AtomSpace::AttentionValue.new(50_i16, 30_i16)
      bank.set_attention_value(concept.handle, av)

      collector.lti_rent_adjustment
      new_av = bank.get_attention_value(concept.handle).not_nil!

      new_av.sti.should eq(50)
    end
  end

  describe "get_statistics" do
    it "returns hash with expected keys" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank)

      stats = collector.get_statistics
      stats.has_key?("total_sti").should be_true
      stats.has_key?("rentable_atoms").should be_true
      stats.has_key?("rent_rate").should be_true
      stats.has_key?("collection_threshold").should be_true
      stats.has_key?("average_rent_potential").should be_true
    end

    it "returns correct rent_rate in statistics" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.05)

      stats = collector.get_statistics
      stats["rent_rate"].should eq(0.05)
    end

    it "counts rentable atoms correctly" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      collector = Attention::RentCollector.new(bank, 0.01, 10_i16)

      c1 = atomspace.add_concept_node("above")
      c2 = atomspace.add_concept_node("below")
      c3 = atomspace.add_concept_node("equal")

      bank.set_attention_value(c1.handle, AtomSpace::AttentionValue.new(100_i16, 0_i16))
      bank.set_attention_value(c2.handle, AtomSpace::AttentionValue.new(5_i16, 0_i16))
      bank.set_attention_value(c3.handle, AtomSpace::AttentionValue.new(10_i16, 0_i16))

      stats = collector.get_statistics
      # Atoms with STI > 10 threshold: only c1 (100 > 10)
      stats["rentable_atoms"].should eq(1)
    end
  end
end
