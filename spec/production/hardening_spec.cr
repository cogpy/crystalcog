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

  describe Production::RequestGuard do
    it "authenticates bearer tokens when configured" do
      guard = Production::RequestGuard.new("top-secret")
      guard.authentication_required?.should be_true
      guard.authenticate("Bearer top-secret").should be_true
      guard.authenticate("Bearer wrong").should be_false
      guard.authenticate(nil).should be_false
    end

    it "allows unauthenticated local requests and enforces limits" do
      guard = Production::RequestGuard.new(nil, max_body_bytes: 64_i64, capacity: 1.0, refill: 0.0001)
      guard.authenticate(nil).should be_true
      guard.body_too_large?("65").should be_true
      guard.body_too_large?("64").should be_false
      guard.body_too_large?(nil, "gzip, chunked").should be_true
      guard.allow?("client").should be_true
      guard.allow?("client").should be_false
    end
  end

  describe Production do
    it "requires stable secrets in production" do
      previous_env = ENV["CRYSTALCOG_ENV"]?
      previous_secret = ENV["CRYSTALCOG_TEST_SECRET"]?
      begin
        ENV["CRYSTALCOG_ENV"] = "production"
        ENV.delete("CRYSTALCOG_TEST_SECRET")
        expect_raises(Production::ProductionException, /CRYSTALCOG_TEST_SECRET/) do
          Production.secret_from_env("CRYSTALCOG_TEST_SECRET")
        end
      ensure
        if previous_env
          ENV["CRYSTALCOG_ENV"] = previous_env
        else
          ENV.delete("CRYSTALCOG_ENV")
        end
        if previous_secret
          ENV["CRYSTALCOG_TEST_SECRET"] = previous_secret
        else
          ENV.delete("CRYSTALCOG_TEST_SECRET")
        end
      end
    end
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
