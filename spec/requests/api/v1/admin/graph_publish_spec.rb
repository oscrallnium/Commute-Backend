require "rails_helper"

RSpec.describe "Admin graph read, publish, and history", type: :request do
  before { build_ops_graph! }

  def json_headers(user)
    (user ? auth_headers_for(user) : {}).merge("Content-Type" => "application/json")
  end

  def post_publish(body, user: admin_user)
    post "/api/v1/admin/graph/publish", params: body.is_a?(String) ? body : body.to_json, headers: json_headers(user)
  end

  describe "GET /api/v1/admin/graph" do
    before do
      Line.find("OPST_ROAD").update!(enabled: false, disabled_reason: "Road works", base_km: 4)
      Station.find("OPST_RAIL_C").update!(enabled: false)
      RailFareTable.create!(line_id: "OPST_RAIL", station_ids: %w[OPST_RAIL_A OPST_RAIL_B], fares: [[nil, 13], [13, nil]])
    end

    it "returns hidden items with their ops fields" do
      get "/api/v1/admin/graph", headers: auth_headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data["lines"]["OPST_ROAD"]).to include("enabled" => false, "disabledReason" => "Road works",
                                                    "hiddenFromRiders" => true, "baseKm" => 4.0, "direction" => "both")
      stop = data["stations"].find { |s| s["id"] == "OPST_ROAD_S1" }
      expect(stop).to include("enabled" => true, "hiddenFromRiders" => true)
      edge = data["edges"].find { |e| e["id"] == "OPST_RAIL_B__OPST_RAIL_C" }
      expect(edge).to include("enabled" => true, "disabledReason" => nil, "hiddenFromRiders" => true)
      expect(data["railFareTables"]["OPST_RAIL"]).to eq("stationIds" => %w[OPST_RAIL_A OPST_RAIL_B],
                                                        "fares" => [[nil, 13], [13, nil]])
    end

    it "returns 403 for a rider and 401 with no token" do
      get "/api/v1/admin/graph", headers: auth_headers_for(rider_user)
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/admin/graph"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/admin/graph/publish" do
    it "publishes and returns 201 with the new version" do
      version = graph_version_now
      post_publish({ base_version: version, changes: [{ type: "stop_name", station_id: "OPST_ROAD_S1", name: "New" }] })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["data"]).to include("version" => version + 1, "change_count" => 1, "created" => [])
      expect(response.parsed_body["data"]["published_by"]).to include("display_name" => "Ops Admin")
      expect(Station.find("OPST_ROAD_S1").name).to eq("New")
    end

    it "keeps the null cells of a rail fare grid" do
      grid = [[nil, 13, 16], [13, nil, 13], [16, 13, nil]]
      post_publish({ base_version: graph_version_now,
                     changes: [{ type: "line_rail_fares", line_id: "OPST_RAIL",
                                 station_ids: %w[OPST_RAIL_A OPST_RAIL_B OPST_RAIL_C], fares: grid }] })

      expect(response).to have_http_status(:created), response.body
      expect(RailFareTable.find("OPST_RAIL").fares).to eq(grid)
    end

    it "returns 409 for an old base_version" do
      post_publish({ base_version: graph_version_now - 1,
                     changes: [{ type: "stop_name", station_id: "OPST_ROAD_S1", name: "New" }] })

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include("error" => "Version conflict", "current_version" => graph_version_now)
    end

    it "returns 422 with the index and changes nothing" do
      version = graph_version_now
      post_publish({ base_version: version,
                     changes: [{ type: "stop_name", station_id: "OPST_ROAD_S1", name: "New" },
                               { type: "edge_enabled", edge_id: "OPST_NONE", enabled: false, reason: nil }] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to eq([{ "index" => 1, "type" => "edge_enabled", "field" => "edge_id",
                                                      "message" => "Edge 'OPST_NONE' was not found." }])
      expect(Station.find("OPST_ROAD_S1").name).not_to eq("New")
      expect(graph_version_now).to eq(version)
    end

    it "returns 400 for a body that is not JSON" do
      post_publish("{not json")

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 403 for a rider" do
      post_publish({ base_version: graph_version_now, changes: [] }, user: rider_user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/admin/graph/versions" do
    before do
      2.times do |n|
        post_publish({ base_version: graph_version_now,
                       changes: [{ type: "stop_name", station_id: "OPST_ROAD_S1", name: "Name #{n}" }] })
      end
    end

    it "lists versions newest first, with paging and no change list" do
      get "/api/v1/admin/graph/versions", params: { per_page: 1 }, headers: auth_headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["data"].length).to eq(1)
      expect(body["data"].first["version"]).to eq(graph_version_now)
      expect(body["data"].first).not_to have_key("changes")
      expect(body["meta"]).to include("current_page" => 1, "per_page" => 1)
      expect(body["meta"]["total_count"]).to be >= 2
    end

    it "returns an empty page past the last page" do
      get "/api/v1/admin/graph/versions", params: { page: 9999 }, headers: auth_headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to eq([])
    end

    it "returns one version with its change list" do
      get "/api/v1/admin/graph/versions/#{graph_version_now}", headers: auth_headers_for(admin_user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["changes"]).to eq(
        [{ "type" => "stop_name", "station_id" => "OPST_ROAD_S1", "name" => "Name 1" }]
      )
    end

    it "returns 404 for a version with no history row" do
      get "/api/v1/admin/graph/versions/999999999", headers: auth_headers_for(admin_user)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 403 for a rider" do
      get "/api/v1/admin/graph/versions", headers: auth_headers_for(rider_user)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
