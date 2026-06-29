class Rack::Attack
  # Cache store — uses Redis if available, otherwise memory
  Rack::Attack.cache.store = if ENV["REDIS_URL"].present? && defined?(Redis)
    ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])
  else
    ActiveSupport::Cache::MemoryStore.new
  end

  # ── Throttles ──────────────────────────────────────────────────────────────

  # Auth endpoints — 10 attempts per 20 seconds per IP
  throttle("auth/ip", limit: 10, period: 20) do |req|
    req.ip if req.path.start_with?("/auth/")
  end

  # Auth by email — 5 attempts per 5 minutes per email
  throttle("auth/email", limit: 5, period: 5.minutes) do |req|
    if req.path == "/auth/sign_in" && req.post?
      req.params["user"]&.dig("email").to_s.downcase.presence
    end
  end

  # API — 60 requests per minute per IP
  throttle("api/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # Analytics write — 30 per minute per user (prevent accidental storms)
  throttle("analytics/user", limit: 30, period: 1.minute) do |req|
    if req.path == "/api/v1/analytics/route_plan" && req.post?
      req.env["HTTP_AUTHORIZATION"].to_s.split(" ").last.presence
    end
  end

  # ── Response ───────────────────────────────────────────────────────────────
  self.throttled_responder = lambda do |req|
    [
      429,
      { "Content-Type" => "application/json" },
      [{ error: "Too many requests. Please try again later." }.to_json]
    ]
  end
end
