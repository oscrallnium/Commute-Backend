require "rails_helper"

# Audit §3.4 — POST /api/v1/analytics/route_plan wrote null origin/destination/modes_used
# because iOS sends { event: { origin_station_id, destination_station_id, line_ids,
# duration_seconds } } but the controller read top-level params[:origin_id] etc.
# Verifies the fix: a correctly-shaped iOS payload produces a RoutePlanEvent with
# non-null fields.
RSpec.describe "POST /api/v1/analytics/route_plan", type: :request do
  let(:user) do
    User.create!(
      email: "user_#{SecureRandom.hex(4)}@test.com",
      password: "Password1!",
      display_name: "Tester"
    )
  end

  let(:ios_payload) do
    {
      event: {
        origin_station_id: "MRT_NORTH_AVE",
        destination_station_id: "MRT_SHAW",
        line_ids: ["MRT-3"],
        duration_seconds: 720
      }
    }
  end

  def post_analytics(body)
    post "/api/v1/analytics/route_plan",
         params: body.to_json,
         headers: auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  it "returns 201 for a correctly-shaped iOS payload" do
    post_analytics(ios_payload)
    expect(response).to have_http_status(:created)
  end

  it "persists origin_station_id from the nested event key" do
    expect { post_analytics(ios_payload) }.to change(RoutePlanEvent, :count).by(1)
    event = RoutePlanEvent.last
    expect(event.origin_station_id).to eq("MRT_NORTH_AVE")
  end

  it "persists destination_station_id from the nested event key" do
    post_analytics(ios_payload)
    expect(RoutePlanEvent.last.destination_station_id).to eq("MRT_SHAW")
  end

  it "maps line_ids to modes_used" do
    post_analytics(ios_payload)
    expect(RoutePlanEvent.last.modes_used).to eq(["MRT-3"])
  end

  it "converts duration_seconds to total_time_minutes" do
    post_analytics(ios_payload)
    # 720 seconds → 12 minutes
    expect(RoutePlanEvent.last.total_time_minutes).to eq(12)
  end

  it "does not write null origin when iOS payload is used (old failing case)" do
    post_analytics(ios_payload)
    expect(RoutePlanEvent.last.origin_station_id).not_to be_nil
  end

  it "still returns 201 even if the payload is malformed (analytics never block)" do
    post_analytics({ garbage: "data" })
    expect(response).to have_http_status(:created)
  end

  it "returns 401 with no token" do
    post "/api/v1/analytics/route_plan",
         params: ios_payload.to_json,
         headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end
end
