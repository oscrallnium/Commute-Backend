module SocialAuth
  # Checks the RS256 signature, iss, aud, and exp of a token against a cached JWKS.
  # The verifier reloads the key set once when the token's kid is not in the cache.
  class JwksTokenVerifier
    CACHE_TTL = 6.hours
    ALGORITHMS = ["RS256"].freeze

    def initialize(jwks_url:, issuers:, audience:, cache: Rails.cache, transport: AppStoreConnect::HttpTransport.new)
      @jwks_url = jwks_url
      @issuers = issuers
      @audience = audience
      @cache = cache
      @transport = transport
    end

    def verify(token)
      raise InvalidTokenError, "Token is blank" if token.blank?
      raise InvalidTokenError, "Audience is not configured" if @audience.blank?

      key = find_key(token_kid(token))
      decode(token, key)
    rescue JWT::DecodeError => e
      raise InvalidTokenError, "Token check failed: #{e.class}"
    end

    private

    def token_kid(token)
      _payload, header = JWT.decode(token, nil, false)
      header["kid"].presence || raise(InvalidTokenError, "Token has no kid")
    end

    def find_key(kid)
      key_in(cached_key_set, kid) || key_in(reload_key_set, kid) || raise(InvalidTokenError, "Unknown kid")
    end

    def key_in(key_set, kid)
      JWT::JWK::Set.new(key_set).find { |jwk| jwk[:kid] == kid }&.verify_key
    end

    def decode(token, key)
      claims, = JWT.decode(token, key, true, algorithms: ALGORITHMS, iss: @issuers, verify_iss: true,
                                             aud: @audience, verify_aud: true)
      claims
    end

    def cached_key_set
      @cache.read(cache_key) || reload_key_set
    end

    def reload_key_set
      key_set = fetch_key_set
      @cache.write(cache_key, key_set, expires_in: CACHE_TTL)
      key_set
    end

    def fetch_key_set
      response = @transport.call(:get, @jwks_url, headers: { "Accept" => "application/json" }, body: nil)
      raise InvalidTokenError, "Key set fetch returned HTTP #{response.status}" unless response.status == 200

      key_set = JSON.parse(response.body)
      raise InvalidTokenError, "Key set is malformed" unless key_set.is_a?(Hash) && key_set["keys"].is_a?(Array)

      key_set
    rescue AppStoreConnect::Client::TransientError, JSON::ParserError => e
      raise InvalidTokenError, "Key set fetch failed: #{e.class}"
    end

    def cache_key
      "social_auth/jwks/#{@jwks_url}"
    end
  end
end
