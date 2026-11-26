# Production hardening utilities for CrystalCog
#
# Rate limiting, simple token auth hooks, Prometheus-style metrics,
# and health check aggregation.

require "json"
require "../cogutil/cogutil"

module Production
  VERSION = "0.1.0"

  class ProductionException < Exception
  end

  # Token-bucket rate limiter
  class RateLimiter
    getter capacity : Float64
    getter refill_per_second : Float64
    @tokens : Float64
    @last_refill : Time

    def initialize(@capacity : Float64 = 100.0, @refill_per_second : Float64 = 10.0)
      raise ProductionException.new("capacity must be > 0") if @capacity <= 0
      raise ProductionException.new("refill must be > 0") if @refill_per_second <= 0
      @tokens = @capacity
      @last_refill = Time.utc
    end

    def allow?(cost : Float64 = 1.0) : Bool
      refill
      return false if @tokens < cost
      @tokens -= cost
      true
    end

    def remaining : Float64
      refill
      @tokens
    end

    private def refill
      now = Time.utc
      elapsed = (now - @last_refill).total_seconds
      @tokens = Math.min(@capacity, @tokens + elapsed * @refill_per_second)
      @last_refill = now
    end
  end

  # Per-key rate limiting (e.g. by API client id)
  class KeyedRateLimiter
    @limiters : Hash(String, RateLimiter)
    @capacity : Float64
    @refill : Float64

    def initialize(@capacity : Float64 = 100.0, @refill : Float64 = 10.0,
                   @max_keys : Int32 = 4096)
      @limiters = {} of String => RateLimiter
    end

    def allow?(key : String, cost : Float64 = 1.0) : Bool
      lim = @limiters[key]?
      unless lim
        if @limiters.size >= @max_keys
          @limiters.delete(@limiters.first_key)
        end
        lim = @limiters[key] = RateLimiter.new(@capacity, @refill)
      end
      lim.allow?(cost)
    end
  end

  # Simple bearer-token authentication registry
  class Authenticator
    @tokens : Hash(String, String) # token -> principal
    @revoked : Set(String)

    def initialize
      @tokens = {} of String => String
      @revoked = Set(String).new
    end

    def issue(principal : String) : String
      token = Random::Secure.hex(16)
      @tokens[token] = principal
      token
    end

    def revoke(token : String)
      @revoked << token
      @tokens.delete(token)
    end

    def authenticate(token : String) : String?
      return nil if @revoked.includes?(token)
      @tokens[token]?
    end

    def authorized?(token : String, required_principal : String? = nil) : Bool
      principal = authenticate(token)
      return false unless principal
      required_principal.nil? || principal == required_principal
    end
  end

  # Reusable HTTP request policy for CrystalCog servers. Authentication is
  # disabled only when no token is configured; network-facing entry points can
  # require callers to supply one while local development stays ergonomic.
  class RequestGuard
    getter max_body_bytes : Int64

    def initialize(@auth_token : String? = nil, @max_body_bytes : Int64 = 1_048_576_i64,
                   @capacity : Float64 = 120.0, @refill : Float64 = 30.0)
      raise ProductionException.new("max_body_bytes must be > 0") if @max_body_bytes <= 0
      @limiter = KeyedRateLimiter.new(@capacity, @refill)
    end

    def authentication_required? : Bool
      !@auth_token.nil?
    end

    def authenticate(header_or_token : String?) : Bool
      return true unless expected = @auth_token
      provided = self.class.token_from(header_or_token)
      !provided.nil? && provided == expected
    end

    def allow?(key : String) : Bool
      @limiter.allow?(key)
    end

    def body_too_large?(content_length : String?, transfer_encoding : String? = nil) : Bool
      return true if transfer_encoding.try(&.downcase.split(',').any? { |v| v.strip == "chunked" })
      return false unless content_length
      length = content_length.to_i64?
      !length.nil? && length > @max_body_bytes
    end

    def self.token_from(value : String?) : String?
      return if value.nil?
      if match = value.match(/\A\s*Bearer\s+(.+?)\s*\z/i)
        match[1]
      else
        value.strip.presence
      end
    end
  end

  def self.production_environment? : Bool
    %w(production prod).includes?((ENV["CRYSTALCOG_ENV"]? || ENV["APP_ENV"]? || "").downcase)
  end

  def self.secret_from_env(name : String, min_bytes : Int32 = 32) : String
    configured = ENV[name]?.try(&.strip)
    if configured && configured.bytesize >= min_bytes
      configured
    elsif configured && !configured.empty?
      raise ProductionException.new("#{name} must contain at least #{min_bytes} bytes")
    elsif production_environment?
      raise ProductionException.new("#{name} is required in production")
    else
      Random::Secure.hex(min_bytes)
    end
  end

  # In-process metrics registry (Prometheus text exposition subset)
  class MetricsRegistry
    @counters : Hash(String, Float64)
    @gauges : Hash(String, Float64)
    @histograms : Hash(String, Array(Float64))

    def initialize
      @counters = Hash(String, Float64).new(0.0)
      @gauges = {} of String => Float64
      @histograms = Hash(String, Array(Float64)).new { |h, k| h[k] = [] of Float64 }
    end

    def inc(name : String, by : Float64 = 1.0)
      @counters[name] = @counters[name] + by
    end

    def gauge(name : String, value : Float64)
      @gauges[name] = value
    end

    def observe(name : String, value : Float64)
      @histograms[name] << value
    end

    def counter(name : String) : Float64
      @counters[name]
    end

    def export_prometheus : String
      lines = [] of String
      @counters.each do |name, val|
        lines << "# TYPE #{sanitize(name)} counter"
        lines << "#{sanitize(name)} #{val}"
      end
      @gauges.each do |name, val|
        lines << "# TYPE #{sanitize(name)} gauge"
        lines << "#{sanitize(name)} #{val}"
      end
      @histograms.each do |name, vals|
        next if vals.empty?
        sum = vals.sum
        count = vals.size
        lines << "# TYPE #{sanitize(name)} summary"
        lines << "#{sanitize(name)}_count #{count}"
        lines << "#{sanitize(name)}_sum #{sum}"
      end
      lines.join("\n") + "\n"
    end

    def snapshot : Hash(String, JSON::Any)
      {
        "counters" => JSON::Any.new(@counters.transform_values { |v| JSON::Any.new(v) }),
        "gauges"   => JSON::Any.new(@gauges.transform_values { |v| JSON::Any.new(v) }),
      } of String => JSON::Any
    end

    private def sanitize(name : String) : String
      name.gsub(/[^a-zA-Z0-9_:]/, "_")
    end
  end

  # Aggregate health checks
  class HealthChecker
    alias Check = -> Tuple(Bool, String)

    @checks : Hash(String, Check)

    def initialize
      @checks = {} of String => Check
    end

    def register(name : String, &block : Check)
      @checks[name] = block
    end

    def run : Hash(String, JSON::Any)
      results = {} of String => JSON::Any
      overall = true
      @checks.each do |name, check|
        ok, message = check.call
        overall = overall && ok
        results[name] = JSON::Any.new({
          "ok"      => JSON::Any.new(ok),
          "message" => JSON::Any.new(message),
        } of String => JSON::Any)
      end
      {
        "status"  => JSON::Any.new(overall ? "healthy" : "unhealthy"),
        "checks"  => JSON::Any.new(results),
        "version" => JSON::Any.new(Production::VERSION),
      } of String => JSON::Any
    end

    def healthy? : Bool
      run["status"].as_s == "healthy"
    end
  end

  # Structured request logger helper
  class RequestLogger
    def self.log(method : String, path : String, status : Int32, duration_ms : Float64,
                 principal : String? = nil)
      CogUtil::Logger.info(
        "HTTP",
        "#{method} #{path} status=#{status} duration_ms=#{duration_ms.round(2)} principal=#{principal || "-"}"
      )
    end
  end

  def self.initialize
    CogUtil::Logger.info("Initializing Production hardening subsystem...")
    CogUtil::Logger.info("Production hardening subsystem initialized successfully")
  end
end
