require "spec"
require "../../src/attention/normalization"

describe Attention::AttentionNormalizer do
  describe "initialization" do
    it "creates a normalizer with default targets" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      normalizer = Attention::AttentionNormalizer.new(bank)

      normalizer.should_not be_nil
      normalizer.target_sti_total.should eq(Attention::ECANParams::TARGET_STI_FUNDS)
      normalizer.target_lti_total.should eq(Attention::ECANParams::TARGET_LTI_FUNDS)
      normalizer.bank.should eq(bank)
    end

    it "accepts custom STI and LTI targets" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      normalizer = Attention::AttentionNormalizer.new(bank, 500_i16, 750_i16)

      normalizer.target_sti_total.should eq(500)
      normalizer.target_lti_total.should eq(750)
    end
  end

  describe "#current_totals" do
    it "returns zeros for an empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      normalizer = Attention::AttentionNormalizer.new(bank)

      totals = normalizer.current_totals
      totals[:sti].should eq(0)
      totals[:lti].should eq(0)
      totals[:count].should eq(0)
    end

    it "ignores atoms without attention values" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      atomspace.add_concept_node("no_av")
      normalizer = Attention::AttentionNormalizer.new(bank)

      totals = normalizer.current_totals
      totals[:count].should eq(0)
      totals[:sti].should eq(0)
      totals[:lti].should eq(0)
    end

    it "sums STI and LTI across atoms with attention values" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(100_i16, 20_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(300_i16, 40_i16))

      normalizer = Attention::AttentionNormalizer.new(bank)
      totals = normalizer.current_totals

      totals[:sti].should eq(400)
      totals[:lti].should eq(60)
      totals[:count].should eq(2)
    end
  end

  describe "#normalize_sti" do
    it "returns 0 when there are no atoms with attention values" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      normalizer = Attention::AttentionNormalizer.new(bank, 400_i16, 400_i16)

      normalizer.normalize_sti.should eq(0)
    end

    it "returns 0 when total STI is zero" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(0_i16, 10_i16))
      normalizer = Attention::AttentionNormalizer.new(bank, 400_i16, 400_i16)

      normalizer.normalize_sti.should eq(0)
      bank.get_attention_value(a.handle).not_nil!.sti.should eq(0)
    end

    it "scales STI values so their sum matches the target total" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(50_i16, 5_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(150_i16, 5_i16))

      normalizer = Attention::AttentionNormalizer.new(bank, 400_i16, 400_i16)
      updated = normalizer.normalize_sti
      updated.should be > 0

      totals = normalizer.current_totals
      totals[:sti].should be_close(400, 2)

      # Relative proportions preserved (1:3)
      sti_a = bank.get_attention_value(a.handle).not_nil!.sti
      sti_b = bank.get_attention_value(b.handle).not_nil!.sti
      sti_a.should be_close(100, 2)
      sti_b.should be_close(300, 2)

      # LTI unchanged by normalize_sti
      bank.get_attention_value(a.handle).not_nil!.lti.should eq(5)
      bank.get_attention_value(b.handle).not_nil!.lti.should eq(5)
    end

    it "preserves VLTI flag when updating STI" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(50_i16, 10_i16, true))

      normalizer = Attention::AttentionNormalizer.new(bank, 100_i16, 100_i16)
      normalizer.normalize_sti

      av = bank.get_attention_value(a.handle).not_nil!
      av.vlti.should be_true
      av.sti.should eq(100)
    end
  end

  describe "#normalize_lti" do
    it "returns 0 when total LTI is zero" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(10_i16, 0_i16))
      normalizer = Attention::AttentionNormalizer.new(bank, 400_i16, 400_i16)

      normalizer.normalize_lti.should eq(0)
    end

    it "scales LTI values so their sum matches the target total" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(10_i16, 25_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(20_i16, 75_i16))

      normalizer = Attention::AttentionNormalizer.new(bank, 400_i16, 200_i16)
      updated = normalizer.normalize_lti
      updated.should be > 0

      totals = normalizer.current_totals
      totals[:lti].should be_close(200, 2)

      lti_a = bank.get_attention_value(a.handle).not_nil!.lti
      lti_b = bank.get_attention_value(b.handle).not_nil!.lti
      lti_a.should be_close(50, 2)
      lti_b.should be_close(150, 2)

      # STI unchanged by normalize_lti
      bank.get_attention_value(a.handle).not_nil!.sti.should eq(10)
      bank.get_attention_value(b.handle).not_nil!.sti.should eq(20)
    end
  end

  describe "#normalize_all" do
    it "returns counts for both STI and LTI updates" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(50_i16, 25_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(150_i16, 75_i16))

      normalizer = Attention::AttentionNormalizer.new(bank, 400_i16, 200_i16)
      result = normalizer.normalize_all

      result.has_key?("sti_updated").should be_true
      result.has_key?("lti_updated").should be_true
      result["sti_updated"].should be > 0
      result["lti_updated"].should be > 0

      totals = normalizer.current_totals
      totals[:sti].should be_close(400, 2)
      totals[:lti].should be_close(200, 2)
    end

    it "returns zero updates for empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      normalizer = Attention::AttentionNormalizer.new(bank)

      result = normalizer.normalize_all
      result["sti_updated"].should eq(0)
      result["lti_updated"].should eq(0)
    end
  end

  describe "#min_max_normalize_sti" do
    it "returns 0 when there are no attention values" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      normalizer = Attention::AttentionNormalizer.new(bank)

      normalizer.min_max_normalize_sti.should eq(0)
    end

    it "returns 0 when all STI values are equal (zero range)" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(40_i16, 0_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(40_i16, 0_i16))

      normalizer = Attention::AttentionNormalizer.new(bank)
      normalizer.min_max_normalize_sti(100_i16).should eq(0)
      bank.get_attention_value(a.handle).not_nil!.sti.should eq(40)
    end

    it "maps min STI to 0 and max STI to max_sti while preserving order" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      c = atomspace.add_concept_node("c")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(10_i16, 1_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(50_i16, 2_i16))
      bank.set_attention_value(c.handle, AtomSpace::AttentionValue.new(90_i16, 3_i16))

      normalizer = Attention::AttentionNormalizer.new(bank)
      updated = normalizer.min_max_normalize_sti(100_i16)
      updated.should be > 0

      bank.get_attention_value(a.handle).not_nil!.sti.should eq(0)
      bank.get_attention_value(c.handle).not_nil!.sti.should eq(100)
      bank.get_attention_value(b.handle).not_nil!.sti.should be_close(50, 1)

      # LTI preserved
      bank.get_attention_value(a.handle).not_nil!.lti.should eq(1)
      bank.get_attention_value(b.handle).not_nil!.lti.should eq(2)
      bank.get_attention_value(c.handle).not_nil!.lti.should eq(3)
    end
  end

  describe "#center_sti" do
    it "returns 0 for empty atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      normalizer = Attention::AttentionNormalizer.new(bank)

      normalizer.center_sti.should eq(0)
    end

    it "returns 0 when mean already equals target" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(100_i16, 0_i16))

      normalizer = Attention::AttentionNormalizer.new(bank)
      normalizer.center_sti(100_i16).should eq(0)
      bank.get_attention_value(a.handle).not_nil!.sti.should eq(100)
    end

    it "shifts STI so the mean is near the target" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(40_i16, 7_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(60_i16, 8_i16))

      normalizer = Attention::AttentionNormalizer.new(bank)
      updated = normalizer.center_sti(100_i16)
      updated.should be > 0

      # mean was 50, shift +50 => 90 and 110
      bank.get_attention_value(a.handle).not_nil!.sti.should eq(90)
      bank.get_attention_value(b.handle).not_nil!.sti.should eq(110)

      totals = normalizer.current_totals
      mean = totals[:sti].to_f64 / totals[:count]
      mean.should be_close(100.0, 1.0)

      # LTI unchanged
      bank.get_attention_value(a.handle).not_nil!.lti.should eq(7)
      bank.get_attention_value(b.handle).not_nil!.lti.should eq(8)
    end
  end
end
