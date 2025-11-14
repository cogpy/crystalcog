require "spec"
require "../../src/attention/attention_main"

describe Attention do
  describe "module initialization" do
    it "initializes attention system" do
      Attention.initialize
      # Should not crash
    end

    it "has correct version" do
      Attention::VERSION.should eq("0.1.0")
    end
  end

  describe "ECANParams" do
    it "has reasonable parameter values" do
      Attention::ECANParams::AF_MAX_SIZE.should eq(1000)
      Attention::ECANParams::AF_MIN_SIZE.should eq(500)
      Attention::ECANParams::TARGET_STI_FUNDS.should eq(10000)
      Attention::ECANParams::MAX_SPREAD_PERCENTAGE.should eq(0.4)
    end
  end

  describe "Priority enum" do
    it "provides correct boost factors" do
      Attention::Priority::Critical.boost_factor.should eq(1.5)
      Attention::Priority::High.boost_factor.should eq(1.2)
      Attention::Priority::Medium.boost_factor.should eq(1.0)
      Attention::Priority::Low.boost_factor.should eq(0.8)
      Attention::Priority::Minimal.boost_factor.should eq(0.6)
    end
  end

  describe "AttentionMetrics" do
    it "creates valid attention metrics" do
      metrics = Attention::AttentionMetrics.new(100_i16, 50_i16, true)

      metrics.sti.should eq(100)
      metrics.lti.should eq(50)
      metrics.vlti.should be_true
    end

    it "calculates importance score correctly" do
      metrics = Attention::AttentionMetrics.new(100_i16, 50_i16, true, Attention::Priority::High)

      # Base: 100 + (50 * 0.1) + 100 = 205
      # With High priority boost: 205 * 1.2 = 246
      expected_score = (100.0 + (50.0 * 0.1) + 100.0) * 1.2
      metrics.importance_score.should be_close(expected_score, 0.01)
    end

    it "checks attentional focus correctly" do
      metrics = Attention::AttentionMetrics.new(100_i16)

      metrics.in_attentional_focus?(50_i16).should be_true
      metrics.in_attentional_focus?(150_i16).should be_false
    end

    it "calculates rent correctly" do
      metrics = Attention::AttentionMetrics.new(100_i16)
      rent = metrics.calculate_rent(0.02)

      rent.should eq(2.0) # 100 * 0.02
    end
  end

  describe "AttentionBank" do
    before_each do
      @atomspace = AtomSpace::AtomSpace.new
    end
    
    # Helper method to access atomspace instance
    def atomspace
      @atomspace
    end
    
    it "initializes with correct funds" do
      bank = Attention::AttentionBank.new(atomspace)

      bank.sti_funds.should eq(Attention::ECANParams::TARGET_STI_FUNDS)
      bank.lti_funds.should eq(Attention::ECANParams::TARGET_LTI_FUNDS)
    end

    it "sets and gets attention values" do
      bank = Attention::AttentionBank.new(atomspace)
      dog = atomspace.add_concept_node("dog")
      av = AtomSpace::AttentionValue.new(100_i16, 50_i16, true)

      result = bank.set_attention_value(dog.handle, av)
      result.should be_true

      retrieved_av = bank.get_attention_value(dog.handle)
      retrieved_av.should_not be_nil
      retrieved_av.not_nil!.sti.should eq(100)
      retrieved_av.not_nil!.lti.should eq(50)
      retrieved_av.not_nil!.vlti.should be_true
    end

    it "manages attentional focus" do
      bank = Attention::AttentionBank.new(atomspace)
      dog = atomspace.add_concept_node("dog")

      bank.in_attentional_focus?(dog.handle).should be_false

      # Stimulate to add to AF
      bank.stimulate(dog.handle, 100_i16)

      bank.in_attentional_focus?(dog.handle).should be_true
      bank.attentional_focus.should contain(dog.handle)
    end
  end

  describe "Goal enum" do
    it "provides correct boost factors" do
      Attention::Goal::Reasoning.boost_factor.should eq(0.9)
      Attention::Goal::Learning.boost_factor.should eq(0.7)
      Attention::Goal::Memory.boost_factor.should eq(0.65)
      Attention::Goal::Processing.boost_factor.should eq(0.85)
    end
  end

  describe "module convenience functions" do
    before_each do
      @dog = atomspace.add_concept_node("dog")
    end

    it "creates allocation engines" do
      engine = Attention.create_engine(atomspace)
      engine.should be_a(Attention::AllocationEngine)
    end

    it "performs quick attention allocation" do
      results = Attention.allocate_attention(atomspace, 1)
      results.should be_a(Hash(String, Float64))
    end

    it "sets and gets attention values" do
      Attention.set_attention(atomspace, @dog.handle, 100_i16, 50_i16, true)

      av = Attention.get_attention(atomspace, @dog.handle)
      av.should_not be_nil
      av.not_nil!.sti.should eq(100)
      av.not_nil!.lti.should eq(50)
      av.not_nil!.vlti.should be_true
    end

    it "stimulates atoms" do
      Attention.stimulate(atomspace, @dog.handle, 75_i16)

      av = Attention.get_attention(atomspace, @dog.handle)
      av.should_not be_nil
      av.not_nil!.sti.should eq(75)
    end

    it "gets statistics" do
      stats = Attention.get_statistics(atomspace)
      stats.should be_a(Hash(String, Float64))
      stats.should have_key("bank_sti_funds")
    end
  end
end
