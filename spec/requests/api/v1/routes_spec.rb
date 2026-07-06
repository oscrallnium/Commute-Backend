require "rails_helper"

# Audit §3.1 — /api/v1/routes and /api/v1/routes/:line_id returned HTTP 500 because
# RoutesController selected open_time/close_time from edges, but those columns only
# exist on stations. Verifies the fix: endpoints return 200 and well-formed JSON.
RSpec.describe "GET /api/v1/routes", type: :request do
  before do
    Rails.cache.clear

    Station.create!(
      station_id: "MRT_NORTH_AVE", name: "North Avenue", short_name: "NA",
      line: "MRT-3", type: "station",
      lat: 14.6527, lng: 121.0325,
      open_time: "05:30", close_time: "23:00"
    )
    Station.create!(
      station_id: "MRT_QUEZON_AVE", name: "Quezon Avenue", short_name: "QA",
      line: "MRT-3", type: "station",
      lat: 14.6430, lng: 121.0325,
      open_time: "05:30", close_time: "23:00"
    )
    Edge.create!(
      edge_id: "MRT3_NA_QA", from_station: "MRT_NORTH_AVE", to_station: "MRT_QUEZON_AVE",
      mode: "train", line: "MRT-3",
      travel_time_minutes: 3, distance_km: 1.2,
      base_fare: 15, accepted_payments: ["cash", "beep_card"],
      is_air_conditioned: true, crowd_factor: 0.5, reliability: 0.95
    )
  end

  describe "GET /api/v1/routes" do
    it "returns 200 (not 500)" do
      get "/api/v1/routes"
      expect(response).to have_http_status(:ok)
    end

    it "returns a data array" do
      get "/api/v1/routes"
      json = JSON.parse(response.body)
      expect(json["data"]).to be_an(Array)
    end

    it "includes line_id in each route entry" do
      get "/api/v1/routes"
      json = JSON.parse(response.body)
      expect(json["data"].first["line_id"]).to eq("MRT-3")
    end

    it "includes stop_count derived from stations (not edges)" do
      get "/api/v1/routes"
      json = JSON.parse(response.body)
      expect(json["data"].first["stop_count"]).to eq(2)
    end

    it "does not include open_time or close_time (edge-level fields that do not exist)" do
      get "/api/v1/routes"
      json = JSON.parse(response.body)
      entry = json["data"].first
      expect(entry.keys).not_to include("open_time", "close_time")
    end

    it "includes meta count" do
      get "/api/v1/routes"
      json = JSON.parse(response.body)
      expect(json["meta"]["count"]).to eq(1)
    end
  end

  describe "GET /api/v1/routes/:line_id" do
    it "returns 200 for a known line_id" do
      get "/api/v1/routes/MRT-3"
      expect(response).to have_http_status(:ok)
    end

    it "includes stations and edges in the response" do
      get "/api/v1/routes/MRT-3"
      json = JSON.parse(response.body)
      expect(json["data"]["stations"].length).to eq(2)
      expect(json["data"]["edges"].length).to eq(1)
    end

    it "does not include open_time or close_time on the route summary" do
      get "/api/v1/routes/MRT-3"
      json = JSON.parse(response.body)
      expect(json["data"].keys).not_to include("open_time", "close_time")
    end

    it "returns 404 for an unknown line_id" do
      get "/api/v1/routes/UNKNOWN"
      expect(response).to have_http_status(:not_found)
    end
  end
end
