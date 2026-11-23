module SocialAuth
  # Checks Google ID tokens against Google's public keys.
  class GoogleTokenVerifier
    JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs".freeze
    ISSUERS = ["accounts.google.com", "https://accounts.google.com"].freeze

    def initialize(env: ENV, jwks_verifier: nil)
      @jwks_verifier = jwks_verifier || JwksTokenVerifier.new(
        jwks_url: JWKS_URL, issuers: ISSUERS, audience: env["GOOGLE_IOS_CLIENT_ID"]
      )
    end

    def verify(id_token)
      claims = @jwks_verifier.verify(id_token)
      { uid: claims["sub"], email: claims["email"].presence,
        email_verified: claims["email_verified"] == true || claims["email_verified"].to_s == "true",
        name: claims["name"].presence }
    end
  end
end
