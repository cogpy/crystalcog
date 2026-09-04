require "spec"
require "../../src/attention/query_optimizer"

private def build_optimizer(sti_map : Hash(String, Int16))
  atomspace = AtomSpace::AtomSpace.new
  bank = Attention::AttentionBank.new(atomspace)
  atoms = {} of String => AtomSpace::Atom
  sti_map.each do |name, sti|
    atom = atomspace.add_concept_node(name)
    bank.set_attention_value(atom.handle, AtomSpace::AttentionValue.new(sti, 0_i16, false))
    atoms[name] = atom
  end
  {bank, atoms}
end

describe Attention::AttentionQueryOptimizer do
  it "ranks atoms by attention importance (highest first)" do
    bank, atoms = build_optimizer({"low" => 10_i16, "high" => 500_i16, "mid" => 100_i16})
    optimizer = Attention::AttentionQueryOptimizer.new(bank)

    ranked = optimizer.rank_by_attention(atoms.values)
    ranked.first.should eq(atoms["high"])
    ranked.last.should eq(atoms["low"])
  end

  it "filters atoms below the STI threshold" do
    bank, atoms = build_optimizer({"low" => 10_i16, "high" => 500_i16})
    optimizer = Attention::AttentionQueryOptimizer.new(bank, min_sti: 100_i16)

    filtered = optimizer.filter_by_sti(atoms.values)
    filtered.should contain(atoms["high"])
    filtered.should_not contain(atoms["low"])
  end

  it "selects top-k atoms by STI" do
    bank, _atoms = build_optimizer({"a" => 10_i16, "b" => 500_i16, "c" => 100_i16})
    optimizer = Attention::AttentionQueryOptimizer.new(bank)

    top = optimizer.top_k_by_sti(2)
    top.size.should eq(2)
    stis = top.map { |a| bank.get_attention_value(a.handle).not_nil!.sti }
    stis.should contain(500_i16)
    stis.should contain(100_i16)
  end

  it "estimates lower cost with a larger focus fraction" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    optimizer = Attention::AttentionQueryOptimizer.new(bank)

    no_focus = optimizer.estimate_cost(100, 0.0)
    full_focus = optimizer.estimate_cost(100, 1.0)
    full_focus.should be < no_focus
    no_focus.should eq(100.0)
  end
end
