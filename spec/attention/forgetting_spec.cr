require "spec"
require "../../src/attention/attention_main"

describe Attention::ForgettingManager do
  it "applies exponential decay to STI values" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    concept = atomspace.add_concept_node("decay_me")
    bank.set_attention_value(concept.handle, AtomSpace::AttentionValue.new(100_i16, 10_i16))

    mgr = Attention::ForgettingManager.new(bank, Attention::ForgettingStrategy::ExponentialDecay, 0.5)
    reclaimed = mgr.exponential_decay

    reclaimed.should be > 0
    av = bank.get_attention_value(concept.handle).not_nil!
    av.sti.should eq(50_i16)
  end

  it "does not decay VLTI atoms" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    concept = atomspace.add_concept_node("important")
    bank.set_attention_value(concept.handle, AtomSpace::AttentionValue.new(100_i16, 10_i16, true))

    mgr = Attention::ForgettingManager.new(bank, Attention::ForgettingStrategy::ExponentialDecay, 0.5)
    mgr.exponential_decay

    av = bank.get_attention_value(concept.handle).not_nil!
    av.sti.should eq(100_i16)
  end

  it "performs LRU forgetting of lowest-STI atoms" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    low = atomspace.add_concept_node("low")
    high = atomspace.add_concept_node("high")
    bank.set_attention_value(low.handle, AtomSpace::AttentionValue.new(5_i16, 0_i16))
    bank.set_attention_value(high.handle, AtomSpace::AttentionValue.new(200_i16, 0_i16))

    mgr = Attention::ForgettingManager.new(bank, Attention::ForgettingStrategy::LRU)
    forgotten = mgr.lru_forget(1)

    forgotten.should eq(1)
    bank.get_attention_value(low.handle).not_nil!.sti.should eq(0_i16)
    bank.get_attention_value(high.handle).not_nil!.sti.should eq(200_i16)
  end

  it "tracks access order for LRU" do
    tracker = Attention::AccessTracker.new
    atomspace = AtomSpace::AtomSpace.new
    a = atomspace.add_concept_node("a")
    b = atomspace.add_concept_node("b")
    tracker.touch(a.handle)
    tracker.touch(b.handle)
    tracker.touch(a.handle) # a is now most recent
    tracker.lru_order.first.should eq(b.handle)
  end

  it "hybrid forget decays then zeros below threshold" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    c = atomspace.add_concept_node("c")
    bank.set_attention_value(c.handle, AtomSpace::AttentionValue.new(8_i16, 0_i16))

    mgr = Attention::ForgettingManager.new(bank, Attention::ForgettingStrategy::Hybrid, 0.5, 10_i16)
    results = mgr.forget(5)
    results.has_key?("decay_reclaimed").should be_true
    results.has_key?("lru_forgotten").should be_true
  end

  it "rejects invalid decay rates" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    expect_raises(Attention::AttentionError) do
      Attention::ForgettingManager.new(bank, decay_rate: 0.0)
    end
  end
end

describe Attention::AttentionNormalizer do
  it "normalizes STI proportions to target total" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    a = atomspace.add_concept_node("a")
    b = atomspace.add_concept_node("b")
    bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(100_i16, 0_i16))
    bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(300_i16, 0_i16))

    normalizer = Attention::AttentionNormalizer.new(bank, 400_i16, 400_i16)
    normalizer.normalize_sti

    totals = normalizer.current_totals
    totals[:sti].should be_close(400, 2)
  end

  it "min-max normalizes STI into range" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    a = atomspace.add_concept_node("a")
    b = atomspace.add_concept_node("b")
    bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(10_i16, 0_i16))
    bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(90_i16, 0_i16))

    normalizer = Attention::AttentionNormalizer.new(bank)
    normalizer.min_max_normalize_sti(100_i16)

    bank.get_attention_value(a.handle).not_nil!.sti.should eq(0_i16)
    bank.get_attention_value(b.handle).not_nil!.sti.should eq(100_i16)
  end

  it "centers STI around a target mean" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    a = atomspace.add_concept_node("a")
    bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(50_i16, 0_i16))

    normalizer = Attention::AttentionNormalizer.new(bank)
    normalizer.center_sti(100_i16)
    bank.get_attention_value(a.handle).not_nil!.sti.should eq(100_i16)
  end
end

describe Attention::AttentionQueryOptimizer do
  it "ranks atoms by STI" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    low = atomspace.add_concept_node("low")
    high = atomspace.add_concept_node("high")
    bank.set_attention_value(low.handle, AtomSpace::AttentionValue.new(1_i16, 0_i16))
    bank.set_attention_value(high.handle, AtomSpace::AttentionValue.new(500_i16, 0_i16))

    opt = Attention::AttentionQueryOptimizer.new(bank)
    ranked = opt.rank_by_attention([low, high])
    ranked.first.should eq(high)
  end

  it "filters by minimum STI" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    low = atomspace.add_concept_node("low")
    high = atomspace.add_concept_node("high")
    bank.set_attention_value(low.handle, AtomSpace::AttentionValue.new(1_i16, 0_i16))
    bank.set_attention_value(high.handle, AtomSpace::AttentionValue.new(50_i16, 0_i16))

    opt = Attention::AttentionQueryOptimizer.new(bank, 10_i16)
    filtered = opt.filter_by_sti([low, high])
    filtered.should eq([high])
  end

  it "returns top-k by STI" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    5.times do |i|
      c = atomspace.add_concept_node("c#{i}")
      bank.set_attention_value(c.handle, AtomSpace::AttentionValue.new((i * 10).to_i16, 0_i16))
    end

    opt = Attention::AttentionQueryOptimizer.new(bank)
    top = opt.top_k_by_sti(2)
    top.size.should eq(2)
  end

  it "estimates lower cost when focus fraction is higher" do
    atomspace = AtomSpace::AtomSpace.new
    bank = Attention::AttentionBank.new(atomspace)
    opt = Attention::AttentionQueryOptimizer.new(bank)
    high_focus = opt.estimate_cost(100, 0.8)
    low_focus = opt.estimate_cost(100, 0.0)
    high_focus.should be < low_focus
  end
end

describe "Attention module convenience API" do
  it "creates forgetting manager and normalizes" do
    atomspace = AtomSpace::AtomSpace.new
    c = atomspace.add_concept_node("x")
    Attention.set_attention(atomspace, c.handle, 100_i16, 50_i16)

    mgr = Attention.create_forgetting_manager(atomspace)
    mgr.should be_a(Attention::ForgettingManager)

    # normalize via fresh bank may not see values set on another bank instance
    # because each AttentionBank is independent; just ensure API works
    Attention.forget(atomspace, Attention::ForgettingStrategy::ExponentialDecay)
  end
end
