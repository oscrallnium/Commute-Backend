# Replaces the HTTP transport of AppStoreConnect::Client. Answers come from a queue, and
# every call is recorded. No spec reaches Apple.
class FakeAppStoreConnectTransport
  Call = Struct.new(:http_method, :url, :headers, :body)

  attr_reader :calls

  def initialize(*responses)
    @responses = responses
    @calls = []
  end

  def call(method, url, headers:, body: nil)
    @calls << Call.new(method, url, headers, body && JSON.parse(body))
    answer = @responses.shift || raise("No fake response left for #{method} #{url}")
    raise answer if answer.is_a?(Exception)

    AppStoreConnect::HttpTransport::Response.new(answer[0], answer[1].to_json)
  end
end

module AppStoreConnectEnv
  SIGNING_KEY = OpenSSL::PKey::EC.generate("prime256v1")

  def asc_env(**overrides)
    { "ASC_ISSUER_ID" => "issuer-1", "ASC_KEY_ID" => "KEY123", "ASC_APP_ID" => "app-1",
      "ASC_BETA_GROUP_ID" => "group-1", "ASC_PRIVATE_KEY" => SIGNING_KEY.to_pem.gsub("\n", "\\n") }
      .merge(overrides)
  end
end

RSpec.configure do |config|
  config.include AppStoreConnectEnv
  config.before { AppStoreConnect::Client.token_cache.clear }
end
