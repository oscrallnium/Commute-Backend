require "rails_helper"

# Directionality had no editor anywhere: `edge_params` permitted only
# polyline_coordinates, so a two-way segment left in the middle of a one-way route (by an
# insert done before edge_attrs inherited directionality) could not be repaired by any
# client, and a route saved with the wrong setting had to be deleted and re-recorded.
RSpec.describe "PATCH /api/v1/admin/edges/:id", type: :request do
  let(:admin) do
    User.create!(email: "admin_#{SecureRandom.hex(4)}@test.com", password: "Password1!",
                 display_name: "Admin", role: :admin)
  end

  let!(:edge) do
    Edge.create!(
      edge_id: "TEST_SEG1", from_station: "TEST_STOP1", to_station: "TEST_STOP2",
      mode: "jeepney", line: "TEST", travel_time_minutes: 5, distance_km: 1.0,
      base_fare: 13, fare_per_km: 1.8, accepted_payments: ["cash"],
      is_air_conditioned: false, crowd_factor: 0.5, reliability: 0.9,
      bidirectional: true, direction: nil, polyline_coordinates: [],
      mk_directions_transport_type: "automobile", is_road_snapped: false
    )
  end

  def patch_edge(body)
    patch "/api/v1/admin/edges/TEST_SEG1",
          params: { edge: body }.to_json,
          headers: auth_headers_for(admin).merge("Content-Type" => "application/json")
  end

  it "makes a two-way edge one-way — the repair case" do
    patch_edge(bidirectional: false)
    expect(response).to have_http_status(:ok)
    expect(edge.reload.bidirectional).to be false
  end

  it "accepts the string 'false' a form-encoded client would send" do
    patch_edge(bidirectional: "false")
    expect(edge.reload.bidirectional).to be false
  end

  it "leaves the polyline alone when only directionality is sent" do
    edge.update!(polyline_coordinates: [{ "lat" => 14.1, "lng" => 121.1 },
                                        { "lat" => 14.2, "lng" => 121.2 }])
    patch_edge(bidirectional: false)
    expect(edge.reload.polyline_coordinates.length).to eq(2)
  end

  it "sets a direction label" do
    patch_edge(bidirectional: false, direction: "northbound")
    expect(edge.reload.direction).to eq("northbound")
  end

  it "clears a direction label when sent null" do
    edge.update!(bidirectional: false, direction: "northbound")
    patch_edge(direction: nil)
    expect(edge.reload.direction).to be_nil
  end

  it "rejects a direction-tagged edge marked bidirectional" do
    patch_edge(bidirectional: true, direction: "northbound")
    expect(response).to have_http_status(:unprocessable_content)
    expect(edge.reload.direction).to be_nil
  end

  it "rejects the same pairing when the direction is already stored" do
    edge.update!(bidirectional: false, direction: "northbound")
    patch_edge(bidirectional: true)
    expect(response).to have_http_status(:unprocessable_content)
    expect(edge.reload.bidirectional).to be false
  end

  it "rejects an empty edge object (ParameterMissing, before any of our checks)" do
    patch_edge({})
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects an update with no recognised field instead of silently succeeding" do
    patch_edge(not_a_field: "x")
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["error"]).to eq("Nothing to update")
  end

  it "still updates the polyline, recomputing distance and trusting the geometry" do
    patch_edge(polyline_coordinates: [{ lat: 14.10, lng: 121.10 },
                                      { lat: 14.20, lng: 121.20 }])
    expect(response).to have_http_status(:ok)
    edge.reload
    expect(edge.polyline_coordinates.length).to eq(2)
    expect(edge.is_road_snapped).to be true
    expect(edge.distance_km.to_f).to be > 1.0
  end

  it "updates the polyline and directionality together" do
    patch_edge(bidirectional: false,
               polyline_coordinates: [{ lat: 14.10, lng: 121.10 }, { lat: 14.20, lng: 121.20 }])
    expect(response).to have_http_status(:ok)
    edge.reload
    expect(edge.bidirectional).to be false
    expect(edge.polyline_coordinates.length).to eq(2)
  end
end
