require "rails_helper"

RSpec.describe "DELETE /api/v1/admin/lines/:id", type: :request do
  before { build_ops_graph! }

  def delete_line(id, user: admin_user)
    delete "/api/v1/admin/lines/#{id}", headers: auth_headers_for(user)
  end

  it "deletes an empty line, its fare rows, and its mode entry, and raises the version once" do
    RailFareTable.create!(line_id: "OPST_EMPTY", station_ids: [], fares: [])
    version = graph_version_now
    delete_line("OPST_EMPTY")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"]).to eq("line_id" => "OPST_EMPTY", "version" => version + 1)
    expect(Line.exists?("OPST_EMPTY")).to be false
    expect(FareMatrix.exists?("OPST_EMPTY")).to be false
    expect(RailFareTable.exists?("OPST_EMPTY")).to be false
    expect(TransportMode.find("bus").lines).not_to include("OPST_EMPTY")
    expect(graph_version_now).to eq(version + 1)
  end

  it "refuses a line that still has stops or edges" do
    version = graph_version_now
    delete_line("OPST_ROAD")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"].first).to include("3 stops and 2 edges")
    expect(Line.exists?("OPST_ROAD")).to be true
    expect(graph_version_now).to eq(version)
  end

  it "refuses INTERCHANGE" do
    delete_line("INTERCHANGE")

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 404 for an unknown line and 403 for a rider" do
    delete_line("OPST_NOPE")
    expect(response).to have_http_status(:not_found)

    delete_line("OPST_EMPTY", user: rider_user)
    expect(response).to have_http_status(:forbidden)
    expect(Line.exists?("OPST_EMPTY")).to be true
  end
end
