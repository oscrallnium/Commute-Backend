require "rails_helper"

RSpec.describe GraphPublisher do
  before { build_ops_graph! }

  def publish(*changes, base: graph_version_now)
    described_class.publish(base_version: base, changes: changes.map(&:deep_stringify_keys), user: admin_user)
  end

  def expect_created(result)
    expect(result.status).to eq(:created), result.body.inspect
  end

  describe "one publish" do
    it "applies every change, raises the version once, and records one history row" do
      version = graph_version_now
      result = publish(
        { type: "line_name", line_id: "OPST_ROAD", name: "Road–Line" },
        { type: "line_color", line_id: "OPST_ROAD", color_hex: "#a1b2c3" },
        { type: "stop_name", station_id: "OPST_ROAD_S1", name: "First Stop" },
        { type: "edge_travel_time", edge_id: "OPST_ROAD_S1__OPST_ROAD_S2", travel_time_minutes: 7.5 }
      )

      expect_created(result)
      expect(graph_version_now).to eq(version + 1)
      expect(Line.find("OPST_ROAD")).to have_attributes(display_name: "Road–Line", color_hex: "#A1B2C3")
      expect(Station.find("OPST_ROAD_S1").name).to eq("First Stop")
      expect(Edge.find("OPST_ROAD_S1__OPST_ROAD_S2").travel_time_minutes).to eq(7.5)

      row = GraphVersion.find_by!(version: version + 1)
      expect(row).to have_attributes(change_count: 4, published_by_id: admin_user.id)
      expect(row.change_list.first).to eq("type" => "line_name", "line_id" => "OPST_ROAD", "name" => "Road–Line")
      expect(result.body[:data]).to include(version: version + 1, change_count: 4, created: [])
    end

    it "returns a conflict and changes nothing when base_version is not current" do
      version = graph_version_now
      result = publish({ type: "line_name", line_id: "OPST_ROAD", name: "Late" }, base: version - 1)

      expect(result.status).to eq(:conflict)
      expect(result.body).to include(base_version: version - 1, current_version: version)
      expect(Line.find("OPST_ROAD").display_name).not_to eq("Late")
      expect(graph_version_now).to eq(version)
    end

    it "rolls back every change when a later change names a missing row" do
      version = graph_version_now
      result = publish(
        { type: "line_name", line_id: "OPST_ROAD", name: "Kept Out" },
        { type: "stop_name", station_id: "OPST_NOPE", name: "Ghost" }
      )

      expect(result.status).to eq(:unprocessable_content)
      expect(result.body[:errors]).to eq([{ index: 1, type: "stop_name", field: "station_id",
                                            message: "Stop 'OPST_NOPE' was not found." }])
      expect(Line.find("OPST_ROAD").display_name).not_to eq("Kept Out")
      expect(graph_version_now).to eq(version)
      expect(GraphVersion.where(version: version + 1)).to be_empty
    end

    it "reports every shape error with its index before it writes anything" do
      result = publish(
        { type: "line_name", line_id: "OPST_ROAD", name: "" },
        { type: "edge_distance", edge_id: "OPST_ROAD_S1__OPST_ROAD_S2", distance_km: -1 },
        { type: "warp_drive" }
      )

      expect(result.status).to eq(:unprocessable_content)
      expect(result.body[:errors].pluck(:index)).to eq([0, 1, 2])
    end

    it "rejects a missing base_version" do
      result = described_class.publish(base_version: nil, changes: [{ "type" => "line_delete", "line_id" => "X" }],
                                       user: admin_user)

      expect(result.status).to eq(:unprocessable_content)
      expect(result.body[:errors].first).to include(field: "base_version")
    end
  end

  describe "line changes" do
    it "writes the road fare to every edge of the line and the free distance to the line" do
      expect_created(publish({ type: "line_road_fare", line_id: "OPST_ROAD", base_fare: 15, base_km: 4, fare_per_km: 2.2 }))

      expect(Edge.where(line: "OPST_ROAD").pluck(:base_fare, :fare_per_km).uniq).to eq([[15, 2.2]])
      expect(Line.find("OPST_ROAD").base_km).to eq(4)
    end

    it "refuses a road fare on a train line" do
      result = publish({ type: "line_road_fare", line_id: "OPST_RAIL", base_fare: 15, base_km: 4, fare_per_km: 2 })

      expect(result.status).to eq(:unprocessable_content)
      expect(result.body[:errors].first[:message]).to include("train line")
    end

    it "sets the line direction and the bidirectional flag of its edges" do
      expect_created(publish({ type: "line_direction", line_id: "OPST_RAIL", direction: "one_way" }))

      expect(Line.find("OPST_RAIL").direction).to eq("one_way")
      expect(Edge.where(line: "OPST_RAIL").pluck(:bidirectional).uniq).to eq([false])
    end

    it "refuses both ways on a line whose edges have a compass direction" do
      Edge.where(line: "OPST_ROAD").update_all(direction: "northbound")
      result = publish({ type: "line_direction", line_id: "OPST_ROAD", direction: "both" })

      expect(result.status).to eq(:unprocessable_content)
    end

    it "disables a line with a reason and clears the reason when it enables the line again" do
      expect_created(publish({ type: "line_enabled", line_id: "OPST_ROAD", enabled: false, reason: "Road works" }))
      expect(Line.find("OPST_ROAD")).to have_attributes(enabled: false, disabled_reason: "Road works")

      expect_created(publish({ type: "line_enabled", line_id: "OPST_ROAD", enabled: true, reason: "ignored" }))
      expect(Line.find("OPST_ROAD")).to have_attributes(enabled: true, disabled_reason: nil)
    end

    it "refuses to disable INTERCHANGE" do
      result = publish({ type: "line_enabled", line_id: "INTERCHANGE", enabled: false, reason: nil })

      expect(result.status).to eq(:unprocessable_content)
    end

    it "stores a rail fare table for the line" do
      expect_created(publish({ type: "line_rail_fares", line_id: "OPST_RAIL",
                               station_ids: %w[OPST_RAIL_A OPST_RAIL_B OPST_RAIL_C],
                               fares: [[nil, 13, 16], [13, 0, 13], [16, 13, nil]] }))

      table = RailFareTable.find("OPST_RAIL")
      expect(table.station_ids).to eq(%w[OPST_RAIL_A OPST_RAIL_B OPST_RAIL_C])
      expect(table.fares).to eq([[nil, 13.0, 16.0], [13.0, nil, 13.0], [16.0, 13.0, nil]])
    end

    it "refuses a rail fare table with a stop from another line" do
      result = publish({ type: "line_rail_fares", line_id: "OPST_RAIL", station_ids: %w[OPST_RAIL_A OPST_ROAD_S1],
                         fares: [[nil, 13], [13, nil]] })

      expect(result.status).to eq(:unprocessable_content)
      expect(result.body[:errors].first[:message]).to include("OPST_ROAD_S1")
    end

    it "deletes an empty line" do
      expect_created(publish({ type: "line_delete", line_id: "OPST_EMPTY" }))

      expect(Line.exists?("OPST_EMPTY")).to be false
    end

    it "refuses to delete a line that has stops" do
      result = publish({ type: "line_delete", line_id: "OPST_ROAD" })

      expect(result.status).to eq(:unprocessable_content)
      expect(Line.exists?("OPST_ROAD")).to be true
    end
  end

  describe "stop and edge changes" do
    it "writes the short name, boarding, hours, and enabled state of a stop" do
      expect_created(publish(
                       { type: "stop_short_name", station_id: "OPST_ROAD_S2", short_name: "MID" },
                       { type: "stop_boarding", station_id: "OPST_ROAD_S2", boarding: "alight_only" },
                       { type: "stop_hours", station_id: "OPST_ROAD_S2", open: "04:30", close: "22:00" },
                       { type: "stop_enabled", station_id: "OPST_ROAD_S2", enabled: false, reason: "Closed for repairs" }
                     ))

      expect(Station.find("OPST_ROAD_S2")).to have_attributes(
        short_name: "MID", boarding: "alight_only", open_time: "04:30", close_time: "22:00",
        enabled: false, disabled_reason: "Closed for repairs"
      )
    end

    it "writes the distance and enabled state of an edge" do
      id = "OPST_ROAD_S2__OPST_ROAD_S3"
      expect_created(publish({ type: "edge_distance", edge_id: id, distance_km: 2.4 },
                             { type: "edge_enabled", edge_id: id, enabled: false, reason: nil }))

      expect(Edge.find(id)).to have_attributes(distance_km: 2.4, enabled: false)
    end
  end

  describe "access point changes" do
    it "adds, updates, and deletes access points, and returns the generated ID" do
      result = publish(
        { type: "access_point_add", station_id: "OPST_RAIL_A", access_point_id: "OPST_RAIL_A_AP_1", name: "Gate 1",
          kind: "entrance", direction: "northbound", lat: 14.5, lng: 121.0 },
        { type: "access_point_add", station_id: "OPST_RAIL_A", kind: "exit", lat: 14.501, lng: 121.001 },
        { type: "access_point_update", access_point_id: "OPST_RAIL_A_AP_1", name: "Gate A", direction: nil }
      )

      expect_created(result)
      generated = result.body[:data][:created].find { |c| c[:index] == 1 }[:id]
      expect(generated).to match(/\AOPST_RAIL_A_AP_[0-9A-F]{8}\z/)
      expect(StationAccessPoint.find("OPST_RAIL_A_AP_1")).to have_attributes(name: "Gate A", direction: nil, kind: "entrance")
      expect(GraphVersion.last.change_list[1]["access_point_id"]).to eq(generated)

      expect_created(publish({ type: "access_point_delete", access_point_id: "OPST_RAIL_A_AP_1" }))
      expect(StationAccessPoint.exists?("OPST_RAIL_A_AP_1")).to be false
    end
  end

  describe "transfer changes" do
    let(:path) { [{ lat: 14.51, lng: 121.0 }, { lat: 14.52, lng: 121.0 }] }

    it "adds a transfer edge with the convention ID and marks both stops as interchanges" do
      result = publish({ type: "transfer_add", from_station_id: "OPST_ROAD_S3", to_station_id: "OPST_RAIL_C",
                         travel_time_minutes: 4, distance_km: 0.15, polyline: path })

      expect_created(result)
      edge = Edge.find("X__OPST_ROAD_S3__OPST_RAIL_C")
      expect(edge).to have_attributes(line: "INTERCHANGE", mode: "walk", bidirectional: true, base_fare: 0)
      expect(Station.where(station_id: %w[OPST_ROAD_S3 OPST_RAIL_C]).pluck(:is_interchange)).to eq([true, true])
      expect(result.body[:data][:created]).to eq([{ index: 0, type: "transfer_add", id: "X__OPST_ROAD_S3__OPST_RAIL_C" }])
    end

    it "refuses a second transfer between the same two stops" do
      result = publish({ type: "transfer_add", from_station_id: "OPST_RAIL_B", to_station_id: "OPST_ROAD_S2",
                         travel_time_minutes: 4, distance_km: 0.15, polyline: path })

      expect(result.status).to eq(:unprocessable_content)
    end

    it "updates and deletes a transfer, and clears the interchange flag of a stop with no transfer left" do
      id = "X__OPST_ROAD_S2__OPST_RAIL_B"
      expect_created(publish({ type: "transfer_update", edge_id: id, travel_time_minutes: 6, polyline: path }))
      expect(Edge.find(id).travel_time_minutes).to eq(6)
      expect(Edge.find(id).polyline_coordinates).to eq(path.map(&:stringify_keys))

      expect_created(publish({ type: "transfer_delete", edge_id: id }))
      expect(Edge.exists?(id)).to be false
      expect(Station.find("OPST_ROAD_S2").is_interchange).to be false
    end

    it "refuses a transfer change on an edge that is not on INTERCHANGE" do
      result = publish({ type: "transfer_delete", edge_id: "OPST_ROAD_S1__OPST_ROAD_S2" })

      expect(result.status).to eq(:unprocessable_content)
      expect(Edge.exists?("OPST_ROAD_S1__OPST_ROAD_S2")).to be true
    end
  end
end
