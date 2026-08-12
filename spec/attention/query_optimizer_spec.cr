require "spec"
require "../../src/attention/attention_main"
require "../../src/pattern_matching/pattern_matching"

describe Attention::AttentionQueryOptimizer do
  describe "initialization" do
    it "creates an optimizer with defaults" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      opt = Attention::AttentionQueryOptimizer.new(bank)

      opt.bank.should eq(bank)
      opt.min_sti.should eq(0_i16)
      opt.prefer_focus.should be_true
    end

    it "accepts custom min_sti and prefer_focus" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      opt = Attention::AttentionQueryOptimizer.new(bank, 25_i16, false)

      opt.min_sti.should eq(25_i16)
      opt.prefer_focus.should be_false
    end
  end

  describe "rank_by_attention" do
    it "ranks atoms by STI then LTI (highest first)" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      low = atomspace.add_concept_node("low")
      mid = atomspace.add_concept_node("mid")
      high = atomspace.add_concept_node("high")

      bank.set_attention_value(low.handle, AtomSpace::AttentionValue.new(1_i16, 100_i16))
      bank.set_attention_value(mid.handle, AtomSpace::AttentionValue.new(50_i16, 0_i16))
      bank.set_attention_value(high.handle, AtomSpace::AttentionValue.new(500_i16, 0_i16))

      opt = Attention::AttentionQueryOptimizer.new(bank)
      ranked = opt.rank_by_attention([low, mid, high])

      ranked.map(&.as(AtomSpace::Node).name).should eq(["high", "mid", "low"])
    end

    it "treats missing attention values as zero importance" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      plain = atomspace.add_concept_node("plain")
      boosted = atomspace.add_concept_node("boosted")
      bank.set_attention_value(boosted.handle, AtomSpace::AttentionValue.new(10_i16, 0_i16))

      opt = Attention::AttentionQueryOptimizer.new(bank)
      ranked = opt.rank_by_attention([plain, boosted])

      ranked.first.should eq(boosted)
      ranked.last.should eq(plain)
    end

    it "breaks STI ties using LTI" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      a = atomspace.add_concept_node("a")
      b = atomspace.add_concept_node("b")
      bank.set_attention_value(a.handle, AtomSpace::AttentionValue.new(20_i16, 1_i16))
      bank.set_attention_value(b.handle, AtomSpace::AttentionValue.new(20_i16, 50_i16))

      opt = Attention::AttentionQueryOptimizer.new(bank)
      ranked = opt.rank_by_attention([a, b])

      ranked.first.should eq(b)
    end
  end

  describe "filter_by_sti" do
    it "keeps atoms at or above the STI threshold" do
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

    it "includes atoms without AV when min_sti is non-positive" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      plain = atomspace.add_concept_node("plain")

      opt = Attention::AttentionQueryOptimizer.new(bank, 0_i16)
      opt.filter_by_sti([plain]).should eq([plain])
    end

    it "excludes atoms without AV when min_sti is positive" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      plain = atomspace.add_concept_node("plain")

      opt = Attention::AttentionQueryOptimizer.new(bank, 1_i16)
      opt.filter_by_sti([plain]).should be_empty
    end
  end

  describe "prioritize_focus" do
    it "places attentional-focus atoms before others" do
      atomspace = AtomSpace::AtomSpace.new
      # Keep AF small so only the high-STI atom stays in focus
      bank = Attention::AttentionBank.new(atomspace, 1, 1)
      focused = atomspace.add_concept_node("focused")
      outside = atomspace.add_concept_node("outside")

      bank.set_attention_value(focused.handle, AtomSpace::AttentionValue.new(500_i16, 0_i16))
      bank.set_attention_value(outside.handle, AtomSpace::AttentionValue.new(1_i16, 0_i16))

      bank.in_attentional_focus?(focused.handle).should be_true
      bank.in_attentional_focus?(outside.handle).should be_false

      opt = Attention::AttentionQueryOptimizer.new(bank, 0_i16, true)
      ordered = opt.prioritize_focus([outside, focused])

      ordered.first.should eq(focused)
      ordered.last.should eq(outside)
    end

    it "falls back to rank_by_attention when prefer_focus is false" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace, 1, 1)
      focused = atomspace.add_concept_node("focused")
      outside = atomspace.add_concept_node("outside")

      bank.set_attention_value(focused.handle, AtomSpace::AttentionValue.new(10_i16, 0_i16))
      bank.set_attention_value(outside.handle, AtomSpace::AttentionValue.new(100_i16, 0_i16))

      opt = Attention::AttentionQueryOptimizer.new(bank, 0_i16, false)
      ordered = opt.prioritize_focus([focused, outside])

      # Outside has higher STI; without prefer_focus it should rank first
      ordered.first.should eq(outside)
    end
  end

  describe "optimize_candidates" do
    it "filters by STI then prioritizes focus" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace, 1, 1)
      low = atomspace.add_concept_node("low")
      focused = atomspace.add_concept_node("focused")
      outside = atomspace.add_concept_node("outside")

      bank.set_attention_value(low.handle, AtomSpace::AttentionValue.new(1_i16, 0_i16))
      bank.set_attention_value(focused.handle, AtomSpace::AttentionValue.new(200_i16, 0_i16))
      bank.set_attention_value(outside.handle, AtomSpace::AttentionValue.new(50_i16, 0_i16))

      opt = Attention::AttentionQueryOptimizer.new(bank, 10_i16, true)
      optimized = opt.optimize_candidates([low, outside, focused])

      optimized.includes?(low).should be_false
      optimized.first.should eq(focused)
      optimized.should contain(outside)
    end
  end

  describe "estimate_cost" do
    it "returns candidate count when focus fraction is zero" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      opt = Attention::AttentionQueryOptimizer.new(bank)

      opt.estimate_cost(100, 0.0).should eq(100.0)
    end

    it "estimates lower cost when focus fraction is higher" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      opt = Attention::AttentionQueryOptimizer.new(bank)

      high_focus = opt.estimate_cost(100, 0.8)
      low_focus = opt.estimate_cost(100, 0.0)
      high_focus.should be < low_focus
    end

    it "clamps focus fraction to [0, 1]" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      opt = Attention::AttentionQueryOptimizer.new(bank)

      opt.estimate_cost(100, 2.0).should eq(opt.estimate_cost(100, 1.0))
      opt.estimate_cost(100, -1.0).should eq(opt.estimate_cost(100, 0.0))
    end
  end

  describe "top_k_by_sti" do
    it "returns the k highest-STI atoms from the atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      5.times do |i|
        c = atomspace.add_concept_node("c#{i}")
        bank.set_attention_value(c.handle, AtomSpace::AttentionValue.new((i * 10).to_i16, 0_i16))
      end

      opt = Attention::AttentionQueryOptimizer.new(bank)
      top = opt.top_k_by_sti(2)

      top.size.should eq(2)
      top.first.as(AtomSpace::Node).name.should eq("c4")
      top.last.as(AtomSpace::Node).name.should eq("c3")
    end

    it "returns all atoms when k exceeds atomspace size" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      atomspace.add_concept_node("only")

      opt = Attention::AttentionQueryOptimizer.new(bank)
      opt.top_k_by_sti(10).size.should eq(1)
    end
  end

  describe "optimized_match" do
    it "ranks match results by average STI of matched atoms" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)

      low = atomspace.add_concept_node("low_match")
      high = atomspace.add_concept_node("high_match")
      bank.set_attention_value(low.handle, AtomSpace::AttentionValue.new(5_i16, 0_i16))
      bank.set_attention_value(high.handle, AtomSpace::AttentionValue.new(400_i16, 0_i16))

      # Concrete ConceptNode templates may yield multiple same-type candidates;
      # the optimizer must order those results by average matched STI.
      pattern = PatternMatching::Pattern.new(low)
      opt = Attention::AttentionQueryOptimizer.new(bank)
      results = opt.optimized_match(pattern)

      results.size.should be >= 2
      results.first.matched_atoms.should contain(high)

      avg = ->(result : PatternMatching::MatchResult) do
        return 0.0 if result.matched_atoms.empty?
        total = result.matched_atoms.sum do |atom|
          av = bank.get_attention_value(atom.handle)
          av ? av.sti.to_f64 : 0.0
        end
        total / result.matched_atoms.size
      end

      avg.call(results.first).should be >= avg.call(results.last)
    end

    it "returns an empty array when nothing matches" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      missing = AtomSpace::ConceptNode.new("not_in_space")
      pattern = PatternMatching::Pattern.new(missing)

      opt = Attention::AttentionQueryOptimizer.new(bank)
      opt.optimized_match(pattern).should be_empty
    end

    it "respects max_results when forwarding to the matcher" do
      atomspace = AtomSpace::AtomSpace.new
      bank = Attention::AttentionBank.new(atomspace)
      3.times { |i| atomspace.add_concept_node("n#{i}") }

      pattern = PatternMatching::Pattern.new(atomspace.add_concept_node("seed"))
      opt = Attention::AttentionQueryOptimizer.new(bank)
      opt.optimized_match(pattern, 1).size.should eq(1)
    end
  end

  describe "Attention.create_query_optimizer" do
    it "builds an optimizer bound to a fresh bank" do
      atomspace = AtomSpace::AtomSpace.new
      opt = Attention.create_query_optimizer(atomspace, 15_i16)

      opt.should be_a(Attention::AttentionQueryOptimizer)
      opt.min_sti.should eq(15_i16)
      opt.bank.atomspace.should eq(atomspace)
    end
  end
end
