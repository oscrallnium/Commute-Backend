require "rails_helper"

RSpec.describe "GET /api/v1/graph visibility", type: :request do
  before { build_ops_graph! }

  def public_graph
    get "/api/v1/graph"
    expect(response).to have_http_status(:ok)
    response.parsed_body["data"]
  end

  def ids(list) = list.map { |item| item["id"] }.select { |id| id.include?("OPST") }

  it "keeps every top-level key that the iOS app decodes and adds the rail fare tables" do
    expect(public_graph.keys).to include("version", "lastModified", "enforceOperatingHours", "metadata",
                                         "transportModes", "paymentMethods", "lines", "peakHourMultipliers",
                                         "fareMatrix", "railFareTables", "stations", "edges")
  end

  it "leaves out the ops fields" do
    data = public_graph
    expect(data["lines"]["OPST_ROAD"].keys).to contain_exactly("id", "displayName", "mode", "lastStopNumber", "baseKm")
    expect(data["stations"].find { |s| s["id"] == "OPST_ROAD_S1" }).not_to have_key("enabled")
    expect(data["edges"].find { |e| e["id"] == "OPST_ROAD_S1__OPST_ROAD_S2" }).not_to have_key("enabled")
  end

  it "hides a disabled line with its stops, edges, transfers, fare rows, and mode entry" do
    Line.find("OPST_EMPTY").update!(enabled: false)
    Line.find("OPST_ROAD").update!(enabled: false)
    data = public_graph

    expect(data["lines"].keys).not_to include("OPST_ROAD", "OPST_EMPTY")
    expect(ids(data["stations"])).to eq(%w[OPST_RAIL_A OPST_RAIL_B OPST_RAIL_C])
    expect(ids(data["edges"])).to eq(%w[OPST_RAIL_A__OPST_RAIL_B OPST_RAIL_B__OPST_RAIL_C])
    expect(data["fareMatrix"].keys).not_to include("OPST_EMPTY")
    expect(data["transportModes"]["bus"]["lines"]).not_to include("OPST_EMPTY")
  end

  it "hides a disabled stop and every edge that touches it" do
    Station.find("OPST_RAIL_B").update!(enabled: false)
    data = public_graph

    expect(ids(data["stations"])).not_to include("OPST_RAIL_B")
    expect(ids(data["edges"])).to eq(%w[OPST_ROAD_S1__OPST_ROAD_S2 OPST_ROAD_S2__OPST_ROAD_S3])
  end

  it "hides a disabled edge and an edge that points at a missing stop" do
    Edge.find("OPST_ROAD_S1__OPST_ROAD_S2").update!(enabled: false)
    Edge.create!(ops_edge_attrs("E_OPST_DANGLING", "OPST_ROAD_S1", "OPST_GONE", "INTERCHANGE", "walk", bidirectional: true))

    expect(ids(public_graph["edges"])).not_to include("OPST_ROAD_S1__OPST_ROAD_S2", "E_OPST_DANGLING")
  end

  it "serves the rail fare table without the rows and columns of a hidden stop" do
    RailFareTable.create!(line_id: "OPST_RAIL", station_ids: %w[OPST_RAIL_A OPST_RAIL_B OPST_RAIL_C],
                          fares: [[nil, 13, 16], [13, nil, 13], [16, 13, nil]])
    Station.find("OPST_RAIL_B").update!(enabled: false)

    expect(public_graph["railFareTables"]["OPST_RAIL"]).to eq("stationIds" => %w[OPST_RAIL_A OPST_RAIL_C],
                                                              "fares" => [[nil, 16], [16, nil]])
  end
end
