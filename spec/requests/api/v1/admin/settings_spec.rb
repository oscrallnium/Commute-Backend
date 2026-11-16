require "rails_helper"

RSpec.describe "/api/v1/admin/settings", type: :request do
  let(:admin) do
    User.create!(email: "admin_#{SecureRandom.hex(4)}@test.com", password: "Password1!",
                 display_name: "Admin", role: :admin)
  end
  let(:rider) do
    User.create!(email: "rider_#{SecureRandom.hex(4)}@test.com", password: "Password1!", display_name: "Rider")
  end

  before do
    meta = GraphMeta.first || GraphMeta.create!
    meta.update!(enforce_operating_hours: true, scheduled_max_wait_minutes: 60)
  end

  def patch_settings(body, user: admin)
    headers = user ? auth_headers_for(user) : {}
    patch "/api/v1/admin/settings", params: body.to_json, headers: headers.merge("Content-Type" => "application/json")
  end

  def version = GraphMeta.first.version

  it "returns both settings" do
    get "/api/v1/admin/settings", headers: auth_headers_for(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"]).to eq("enforce_operating_hours" => true, "scheduled_max_wait_minutes" => 60)
  end

  it "updates the maximum wait and raises the version" do
    before_version = version
    patch_settings({ scheduled_max_wait_minutes: 90 })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"]["scheduled_max_wait_minutes"]).to eq(90)
    expect(GraphMeta.first.scheduled_max_wait_minutes).to eq(90)
    expect(version).to eq(before_version + 1)
  end

  it "accepts an integer string" do
    patch_settings({ scheduled_max_wait_minutes: "120" })

    expect(GraphMeta.first.scheduled_max_wait_minutes).to eq(120)
  end

  it "updates enforce_operating_hours and raises the version" do
    before_version = version
    patch_settings({ enforce_operating_hours: false })

    expect(response).to have_http_status(:ok)
    expect(GraphMeta.first.enforce_operating_hours).to be(false)
    expect(version).to eq(before_version + 1)
  end

  it "accepts both keys in one request and raises the version once" do
    before_version = version
    patch_settings({ enforce_operating_hours: false, scheduled_max_wait_minutes: 30 })

    expect(GraphMeta.first).to have_attributes(enforce_operating_hours: false, scheduled_max_wait_minutes: 30)
    expect(version).to eq(before_version + 1)
  end

  [0, 601, "abc", 1.5, nil].each do |bad|
    it "rejects #{bad.inspect} with 422 and saves nothing" do
      before_version = version
      patch_settings({ enforce_operating_hours: false, scheduled_max_wait_minutes: bad })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Validation failed")
      expect(response.parsed_body["errors"].first).to include("field" => "scheduled_max_wait_minutes")
      expect(GraphMeta.first).to have_attributes(enforce_operating_hours: true, scheduled_max_wait_minutes: 60)
      expect(version).to eq(before_version)
    end
  end

  it "does not raise the version when nothing changes" do
    before_version = version
    patch_settings({ enforce_operating_hours: true, scheduled_max_wait_minutes: 60 })

    expect(response).to have_http_status(:ok)
    expect(version).to eq(before_version)
  end

  it "returns 403 for a non-admin" do
    patch_settings({ scheduled_max_wait_minutes: 90 }, user: rider)

    expect(response).to have_http_status(:forbidden)
    expect(GraphMeta.first.scheduled_max_wait_minutes).to eq(60)
  end

  it "returns 401 without a token" do
    patch_settings({ scheduled_max_wait_minutes: 90 }, user: nil)

    expect(response).to have_http_status(:unauthorized)
  end
end
