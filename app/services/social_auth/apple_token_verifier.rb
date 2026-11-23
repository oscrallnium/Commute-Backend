module SocialAuth
  # Checks Apple ID tokens and server notifications against Apple's public keys.
  class AppleTokenVerifier
    JWKS_URL = "https://appleid.apple.com/auth/keys".freeze
    ISSUERS = ["https://appleid.apple.com"].freeze

    def initialize(env: ENV, jwks_verifier: nil)
      @jwks_verifier = jwks_verifier || JwksTokenVerifier.new(
        jwks_url: JWKS_URL, issuers: ISSUERS, audience: env["APPLE_BUNDLE_ID"]
      )
    end

    # The nonce claim must equal the SHA-256 hex digest of the raw nonce.
    def verify(id_token, nonce:)
      raise InvalidTokenError, "Nonce is blank" if nonce.blank?

      claims = @jwks_verifier.verify(id_token)
      check_nonce(claims, nonce)
      { uid: claims["sub"], email: claims["email"].presence, email_verified: truthy?(claims["email_verified"]) }
    end

    def verify_notification(payload)
      events = @jwks_verifier.verify(payload)["events"]
      raise InvalidTokenError, "Events claim is missing" if events.blank?

      parsed = events.is_a?(String) ? JSON.parse(events) : events
      raise InvalidTokenError, "Events claim is not an object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise InvalidTokenError, "Events claim is not valid JSON"
    end

    private

    def check_nonce(claims, nonce)
      expected = Digest::SHA256.hexdigest(nonce)
      actual = claims["nonce"].to_s
      return if actual.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(actual, expected)

      raise InvalidTokenError, "Nonce does not match"
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end
  end
end
