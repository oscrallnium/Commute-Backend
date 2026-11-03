require "rails_helper"

RSpec.describe "Service area publish changes" do
  before do
    build_ops_graph!
    build_area_mode!
  end

  def publish(*changes, base: graph_version_now)
    GraphPublisher.publish(base_version: base, changes: changes.map(&:deep_stringify_keys), user: admin_user)
  end

  def expect_created(result)
    expect(result.status).to eq(:created), result.body.inspect
  end

  def expect_rejected(result, field:, message: nil)
    expect(result.status).to eq(:unprocessable_content), result.body.inspect
    error = result.body[:errors].first
    expect(error[:field]).to eq(field)
    expect(error[:message]).to include(message) if message
  end

  def add_zone!(**overrides)
    expect_created(publish(service_area_change(**overrides)))
  end

  describe "service_area_add" do
    it "creates the line, the zone, and the terminals with one version bump" do
      version = graph_version_now
      result = publish(service_area_change(color_hex: "#abcdef", special_trip_fare: 50))

      expect_created(result)
      expect(graph_version_now).to eq(version + 1)
      expect(result.body[:data][:created]).to eq([])
      expect(Line.find("SAPB_ZONE")).to have_attributes(display_name: "Sapb Zone", mode: "tricycle", direction: "both",
                                                        color_hex: "#ABCDEF", last_stop_number: 2)
      expect(ServiceArea.find("SAPB_ZONE")).to have_attributes(base_fare: 15, special_trip_fare: 50,
                                                               accepted_payments: %w[cash])
      expect(TransportMode.find("tricycle").lines).to include("SAPB_ZONE")
      terminals = Station.where(line: "SAPB_ZONE").order(:station_id)
      expect(terminals.map(&:station_id)).to eq(%w[SAPB_ZONE_S1 SAPB_ZONE_S2])
      expect(terminals.first).to have_attributes(name: "Plaza Gate", short_name: "PLAZA", type: "tricycle",
                                                 is_terminal: true, sequence: nil, open_time: "05:00",
                                                 close_time: "21:00")
    end

    it "refuses a mode that runs on fixed paths" do
      expect_rejected(publish(service_area_change(mode: "bus")), field: "mode", message: "runs on fixed paths")
      expect(Line.exists?("SAPB_ZONE")).to be false
    end

    it "refuses a line ID that exists and a line ID that a stop uses" do
      expect_rejected(publish(service_area_change(line_id: "OPST_ROAD")), field: "line_id")
      Station.create!(station_id: "SAPB_ZONE_X", name: "X", line: "SAPB_ZONE", type: "bus", lat: 14.5, lng: 121.0)
      expect_rejected(publish(service_area_change), field: "line_id")
    end

    it "refuses a terminal outside the boundary" do
      outside = [{ name: "Plaza", lat: 14.51, lng: 121.01 }, { name: "Far", lat: 14.60, lng: 121.01 }]
      expect_rejected(publish(service_area_change(terminals: outside)), field: "terminals[1]")
      expect(Line.exists?("SAPB_ZONE")).to be false
    end

    it "refuses an unknown payment method" do
      expect_rejected(publish(service_area_change(accepted_payments: %w[cash nope])), field: "accepted_payments")
    end

    it "surfaces a self-crossing boundary as a validation error" do
      bow_tie = [{ lat: 14.50, lng: 121.00 }, { lat: 14.52, lng: 121.02 },
                 { lat: 14.52, lng: 121.00 }, { lat: 14.50, lng: 121.02 }]
      result = publish(service_area_change(boundary: bow_tie, terminals: [{ name: "Gate", lat: 14.51, lng: 121.01 }]))

      expect_rejected(result, field: nil, message: "must not cross itself")
      expect(Line.exists?("SAPB_ZONE")).to be false
    end
  end

  describe "service_area_boundary" do
    before { add_zone! }

    let(:bigger) do
      [{ lat: 14.49, lng: 120.99 }, { lat: 14.49, lng: 121.03 }, { lat: 14.53, lng: 121.03 }, { lat: 14.53, lng: 120.99 }]
    end

    it "replaces the boundary" do
      expect_created(publish({ type: "service_area_boundary", line_id: "SAPB_ZONE", boundary: bigger }))

      expect(ServiceArea.find("SAPB_ZONE").boundary.first).to eq("lat" => 14.49, "lng" => 120.99)
    end

    it "refuses a boundary that leaves a terminal outside and names the terminal" do
      small = [{ lat: 14.512, lng: 121.00 }, { lat: 14.512, lng: 121.02 }, { lat: 14.52, lng: 121.02 },
               { lat: 14.52, lng: 121.00 }]
      result = publish({ type: "service_area_boundary", line_id: "SAPB_ZONE", boundary: small })

      expect_rejected(result, field: "boundary", message: "SAPB_ZONE_S1")
      expect(result.body[:errors].first[:message]).not_to include("SAPB_ZONE_S2")
      expect(ServiceArea.find("SAPB_ZONE").boundary.first["lat"]).to eq(14.5)
    end

    it "refuses a line that is not a service area" do
      expect_rejected(publish({ type: "service_area_boundary", line_id: "OPST_ROAD", boundary: bigger }),
                      field: "line_id")
      expect_rejected(publish({ type: "service_area_boundary", line_id: "SAPB_NOPE", boundary: bigger }),
                      field: "line_id")
    end
  end

  describe "service_area_fare" do
    before { add_zone!(special_trip_fare: 50) }

    it "sets the fare, keeps the special trip fare when the key is absent, and clears it with null" do
      expect_created(publish({ type: "service_area_fare", line_id: "SAPB_ZONE", base_fare: 20, base_km: 2,
                               fare_per_km: 6 }))
      expect(ServiceArea.find("SAPB_ZONE")).to have_attributes(base_fare: 20, base_km: 2, fare_per_km: 6,
                                                               special_trip_fare: 50)

      expect_created(publish({ type: "service_area_fare", line_id: "SAPB_ZONE", base_fare: 20, base_km: 2,
                               fare_per_km: 6, special_trip_fare: nil }))
      expect(ServiceArea.find("SAPB_ZONE").special_trip_fare).to be_nil
    end

    it "refuses an unknown payment method" do
      result = publish({ type: "service_area_fare", line_id: "SAPB_ZONE", base_fare: 20, base_km: 2, fare_per_km: 6,
                         accepted_payments: %w[bogus] })

      expect_rejected(result, field: "accepted_payments")
    end
  end

  describe "service_area_timing" do
    before { add_zone! }

    it "sets the timing values" do
      expect_created(publish({ type: "service_area_timing", line_id: "SAPB_ZONE", speed_kmh: 20, wait_minutes: 0 }))

      expect(ServiceArea.find("SAPB_ZONE")).to have_attributes(speed_kmh: 20, wait_minutes: 0, detour_factor: 1.3)
    end

    it "needs at least one value" do
      result = publish({ type: "service_area_timing", line_id: "SAPB_ZONE" })

      expect(result.status).to eq(:unprocessable_content)
      expect(result.body[:errors].first[:message]).to include("at least one")
    end

    it "refuses a detour factor below 1" do
      result = publish({ type: "service_area_timing", line_id: "SAPB_ZONE", detour_factor: 0.9 })

      expect_rejected(result, field: "detour_factor")
    end
  end

  describe "terminals" do
    before { add_zone! }

    def link_transfer!
      Edge.create!(ops_edge_attrs("X__SAPB_ZONE_S1__OPST_ROAD_S1", "SAPB_ZONE_S1", "OPST_ROAD_S1", "INTERCHANGE", "walk",
                                  bidirectional: true))
      Station.where(station_id: %w[SAPB_ZONE_S1 OPST_ROAD_S1]).update_all(is_interchange: true) # rubocop:disable Rails/SkipsModelValidations
    end

    it "adds a terminal, returns its ID, and takes the next stop number" do
      version = graph_version_now
      result = publish({ type: "service_area_terminal_add", line_id: "SAPB_ZONE", name: "Church", lat: 14.512,
                         lng: 121.012, short_name: "CHU" })

      expect_created(result)
      expect(result.body[:data][:created]).to eq([{ index: 0, type: "service_area_terminal_add", id: "SAPB_ZONE_S3" }])
      expect(GraphVersion.find_by!(version: version + 1).change_list.first["station_id"]).to eq("SAPB_ZONE_S3")
      expect(Line.find("SAPB_ZONE").last_stop_number).to eq(3)
      expect(Station.find("SAPB_ZONE_S3")).to have_attributes(short_name: "CHU", is_terminal: true, open_time: "05:00",
                                                              close_time: "21:00")
    end

    it "never reuses a stop number after a delete" do
      expect_created(publish({ type: "service_area_terminal_delete", station_id: "SAPB_ZONE_S2" }))
      result = publish({ type: "service_area_terminal_add", line_id: "SAPB_ZONE", name: "Church", lat: 14.512, lng: 121.012 })

      expect(result.body[:data][:created].first[:id]).to eq("SAPB_ZONE_S3")
    end

    it "refuses a terminal outside the boundary" do
      result = publish({ type: "service_area_terminal_add", line_id: "SAPB_ZONE", name: "Far", lat: 14.7, lng: 121.0 })

      expect_rejected(result, field: "lat")
      expect(Line.find("SAPB_ZONE").last_stop_number).to eq(2)
    end

    it "deletes a terminal with its transfers and refreshes the flags of the other stops" do
      link_transfer!
      expect_created(publish({ type: "service_area_terminal_delete", station_id: "SAPB_ZONE_S1" }))

      expect(Station.exists?("SAPB_ZONE_S1")).to be false
      expect(Edge.exists?("X__SAPB_ZONE_S1__OPST_ROAD_S1")).to be false
      expect(Station.find("OPST_ROAD_S1").is_interchange).to be false
    end

    it "keeps the flag of a stop that has another transfer" do
      link_transfer!
      Edge.create!(ops_edge_attrs("X__OPST_ROAD_S1__OPST_RAIL_A", "OPST_ROAD_S1", "OPST_RAIL_A", "INTERCHANGE", "walk",
                                  bidirectional: true))
      expect_created(publish({ type: "service_area_terminal_delete", station_id: "SAPB_ZONE_S1" }))

      expect(Station.find("OPST_ROAD_S1").is_interchange).to be true
    end

    it "refuses to delete the last terminal" do
      expect_created(publish({ type: "service_area_terminal_delete", station_id: "SAPB_ZONE_S2" }))
      result = publish({ type: "service_area_terminal_delete", station_id: "SAPB_ZONE_S1" })

      expect_rejected(result, field: "station_id", message: "at least one terminal")
    end

    it "refuses to delete a stop that is not a terminal of a service area" do
      expect_rejected(publish({ type: "service_area_terminal_delete", station_id: "OPST_ROAD_S1" }),
                      field: "station_id")
    end
  end

  describe "existing line changes on a service area" do
    before { add_zone! }

    it "refuses a road fare and a direction" do
      fare = publish({ type: "line_road_fare", line_id: "SAPB_ZONE", base_fare: 15, base_km: 1, fare_per_km: 2 })
      direction = publish({ type: "line_direction", line_id: "SAPB_ZONE", direction: "one_way" })

      expect_rejected(fare, field: "line_id", message: "Use service_area_fare.")
      expect_rejected(direction, field: "line_id", message: "has no direction")
    end

    it "deletes the zone, its terminals, and their transfers with line_delete" do
      Edge.create!(ops_edge_attrs("X__SAPB_ZONE_S1__OPST_ROAD_S1", "SAPB_ZONE_S1", "OPST_ROAD_S1", "INTERCHANGE", "walk",
                                  bidirectional: true))
      Station.where(station_id: "OPST_ROAD_S1").update_all(is_interchange: true) # rubocop:disable Rails/SkipsModelValidations
      expect_created(publish({ type: "line_delete", line_id: "SAPB_ZONE" }))

      expect(Line.exists?("SAPB_ZONE")).to be false
      expect(ServiceArea.exists?("SAPB_ZONE")).to be false
      expect(Station.where(line: "SAPB_ZONE")).to be_empty
      expect(Edge.exists?("X__SAPB_ZONE_S1__OPST_ROAD_S1")).to be false
      expect(Station.find("OPST_ROAD_S1").is_interchange).to be false
      expect(TransportMode.find("tricycle").lines).not_to include("SAPB_ZONE")
    end

    it "still refuses to delete a path line that has stops" do
      result = publish({ type: "line_delete", line_id: "OPST_ROAD" })

      expect(result.status).to eq(:unprocessable_content)
      expect(Line.exists?("OPST_ROAD")).to be true
    end
  end
end
