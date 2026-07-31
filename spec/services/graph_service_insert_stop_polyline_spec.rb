require "rails_helper"

# A head/tail stop insert has no existing segment to slice, and used to be written with an
# empty polyline "for Explore to road-snap later". Explore only ever snapped into its own
# in-memory cache and never wrote back, so those edges stayed empty forever — appending
# CEAT to UPLB_KANAN produced UPLB_KANAN_SEG8 with 0 waypoints, and the route drew nothing
# between Animal Science and the new stop.
#
# The client now fetches the road route at save time and posts it as `polylineCoordinates`.
RSpec.describe "GraphService#insert_stop polyline handling" do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }
  end

  let(:stops) do
    (1..4).map { |i| { "name" => "S#{i}", "lat" => 14.20 + i * 0.01, "lng" => 121.0 } }
  end

  def create_route(line_id)
    result = GraphService.add_route({
      "displayName" => "Test", "lineID" => line_id, "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [{ "bidirectional" => false, "stops" => stops }]
    })
    raise "fixture failed: #{result.errors.inspect}" unless result.success?
  end

  def edge(id) = Edge.find_by(edge_id: id)
  def points(edge) = (edge.polyline_coordinates || []).map { |p| [(p[:lat] || p["lat"]).to_f, (p[:lng] || p["lng"]).to_f] }

  before { create_route("POLY") }
  after  { GraphService.delete_route("POLY") }

  describe "appending a stop after the last one" do
    let(:new_lat) { 14.25 }
    let(:road) do
      # Stands in for what MKDirections returns: a bent path, not the straight chord.
      [{ "lat" => 14.2401, "lng" => 121.0 },
       { "lat" => 14.2450, "lng" => 121.0030 },
       { "lat" => 14.2499, "lng" => 121.0 }]
    end

    it "stores the supplied road geometry instead of an empty polyline" do
      result = GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP4", "position" => "after",
        "name" => "CEAT", "lat" => new_lat, "lng" => 121.0,
        "polylineCoordinates" => road
      )
      expect(result.success?).to be true

      seg = edge("POLY_SEG4")
      expect(seg.from_station).to eq "POLY_STOP4"
      expect(seg.to_station).to eq "POLY_STOP5"
      expect(points(seg).length).to eq 3
      expect(seg.is_road_snapped).to be true
    end

    it "pins the polyline's ends to the two stations so the line meets both pins" do
      GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP4", "position" => "after",
        "name" => "CEAT", "lat" => new_lat, "lng" => 121.0,
        "polylineCoordinates" => road
      )
      pts = points(edge("POLY_SEG4"))
      expect(pts.first).to eq [14.24, 121.0]     # POLY_STOP4, not the road's 14.2401
      expect(pts.last).to  eq [new_lat, 121.0]   # the new stop, not the road's 14.2499
    end

    it "measures distance along the road rather than as the crow flies" do
      GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP4", "position" => "after",
        "name" => "CEAT", "lat" => new_lat, "lng" => 121.0,
        "polylineCoordinates" => road
      )
      crow_flies = 1.11 # ~0.01 degrees of latitude
      expect(edge("POLY_SEG4").distance_km).to be > crow_flies
    end

    it "still writes an empty polyline when the client couldn't supply one" do
      GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP4", "position" => "after",
        "name" => "CEAT", "lat" => new_lat, "lng" => 121.0
      )
      seg = edge("POLY_SEG4")
      expect(points(seg)).to be_empty
      expect(seg.is_road_snapped).to be false
    end

    it "rejects a two-point 'polyline' — that is the straight chord, not a road route" do
      GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP4", "position" => "after",
        "name" => "CEAT", "lat" => new_lat, "lng" => 121.0,
        "polylineCoordinates" => [{ "lat" => 14.24, "lng" => 121.0 }, { "lat" => new_lat, "lng" => 121.0 }]
      )
      expect(points(edge("POLY_SEG4"))).to be_empty
      expect(edge("POLY_SEG4").is_road_snapped).to be false
    end

    it "ignores malformed coordinates rather than storing them" do
      GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP4", "position" => "after",
        "name" => "CEAT", "lat" => new_lat, "lng" => 121.0,
        "polylineCoordinates" => [{ "lat" => 999, "lng" => 121.0 }, { "lat" => nil, "lng" => 121.0 }]
      )
      expect(points(edge("POLY_SEG4"))).to be_empty
    end
  end

  describe "inserting a stop at the head" do
    it "orients the new edge new-stop → old-first-stop" do
      road = [{ "lat" => 14.2050, "lng" => 121.0 },
              { "lat" => 14.2075, "lng" => 121.0020 },
              { "lat" => 14.2099, "lng" => 121.0 }]
      GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP1", "position" => "before",
        "name" => "New Head", "lat" => 14.205, "lng" => 121.0,
        "polylineCoordinates" => road
      )
      seg = edge("POLY_SEG1")
      expect([seg.from_station, seg.to_station]).to eq %w[POLY_STOP1 POLY_STOP2]
      expect(points(seg).first).to eq [14.205, 121.0]  # the new head stop
      expect(points(seg).last).to  eq [14.21, 121.0]   # the old first stop
      expect(seg.is_road_snapped).to be true
    end
  end

  describe "splitting a mid-chain segment at its very first vertex" do
    # Slicing at index 0 gives the first half a single point, which is no polyline at all —
    # the same "0 waypoints" symptom, reached from the other direction.
    it "leaves both halves with a drawable line" do
      edge("POLY_SEG1").update!(polyline_coordinates: [
        { lat: 14.21, lng: 121.0 }, { lat: 14.213, lng: 121.001 },
        { lat: 14.217, lng: 121.001 }, { lat: 14.22, lng: 121.0 }
      ])

      result = GraphService.insert_stop(
        "referenceStationId" => "POLY_STOP1", "position" => "after",
        "name" => "Right At The Start", "lat" => 14.2100, "lng" => 121.0
      )
      expect(result.success?).to be true
      expect(points(edge("POLY_SEG1")).length).to be >= 2
      expect(points(edge("POLY_SEG2")).length).to be >= 2
    end
  end
end
