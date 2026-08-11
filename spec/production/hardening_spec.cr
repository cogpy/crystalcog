require "spec"
require "../../src/production/hardening"

describe Production::RateLimiter do
  it "allows up to capacity then rejects" do
    lim = Production::RateLimiter.new(3.0, 0.0001)
    lim.allow?.should be_true
    lim.allow?.should be_true
    lim.allow?.should be_true
    lim.allow?.should be_false
  end

  it "rejects invalid construction" do
    expect_raises(Production::ProductionException) do
      Production::RateLimiter.new(0.0)
    end
  end
end

describe Production::KeyedRateLimiter do
  it "tracks keys independently" do
    lim = Production::KeyedRateLimiter.new(1.0, 0.0001)
    lim.allow?("a").should be_true
    lim.allow?("a").should be_false
    lim.allow?("b").should be_true
  end
end

describe Production::Authenticator do
  it "issues and validates tokens" do
    auth = Production::Authenticator.new
    token = auth.issue("alice")
    auth.authenticate(token).should eq("alice")
    auth.authorized?(token, "alice").should be_true
    auth.authorized?(token, "bob").should be_false
    auth.revoke(token)
    auth.authenticate(token).should be_nil
  end
end

describe Production::MetricsRegistry do
  it "exports prometheus text" do
    m = Production::MetricsRegistry.new
    m.inc("http_requests_total")
    m.inc("http_requests_total")
    m.gauge("queue_depth", 3.0)
    m.observe("latency_ms", 12.0)
    m.observe("latency_ms", 18.0)
    text = m.export_prometheus
    text.should contain("http_requests_total 2")
    text.should contain("queue_depth 3")
    text.should contain("latency_ms_count 2")
    m.counter("http_requests_total").should eq(2.0)
  end
end

describe Production::HealthChecker do
  it "aggregates check results" do
    hc = Production::HealthChecker.new
    hc.register("db") { {true, "ok"} }
    hc.register("cache") { {false, "down"} }
    result = hc.run
    result["status"].as_s.should eq("unhealthy")
    hc.healthy?.should be_false
  end

  it "reports healthy when all pass" do
    hc = Production::HealthChecker.new
    hc.register("ok") { {true, "fine"} }
    hc.healthy?.should be_true
  end
end
