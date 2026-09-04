require "spec"
require "../../src/attention/normalization"

private def build_bank_with_atoms(sti_values : Array(Int16))
  atomspace = AtomSpace::AtomSpace.new
  bank = Attention::AttentionBank.new(atomspace)
  sti_values.each_with_index do |sti, i|
    atom = atomspace.add_concept_node("norm_atom_#{i}")
    bank.set_attention_value(atom.handle, AtomSpace::AttentionValue.new(sti, 0_i16, false))
  end
  bank
end

describe Attention::AttentionNormalizer do
  it "computes current STI/LTI totals" do
    bank = build_bank_with_atoms([100_i16, 200_i16, 300_i16])
    normalizer = Attention::AttentionNormalizer.new(bank)

    totals = normalizer.current_totals
    totals[:sti].should eq(600_i64)
    totals[:count].should eq(3)
  end

  it "normalizes STI to the target total" do
    bank = build_bank_with_atoms([100_i16, 300_i16])
    normalizer = Attention::AttentionNormalizer.new(bank, target_sti_total: 1000_i16)

    updated = normalizer.normalize_sti
    updated.should be > 0

    # After normalization the sum of STI should approach the target total
    normalizer.current_totals[:sti].should be_close(1000_i64, 2)
  end

  it "returns zero when there is nothing to normalize" do
    bank = build_bank_with_atoms([] of Int16)
    normalizer = Attention::AttentionNormalizer.new(bank)
    normalizer.normalize_sti.should eq(0)
  end

  it "min-max normalizes STI into the requested range" do
    bank = build_bank_with_atoms([10_i16, 50_i16, 100_i16])
    normalizer = Attention::AttentionNormalizer.new(bank)

    updated = normalizer.min_max_normalize_sti(1000_i16)
    updated.should eq(3)

    stis = bank.atomspace.get_all_atoms.map { |a| bank.get_attention_value(a.handle).not_nil!.sti }
    stis.min.should eq(0_i16)
    stis.max.should eq(1000_i16)
  end

  it "centers STI around the target mean" do
    bank = build_bank_with_atoms([50_i16, 150_i16])
    normalizer = Attention::AttentionNormalizer.new(bank)

    normalizer.center_sti(100_i16)
    totals = normalizer.current_totals
    (totals[:sti] / totals[:count]).should be_close(100_i64, 1)
  end
end
