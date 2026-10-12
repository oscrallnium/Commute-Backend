require "rails_helper"

RSpec.describe GraphChangeValidator do
  def validate(*changes)
    described_class.new(changes.map(&:deep_stringify_keys)).call
  end

  def errors_for(*changes)
    validate(*changes).last.map(&:to_h)
  end

  it "accepts a valid change and returns clean values" do
    clean, errors = validate({ type: "line_color", line_id: "MRT3", color_hex: " #ab12cd " })

    expect(errors).to be_empty
    expect(clean).to eq([{ "type" => "line_color", "line_id" => "MRT3", "color_hex" => "#AB12CD" }])
  end

  it "rejects an empty list" do
    expect(errors_for).to eq([{ field: "changes", message: "changes must not be empty." }])
  end

  it "rejects an unknown type, a missing field, and an unknown field" do
    errors = errors_for({ type: "nope" }, { type: "stop_name", station_id: "A_B" },
                        { type: "line_delete", line_id: "A", extra: 1 })

    expect(errors).to contain_exactly(
      { index: 0, type: "nope", field: "type", message: "Unknown change type 'nope'." },
      { index: 1, type: "stop_name", field: "name", message: "name is required." },
      { index: 2, type: "line_delete", field: "extra", message: "Unknown field 'extra'." }
    )
  end

  it "rejects a number sent as a string" do
    errors = errors_for({ type: "edge_travel_time", edge_id: "E", travel_time_minutes: "5" })

    expect(errors.first).to include(field: "travel_time_minutes")
  end

  it "rejects a fare grid with the wrong shape or a missing fare" do
    ids = %w[A B C]
    wrong_shape = errors_for({ type: "line_rail_fares", line_id: "L", station_ids: ids, fares: [[nil, 1], [1, nil]] })
    missing     = errors_for({ type: "line_rail_fares", line_id: "L", station_ids: ids,
                               fares: [[nil, 1, 2], [1, nil, nil], [2, 1, nil]] })

    expect(wrong_shape.first[:field]).to eq("fares")
    expect(missing).to eq([{ index: 0, type: "line_rail_fares", field: "fares[1][2]",
                             message: "Every station pair needs a fare." }])
  end

  it "rejects a transfer between legacy IDs and between a stop and itself" do
    errors = errors_for(
      { type: "transfer_add", from_station_id: "STACRUZ.LRT_BUENDIA_STOP3", to_station_id: "MRT_TAFT",
        travel_time_minutes: 3, distance_km: 0.2, polyline: [{ lat: 14.5, lng: 121 }, { lat: 14.6, lng: 121 }] },
      { type: "transfer_add", from_station_id: "MRT_TAFT", to_station_id: "MRT_TAFT",
        travel_time_minutes: 3, distance_km: 0.2, polyline: [{ lat: 14.5, lng: 121 }, { lat: 14.6, lng: 121 }] }
    )

    expect(errors.map { |e| [e[:index], e[:field]] }).to eq([[0, "from_station_id"], [1, "to_station_id"]])
  end

  it "rejects a new access point ID that breaks the convention" do
    errors = errors_for({ type: "access_point_add", station_id: "S", access_point_id: "ap-1", kind: "both",
                          lat: 14.5, lng: 121.0 })

    expect(errors.first).to include(field: "access_point_id")
  end

  it "needs at least one field in an update, and lat with lng" do
    errors = errors_for({ type: "access_point_update", access_point_id: "AP" },
                        { type: "access_point_update", access_point_id: "AP", lat: 14.5 })

    expect(errors.pluck(:index)).to eq([0, 1])
  end
end
