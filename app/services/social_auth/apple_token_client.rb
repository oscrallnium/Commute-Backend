module SocialAuth
  # Calls Apple's token and revoke endpoints. Every failure raises Error.
  class AppleTokenClient
    class Error < StandardError; end
    class ConfigurationError < Error; end

    TOKEN_URL = "https://appleid.apple.com/auth/token".freeze
    REVOKE_URL = "https://appleid.apple.com/auth/revoke".freeze
    FORM_HEADERS = { "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json" }.freeze

    def initialize(env: ENV, transport: AppStoreConnect::HttpTransport.new, client_secret: nil)
      @env = env
      @transport = transport
      @client_secret = client_secret || AppleClientSecret.new(env: env)
    end

    # Returns the refresh token that Apple issues for the authorization code.
    def exchange_code(code)
      response = post(TOKEN_URL, "code" => code, "grant_type" => "authorization_code")
      raise Error, "Apple token exchange returned HTTP #{response.status}" unless response.status == 200

      refresh_token = parse(response)["refresh_token"]
      refresh_token.presence || raise(Error, "Apple token response has no refresh_token")
    end

    def revoke(refresh_token) # rubocop:disable Naming/PredicateMethod
      response = post(REVOKE_URL, "token" => refresh_token, "token_type_hint" => "refresh_token")
      raise Error, "Apple revoke returned HTTP #{response.status}" unless response.status == 200

      true
    end

    private

    def post(url, params)
      form = { "client_id" => client_id, "client_secret" => @client_secret.to_s }.merge(params)
      @transport.call(:post, url, headers: FORM_HEADERS, body: URI.encode_www_form(form))
    rescue AppStoreConnect::Client::TransientError => e
      raise Error, "Apple request failed: #{e.message}"
    end

    def client_id
      @env["APPLE_BUNDLE_ID"].presence || raise(ConfigurationError, "APPLE_BUNDLE_ID is missing")
    end

    def parse(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error, "Apple token response is not valid JSON"
    end
  end
end
