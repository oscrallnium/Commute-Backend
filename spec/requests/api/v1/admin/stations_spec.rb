require "rails_helper"

# Audit §3.2 bug 1 — PATCH /api/v1/admin/stations/:id silently no-oped because
# station_params only permitted :lat/:lng, but iOS sends latitude/longitude.
# Verifies the fix: both naming conventions are accepted and the station is updated.
RSpec.describe "PATCH /api/v1/admin/stations/:id", type: :request do
  let(:admin) do
    User.create!(
      email: "admin_#{SecureRandom.hex(4)}@test.com",
      password: "Password1!",
      display_name: "Admin",
      role: :admin
    )
  end

  let!(:station) do
    Station.create!(
      station_id: "MRT_TEST_STN", name: "Test Station", short_name: "TST",
      line: "MRT-3", type: "station",
      lat: 14.0000, lng: 121.0000,
      open_time: "05:00", close_time: "23:00"
    )
  end

  def patch_station(body)
    patch "/api/v1/admin/stations/MRT_TEST_STN",
          params: body.to_json,
          headers: auth_headers_for(admin).merge("Content-Type" => "application/json")
  end

  context "when iOS sends latitude/longitude (old failing case)" do
    it "returns 200" do
      patch_station(station: { latitude: 14.5555, longitude: 121.5555 })
      expect(response).to have_http_status(:ok)
    end

    it "persists the new coordinates to the database" do
      patch_station(station: { latitude: 14.5555, longitude: 121.5555 })
      station.reload
      expect(station.lat.to_f.round(4)).to eq(14.5555)
      expect(station.lng.to_f.round(4)).to eq(121.5555)
    end

    it "does not silently no-op (coordinates must change)" do
      patch_station(station: { latitude: 14.9999, longitude: 121.9999 })
      station.reload
      expect(station.lat.to_f).not_to eq(14.0000)
    end
  end

  context "when client sends lat/lng (existing convention)" do
    it "returns 200" do
      patch_station(station: { lat: 14.1111, lng: 121.1111 })
      expect(response).to have_http_status(:ok)
    end

    it "persists the new coordinates" do
      patch_station(station: { lat: 14.1111, lng: 121.1111 })
      station.reload
      expect(station.lat.to_f.round(4)).to eq(14.1111)
      expect(station.lng.to_f.round(4)).to eq(121.1111)
    end
  end

  context "authorization" do
    it "returns 401 with no token" do
      patch "/api/v1/admin/stations/MRT_TEST_STN",
            params: { station: { latitude: 14.5, longitude: 121.5 } }.to_json,
            headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for a non-admin user" do
      commuter = User.create!(
        email: "commuter_#{SecureRandom.hex(4)}@test.com",
        password: "Password1!",
        display_name: "Commuter"
      )
      patch "/api/v1/admin/stations/MRT_TEST_STN",
            params: { station: { latitude: 14.5, longitude: 121.5 } }.to_json,
            headers: auth_headers_for(commuter).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:forbidden)
    end
  end
end
