module SocialAuth
  # Builds the ES256 JWT that Apple accepts as the client secret. The secret lives 5 minutes.
  class AppleClientSecret
    AUDIENCE = "https://appleid.apple.com".freeze
    LIFETIME = 5.minutes
    ENV_KEYS = %w[APPLE_TEAM_ID APPLE_KEY_ID APPLE_BUNDLE_ID APPLE_PRIVATE_KEY].freeze

    def initialize(env: ENV, clock: -> { Time.current })
      @env = env
      @clock = clock
    end

    def to_s
      check_settings!
      now = @clock.call
      claims = { iss: setting("APPLE_TEAM_ID"), iat: now.to_i, exp: (now + LIFETIME).to_i,
                 aud: AUDIENCE, sub: setting("APPLE_BUNDLE_ID") }
      JWT.encode(claims, private_key, "ES256", { kid: setting("APPLE_KEY_ID") })
    end

    private

    def check_settings!
      missing = ENV_KEYS.select { |key| @env[key].blank? }
      return if missing.empty?

      raise AppleTokenClient::ConfigurationError, "Sign in with Apple is not configured. Missing: #{missing.join(", ")}"
    end

    def setting(key)
      @env[key].to_s.strip
    end

    def private_key
      OpenSSL::PKey::EC.new(@env["APPLE_PRIVATE_KEY"].to_s.gsub("\\n", "\n"))
    rescue OpenSSL::PKey::PKeyError
      raise AppleTokenClient::ConfigurationError, "APPLE_PRIVATE_KEY is not a valid EC private key in PEM format"
    end
  end
end
