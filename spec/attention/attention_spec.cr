require "spec"
require "../../src/attention/attention"

describe Attention do
  describe "module initialization" do
    it "initializes attention system" do
      Attention.initialize
    end

    it "has correct version" do
      Attention::VERSION.should eq("0.1.0")
    end
  end

  describe Attention::ECANParams do
    it "defines attentional focus size bounds" do
      Attention::ECANParams::AF_MAX_SIZE.should eq(1000)
      Attention::ECANParams::AF_MIN_SIZE.should eq(500)
      Attention::ECANParams::AF_MAX_SIZE.should be > Attention::ECANParams::AF_MIN_SIZE
    end

    it "defines fund targets and STI bounds" do
      Attention::ECANParams::TARGET_STI_FUNDS.should eq(10000)
      Attention::ECANParams::TARGET_LTI_FUNDS.should eq(10000)
      Attention::ECANParams::MIN_STI.should eq(-32768)
      Attention::ECANParams::MAX_STI.should eq(32767)
    end

    it "defines diffusion and forgetting defaults" do
      Attention::ECANParams::MAX_SPREAD_PERCENTAGE.should eq(0.4)
      Attention::ECANParams::DIFFUSION_TOURNAMENT_SIZE.should eq(5)
      Attention::ECANParams::RENT_TOURNAMENT_SIZE.should eq(5)
      Attention::ECANParams::DEFAULT_DECAY_RATE.should eq(0.1)
      Attention::ECANParams::DEFAULT_FORGET_THRESHOLD.should eq(0)
    end
  end

  describe Attention::Priority do
    it "provides correct boost factors for all levels" do
      Attention::Priority::Critical.boost_factor.should eq(1.5)
      Attention::Priority::High.boost_factor.should eq(1.2)
      Attention::Priority::Medium.boost_factor.should eq(1.0)
      Attention::Priority::Low.boost_factor.should eq(0.8)
      Attention::Priority::Minimal.boost_factor.should eq(0.6)
    end

    it "orders boost factors by priority strength" do
      Attention::Priority::Critical.boost_factor.should be > Attention::Priority::High.boost_factor
      Attention::Priority::High.boost_factor.should be > Attention::Priority::Medium.boost_factor
      Attention::Priority::Medium.boost_factor.should be > Attention::Priority::Low.boost_factor
      Attention::Priority::Low.boost_factor.should be > Attention::Priority::Minimal.boost_factor
    end
  end

  describe Attention::AttentionMetrics do
    it "creates metrics with defaults" do
      metrics = Attention::AttentionMetrics.new

      metrics.sti.should eq(0)
      metrics.lti.should eq(0)
      metrics.vlti.should be_false
      metrics.priority.should eq(Attention::Priority::Medium)
      metrics.rent.should eq(0.0)
      metrics.spreading_factor.should eq(0.0)
    end

    it "creates metrics with custom values" do
      metrics = Attention::AttentionMetrics.new(100_i16, 50_i16, true, Attention::Priority::High, 1.5, 0.25)

      metrics.sti.should eq(100)
      metrics.lti.should eq(50)
      metrics.vlti.should be_true
      metrics.priority.should eq(Attention::Priority::High)
      metrics.rent.should eq(1.5)
      metrics.spreading_factor.should eq(0.25)
    end

    it "calculates importance score with STI, LTI, VLTI, and priority" do
      metrics = Attention::AttentionMetrics.new(100_i16, 50_i16, true, Attention::Priority::High)

      # Base: 100 + (50 * 0.1) + 100 = 205; High boost 1.2 => 246
      expected = (100.0 + (50.0 * 0.1) + 100.0) * 1.2
      metrics.importance_score.should be_close(expected, 0.01)
    end

    it "omits VLTI bonus when vlti is false" do
      with_vlti = Attention::AttentionMetrics.new(100_i16, 0_i16, true)
      without_vlti = Attention::AttentionMetrics.new(100_i16, 0_i16, false)

      with_vlti.importance_score.should eq(200.0)
      without_vlti.importance_score.should eq(100.0)
    end

    it "checks attentional focus membership by STI threshold" do
      metrics = Attention::AttentionMetrics.new(100_i16)

      metrics.in_attentional_focus?(50_i16).should be_true
      metrics.in_attentional_focus?(100_i16).should be_true
      metrics.in_attentional_focus?(150_i16).should be_false
    end

    it "calculates rent from STI and rate" do
      metrics = Attention::AttentionMetrics.new(100_i16)
      metrics.calculate_rent(0.02).should eq(2.0)
      metrics.calculate_rent.should eq(1.0) # default rate 0.01
    end

    it "returns zero rent for non-positive STI" do
      metrics = Attention::AttentionMetrics.new(-10_i16)
      metrics.calculate_rent(0.5).should eq(0.0)
    end

    it "diffuses STI to targets and reduces own STI" do
      source = Attention::AttentionMetrics.new(100_i16)
      t1 = Attention::AttentionMetrics.new(0_i16)
      t2 = Attention::AttentionMetrics.new(0_i16)

      source.diffuse_to([t1, t2], 0.4)

      # spread_amount = (100 * 0.4 / 2).round = 20
      source.sti.should eq(60)
      t1.sti.should eq(20)
      t2.sti.should eq(20)
    end

    it "does nothing when diffusing to an empty target list" do
      source = Attention::AttentionMetrics.new(100_i16)
      source.diffuse_to([] of Attention::AttentionMetrics)
      source.sti.should eq(100)
    end

    it "skips diffusion when computed spread amount is non-positive" do
      source = Attention::AttentionMetrics.new(1_i16)
      target = Attention::AttentionMetrics.new(0_i16)

      source.diffuse_to([target], 0.0)
      source.sti.should eq(1)
      target.sti.should eq(0)
    end

    it "clamps target STI to MAX_STI during diffusion" do
      source = Attention::AttentionMetrics.new(1000_i16)
      target = Attention::AttentionMetrics.new(Attention::ECANParams::MAX_STI)

      source.diffuse_to([target], 1.0)
      target.sti.should eq(Attention::ECANParams::MAX_STI)
    end

    it "formats a readable string representation" do
      metrics = Attention::AttentionMetrics.new(10_i16, 5_i16, false, Attention::Priority::Low)
      metrics.to_s.should eq("AV[STI:10, LTI:5, VLTI:false, Priority:Low]")
    end
  end

  describe Attention::AttentionError do
    it "is an Exception subclass" do
      error = Attention::AttentionError.new("test failure")
      error.should be_a(Exception)
      error.message.should eq("test failure")
    end
  end
end
