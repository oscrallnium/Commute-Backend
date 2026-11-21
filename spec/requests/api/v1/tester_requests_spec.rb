require "rails_helper"

RSpec.describe "POST /api/v1/tester_requests", type: :request do
  let(:form_key) { "test-form-key" }
  let(:body) do
    { name: "Juan Dela Cruz", age: 21, location: "Quezon City", email: "juan@example.com",
      consent_at: "2026-11-22T08:00:00Z", source: "website" }
  end

  around do |example|
    previous = ENV.fetch("TESTER_FORM_KEY", nil)
    ENV["TESTER_FORM_KEY"] = form_key
    example.run
  ensure
    ENV["TESTER_FORM_KEY"] = previous
  end

  def post_form(payload, key: form_key, ip: "203.0.113.7")
    headers = { "Content-Type" => "application/json", "X-Forwarded-For" => ip }
    headers["X-Gora-Form-Key"] = key if key
    post "/api/v1/tester_requests", params: payload.to_json, headers: headers
  end

  it "saves a pending request and answers 202" do
    expect { post_form(body) }.to change(TesterRequest, :count).by(1)
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to eq("status" => "received")
    expect(TesterRequest.last).to have_attributes(status: "pending", age: 21, source: "website")
  end

  it "accepts consentAt in camelCase and no name" do
    post_form(body.except(:consent_at, :name).merge(consentAt: "2026-11-22T08:00:00Z"))
    expect(response).to have_http_status(:accepted)
    expect(TesterRequest.last.name).to be_nil
  end

  it "refuses a missing key with 401" do
    post_form(body, key: nil)
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses a wrong key with 401" do
    post_form(body, key: "wrong")
    expect(response).to have_http_status(:unauthorized)
    expect(TesterRequest.count).to eq(0)
  end

  it "refuses every request when TESTER_FORM_KEY is not set" do
    ENV["TESTER_FORM_KEY"] = nil
    post_form(body, key: "")
    expect(response).to have_http_status(:unauthorized)
  end

  it "answers 422 with field errors in camelCase" do
    post_form(body.merge(age: 15, email: "bad", consent_at: nil, location: "x" * 81))
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"].keys).to include("age", "email", "consentAt", "location")
  end

  it "answers 202 for a known email, makes no duplicate, and broadcasts updated" do
    post_form(body)
    expect { post_form(body.merge(email: "JUAN@example.com")) }
      .to have_broadcasted_to("tester_requests").with(hash_including("event" => "updated"))
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to eq("status" => "received")
    expect(TesterRequest.count).to eq(1)
  end

  it "broadcasts created for a new email" do
    expect { post_form(body) }
      .to have_broadcasted_to("tester_requests").with(hash_including("event" => "created"))
  end

  it "allows 5 requests per hour from one client IP and answers 429 after that" do
    5.times { |i| post_form(body.merge(email: "user#{i}@example.com")) }
    expect(response).to have_http_status(:accepted)
    post_form(body.merge(email: "user6@example.com"))
    expect(response).to have_http_status(:too_many_requests)
  end

  it "counts each client IP in X-Forwarded-For apart" do
    5.times { |i| post_form(body.merge(email: "user#{i}@example.com"), ip: "203.0.113.7, 10.0.0.1") }
    post_form(body.merge(email: "other@example.com"), ip: "198.51.100.9, 10.0.0.1")
    expect(response).to have_http_status(:accepted)
  end

  it "filters every form field and the cable token from the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(body.merge(consentAt: "x", token: "jwt", tester_request: body).deep_stringify_keys)
    leaked = filtered.except("source", "tester_request").values.reject { |v| v == "[FILTERED]" }
    expect(leaked).to be_empty
    expect(filtered["tester_request"].except("source").values).to all(eq("[FILTERED]"))
  end
end
