require "rails_helper"

RSpec.describe AppStoreConnect::Client do
  let(:now) { Time.utc(2026, 11, 22, 8, 0, 0) }

  def client_with(*responses, env: asc_env)
    transport = FakeAppStoreConnectTransport.new(*responses)
    [described_class.new(env: env, transport: transport, clock: -> { now }), transport]
  end

  def apple_error(status, detail)
    [status, { errors: [{ status: status.to_s, code: "ERR", title: "Title", detail: detail }] }]
  end

  describe "#invite_tester" do
    it "creates the tester in the beta group and returns its id" do
      client, transport = client_with([201, { data: { id: "T1", type: "betaTesters" } }])
      expect(client.invite_tester(email: "a@example.com", first_name: "Juan", last_name: "Dela Cruz")).to eq("T1")
      call = transport.calls.first
      expect(call.url).to eq("https://api.appstoreconnect.apple.com/v1/betaTesters")
      expect(call.body.dig("data", "attributes"))
        .to eq("email" => "a@example.com", "firstName" => "Juan", "lastName" => "Dela Cruz")
      expect(call.body.dig("data", "relationships", "betaGroups", "data"))
        .to eq([{ "type" => "betaGroups", "id" => "group-1" }])
    end

    it "leaves out the name fields when the request has no name" do
      client, transport = client_with([201, { data: { id: "T1" } }])
      client.invite_tester(email: "a@example.com")
      expect(transport.calls.first.body.dig("data", "attributes")).to eq("email" => "a@example.com")
    end

    it "finds an existing tester and adds it to the group when Apple answers 409" do
      client, transport = client_with(apple_error(409, "Tester already exists"),
                                      [200, { data: [{ id: "T9", type: "betaTesters" }] }],
                                      [204, nil])
      expect(client.invite_tester(email: "a+b@example.com")).to eq("T9")
      expect(transport.calls[1].url).to include("filter%5Bemail%5D=a%2Bb%40example.com")
      expect(transport.calls[2].url).to end_with("/v1/betaGroups/group-1/relationships/betaTesters")
      expect(transport.calls[2].body).to eq("data" => [{ "type" => "betaTesters", "id" => "T9" }])
    end

    it "raises Apple's detail when the 409 tester is not found" do
      client, = client_with(apple_error(409, "Conflict detail"), [200, { data: [] }])
      expect { client.invite_tester(email: "a@example.com") }
        .to raise_error(AppStoreConnect::Client::Error, "Conflict detail")
    end

    it "raises Apple's detail for a 4xx answer" do
      client, = client_with(apple_error(422, "The email is not valid"))
      expect { client.invite_tester(email: "a@example.com") }
        .to raise_error(AppStoreConnect::Client::Error, "The email is not valid")
    end

    it "raises a transient error for a 5xx answer" do
      client, = client_with([503, {}])
      expect { client.invite_tester(email: "a@example.com") }.to raise_error(AppStoreConnect::Client::TransientError)
    end
  end

  describe "#resend_invitation" do
    it "posts the app and the tester" do
      client, transport = client_with([201, { data: { id: "I1" } }])
      client.resend_invitation(tester_id: "T1")
      expect(transport.calls.first.url).to end_with("/v1/betaTesterInvitations")
      expect(transport.calls.first.body.dig("data", "relationships")).to eq(
        "app" => { "data" => { "type" => "apps", "id" => "app-1" } },
        "betaTester" => { "data" => { "type" => "betaTesters", "id" => "T1" } }
      )
    end
  end

  describe "token" do
    def sent_token(transport)
      transport.calls.first.headers["Authorization"].delete_prefix("Bearer ")
    end

    it "signs an ES256 token with the key id, the issuer, the audience, and an expiry under 20 minutes" do
      client, transport = client_with([201, { data: { id: "T1" } }])
      client.invite_tester(email: "a@example.com")
      payload, header = JWT.decode(sent_token(transport), AppStoreConnectEnv::SIGNING_KEY, true,
                                   algorithm: "ES256", verify_expiration: false)
      expect(header).to include("alg" => "ES256", "kid" => "KEY123")
      expect(payload).to include("iss" => "issuer-1", "aud" => "appstoreconnect-v1")
      expect(payload["exp"] - payload["iat"]).to be <= 20 * 60
    end

    it "reuses the cached token for the next call" do
      transport = FakeAppStoreConnectTransport.new([201, { data: { id: "T1" } }], [201, { data: { id: "T2" } }])
      2.times do |i|
        described_class.new(env: asc_env, transport: transport, clock: -> { now + i.minutes })
                       .invite_tester(email: "a@example.com")
      end
      expect(transport.calls.map { |c| c.headers["Authorization"] }.uniq.size).to eq(1)
    end
  end

  describe "settings" do
    it "raises a configuration error that names the missing keys" do
      client, transport = client_with(env: asc_env("ASC_KEY_ID" => nil, "ASC_BETA_GROUP_ID" => ""))
      expect { client.invite_tester(email: "a@example.com") }
        .to raise_error(AppStoreConnect::Client::ConfigurationError, /ASC_KEY_ID, ASC_BETA_GROUP_ID/)
      expect(transport.calls).to be_empty
    end

    it "raises a configuration error for a key that is not a PEM EC key" do
      client, = client_with(env: asc_env("ASC_PRIVATE_KEY" => "not a key"))
      expect { client.invite_tester(email: "a@example.com") }
        .to raise_error(AppStoreConnect::Client::ConfigurationError, /ASC_PRIVATE_KEY/)
    end
  end
end
