require "rails_helper"

RSpec.describe "GraphService service areas" do
  let(:boundary) do
    [{ "lat" => 14.60, "lng" => 121.00 }, { "lat" => 14.62, "lng" => 121.00 }, { "lat" => 14.61, "lng" => 121.02 }]
  end

  before do
    GraphMeta.first || GraphMeta.create!
    TransportMode.find_or_create_by!(id: "tricycle") do |m|
      m.display_name = "Tricycle"
      m.mk_directions_type = "automobile"
      m.service_shape = "area"
    end
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }
    Line.create!(id: "SAGS_ZONE", display_name: "Zone", mode: "tricycle")
    ServiceArea.create!(line_id: "SAGS_ZONE", boundary: boundary, base_fare: 15, base_km: 1, fare_per_km: 5,
                        speed_kmh: 15, detour_factor: 1.3, wait_minutes: 3, accepted_payments: ["cash"],
                        special_trip_fare: 50)
    %w[SAGS_ZONE_S2 SAGS_ZONE_S1].each_with_index do |id, index|
      Station.create!(station_id: id, name: id, short_name: "T", line: "SAGS_ZONE", type: "tricycle",
                      lat: 14.61, lng: 121.005 + (index * 0.001), sequence: 2 - index, is_terminal: true)
    end
  end

  def public_graph
    GraphService.assemble_graph.deep_stringify_keys
  end

  def public_zone
    public_graph["serviceAreas"].find { |zone| zone["line"] == "SAGS_ZONE" }
  end

  def admin_zone
    GraphService.assemble_admin_graph.deep_stringify_keys["serviceAreas"].find { |zone| zone["line"] == "SAGS_ZONE" }
  end

  describe "public graph" do
    it "includes the zone with mode, sorted terminals, and fare fields" do
      zone = public_zone

      expect(zone).to include("mode" => "tricycle", "terminalIds" => %w[SAGS_ZONE_S1 SAGS_ZONE_S2],
                              "baseFare" => 15.0, "baseKm" => 1.0, "farePerKm" => 5.0,
                              "speedKmh" => 15.0, "detourFactor" => 1.3, "waitMinutes" => 3.0,
                              "acceptedPayments" => ["cash"], "specialTripFare" => 50.0)
      expect(zone["boundary"].length).to eq(3)
      expect(zone).not_to have_key("hiddenFromRiders")
    end

    it "omits specialTripFare when it is nil" do
      ServiceArea.find("SAGS_ZONE").update!(special_trip_fare: nil)

      expect(public_zone).not_to have_key("specialTripFare")
    end

    it "omits the zone when its line is disabled" do
      Line.find("SAGS_ZONE").update!(enabled: false)

      expect(public_zone).to be_nil
    end

    it "removes a disabled terminal from terminalIds" do
      Station.find("SAGS_ZONE_S2").update!(enabled: false)

      expect(public_zone["terminalIds"]).to eq(["SAGS_ZONE_S1"])
    end

    it "places serviceAreas between railFareTables and stations" do
      keys = GraphService.assemble_graph.keys.map(&:to_s)

      expect(keys.index("serviceAreas")).to eq(keys.index("railFareTables") + 1)
      expect(keys.index("stations")).to eq(keys.index("serviceAreas") + 1)
    end

    it "runs one query for the service areas" do
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "service_areas"') }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { GraphService.assemble_graph }

      expect(queries.length).to eq(1)
    end
  end

  describe "admin graph" do
    it "keeps a disabled line and marks it hidden" do
      Line.find("SAGS_ZONE").update!(enabled: false)

      expect(admin_zone).to include("hiddenFromRiders" => true, "terminalIds" => %w[SAGS_ZONE_S1 SAGS_ZONE_S2])
    end

    it "keeps a disabled terminal" do
      Station.find("SAGS_ZONE_S2").update!(enabled: false)

      expect(admin_zone).to include("hiddenFromRiders" => false, "terminalIds" => %w[SAGS_ZONE_S1 SAGS_ZONE_S2])
    end
  end

  describe "transport modes" do
    it "carries serviceShape" do
      modes = public_graph["transportModes"]

      expect(modes["tricycle"]["serviceShape"]).to eq("area")
      expect(modes["jeepney"]["serviceShape"]).to eq("path")
    end
  end

  describe "#add_route" do
    let(:stops) { [{ "name" => "A", "lat" => 14.30, "lng" => 121.0 }, { "name" => "B", "lat" => 14.31, "lng" => 121.0 }] }

    def route_payload(line_id, mode)
      { "displayName" => line_id, "lineID" => line_id, "mode" => mode, "openTime" => "05:00", "closeTime" => "22:00",
        "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"], "isAirConditioned" => false,
        "crowdFactor" => 0.7, "reliability" => 0.65, "passes" => [{ "bidirectional" => false, "stops" => stops }] }
    end

    it "refuses an area mode and writes nothing" do
      result = GraphService.add_route(route_payload("SAGS_TRIKE", "tricycle"))

      expect(result.success?).to be false
      expect(result.errors).to include(
        field: "mode",
        message: "Mode 'tricycle' runs in a service area. Publish a service_area_add change instead."
      )
      expect(Line.exists?("SAGS_TRIKE")).to be false
      expect(Station.where(line: "SAGS_TRIKE")).to be_empty
    end

    it "still accepts a path mode" do
      result = GraphService.add_route(route_payload("SAGS_PATH", "jeepney"))

      expect(result.success?).to be true
    end
  end

  describe "stop editing" do
    it "refuses insert_stop next to a terminal" do
      result = GraphService.insert_stop("referenceStationId" => "SAGS_ZONE_S1", "position" => "after",
                                        "name" => "New", "lat" => 14.61, "lng" => 121.01)

      expect(result.success?).to be false
      expect(result.errors.first[:message]).to eq(
        "Stop 'SAGS_ZONE_S1' is a terminal of a service area. Use the service_area_terminal_* changes."
      )
      expect(Station.where(line: "SAGS_ZONE").count).to eq(2)
    end

    it "refuses remove_stop on a terminal" do
      result = GraphService.remove_stop("SAGS_ZONE_S1")

      expect(result.success?).to be false
      expect(result.errors.first[:message]).to include("is a terminal of a service area")
      expect(Station.exists?("SAGS_ZONE_S1")).to be true
    end
  end
end
