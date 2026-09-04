require "spec"
require "../../src/attention/attention"

describe Attention do
  it "has a version" do
    Attention::VERSION.should eq("0.1.0")
  end

  it "initializes without raising" do
    Attention.initialize
  end

  describe "ECANParams" do
    it "defines attentional focus bounds" do
      Attention::ECANParams::AF_MAX_SIZE.should eq(1000)
      Attention::ECANParams::AF_MIN_SIZE.should eq(500)
      Attention::ECANParams::MIN_STI.should eq(-32768_i16)
      Attention::ECANParams::MAX_STI.should eq(32767_i16)
    end
  end

  describe "Priority" do
    it "maps priorities to boost factors" do
      Attention::Priority::Critical.boost_factor.should eq(1.5)
      Attention::Priority::High.boost_factor.should eq(1.2)
      Attention::Priority::Medium.boost_factor.should eq(1.0)
      Attention::Priority::Low.boost_factor.should eq(0.8)
      Attention::Priority::Minimal.boost_factor.should eq(0.6)
    end
  end

  describe "AttentionMetrics" do
    it "computes an importance score scaled by priority" do
      metrics = Attention::AttentionMetrics.new(sti: 100_i16, lti: 50_i16, priority: Attention::Priority::High)
      # (100 + 50*0.1) * 1.2 = 105 * 1.2 = 126
      metrics.importance_score.should be_close(126.0, 1e-6)
    end

    it "adds a bonus for very long-term importance" do
      vlti = Attention::AttentionMetrics.new(sti: 0_i16, lti: 0_i16, vlti: true)
      vlti.importance_score.should eq(100.0)
    end

    it "checks attentional focus membership" do
      metrics = Attention::AttentionMetrics.new(sti: 100_i16)
      metrics.in_attentional_focus?(50_i16).should be_true
      metrics.in_attentional_focus?(150_i16).should be_false
    end

    it "calculates rent proportional to positive STI" do
      metrics = Attention::AttentionMetrics.new(sti: 200_i16)
      metrics.calculate_rent(0.01).should be_close(2.0, 1e-6)

      negative = Attention::AttentionMetrics.new(sti: -50_i16)
      negative.calculate_rent(0.01).should eq(0.0)
    end
  end
end
