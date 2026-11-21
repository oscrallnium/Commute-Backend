module AppStoreConnect
  # Calls the App Store Connect API for TestFlight testers. Reads its settings from the ASC_*
  # environment variables. A missing setting raises ConfigurationError at call time, not at boot.
  class Client
    # Apple refused the request. A retry gets the same answer.
    class Error < StandardError; end
    class ConfigurationError < Error; end
    # A network failure or an HTTP 5xx. A retry can succeed.
    class TransientError < StandardError; end

    BASE_URL = "https://api.appstoreconnect.apple.com".freeze
    AUDIENCE = "appstoreconnect-v1".freeze
    ENV_KEYS = %w[ASC_ISSUER_ID ASC_KEY_ID ASC_PRIVATE_KEY ASC_APP_ID ASC_BETA_GROUP_ID].freeze
    TOKEN_LIFETIME = 19.minutes
    TOKEN_REUSE_LIMIT = 14.minutes

    @token_cache = {}
    @token_mutex = Mutex.new
    class << self
      attr_reader :token_cache, :token_mutex
    end

    def initialize(env: ENV, transport: HttpTransport.new, clock: -> { Time.current })
      @env = env
      @transport = transport
      @clock = clock
    end

    # Adds the email to the beta group and returns the beta tester ID. Apple answers 409 when
    # the tester exists; then the client finds the tester and adds it to the group.
    def invite_tester(email:, first_name: nil, last_name: nil)
      response = request(:post, "/v1/betaTesters", body: new_tester_body(email, first_name, last_name))
      return parse(response).dig("data", "id") if response.status == 201

      raise_error(response) unless response.status == 409

      tester_id = find_tester_id(email) || raise_error(response)
      add_tester_to_group(tester_id)
      tester_id
    end

    def resend_invitation(tester_id:)
      body = { data: { type: "betaTesterInvitations", relationships: {
        app: { data: { type: "apps", id: setting("ASC_APP_ID") } },
        betaTester: { data: { type: "betaTesters", id: tester_id } }
      } } }
      response = request(:post, "/v1/betaTesterInvitations", body: body)
      raise_error(response) unless response.status == 201
    end

    private

    def new_tester_body(email, first_name, last_name)
      attributes = { email: email, firstName: first_name, lastName: last_name }.compact
      { data: { type: "betaTesters", attributes: attributes, relationships: {
        betaGroups: { data: [{ type: "betaGroups", id: setting("ASC_BETA_GROUP_ID") }] }
      } } }
    end

    def find_tester_id(email)
      query = URI.encode_www_form("filter[email]" => email, "limit" => 1)
      response = request(:get, "/v1/betaTesters?#{query}")
      raise_error(response) unless response.status == 200

      parse(response).fetch("data", []).first&.dig("id")
    end

    def add_tester_to_group(tester_id)
      path = "/v1/betaGroups/#{setting("ASC_BETA_GROUP_ID")}/relationships/betaTesters"
      response = request(:post, path, body: { data: [{ type: "betaTesters", id: tester_id }] })
      raise_error(response) unless response.status == 204
    end

    def request(method, path, body: nil)
      check_settings!
      headers = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
      response = @transport.call(method, "#{BASE_URL}#{path}", headers: headers, body: body&.to_json)
      raise TransientError, "App Store Connect returned HTTP #{response.status}" if response.status >= 500

      response
    end

    def raise_error(response)
      details = parse(response).fetch("errors", []).filter_map { |e| e["detail"].presence || e["title"].presence }
      message = details.any? ? details.join("; ") : "App Store Connect returned HTTP #{response.status}"
      raise Error, message
    end

    def parse(response)
      response.body.present? ? JSON.parse(response.body) : {}
    rescue JSON::ParserError
      {}
    end

    def check_settings!
      missing = ENV_KEYS.select { |key| @env[key].blank? }
      return if missing.empty?

      raise ConfigurationError, "App Store Connect is not configured. Missing: #{missing.join(", ")}"
    end

    def setting(key)
      @env[key].to_s.strip
    end

    # Reuses one token per key ID until TOKEN_REUSE_LIMIT, so every token sent has at least
    # 5 minutes left. Apple refuses a token whose expiry is more than 20 minutes after issue.
    def token
      now = @clock.call
      self.class.token_mutex.synchronize do
        cached = self.class.token_cache[setting("ASC_KEY_ID")]
        return cached[:token] if cached && now < cached[:reuse_until]

        signed = sign_token(now)
        self.class.token_cache[setting("ASC_KEY_ID")] = { token: signed, reuse_until: now + TOKEN_REUSE_LIMIT }
        signed
      end
    end

    def sign_token(now)
      payload = { iss: setting("ASC_ISSUER_ID"), iat: now.to_i, exp: (now + TOKEN_LIFETIME).to_i, aud: AUDIENCE }
      JWT.encode(payload, private_key, "ES256", { kid: setting("ASC_KEY_ID"), typ: "JWT" })
    end

    def private_key
      OpenSSL::PKey::EC.new(@env["ASC_PRIVATE_KEY"].to_s.gsub("\\n", "\n"))
    rescue OpenSSL::PKey::PKeyError
      raise ConfigurationError, "ASC_PRIVATE_KEY is not a valid EC private key in PEM format"
    end
  end
end
