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

  it "accepts fare_step_km on a road fare as absent, null, or 0 or more, and refuses a negative value" do
    base = { type: "line_road_fare", line_id: "L", base_fare: 13, base_km: 4, fare_per_km: 1.8 }
    clean, errors = validate(base, base.merge(fare_step_km: nil), base.merge(fare_step_km: 1))

    expect(errors).to be_empty
    expect(clean[0]).not_to have_key("fare_step_km")
    expect(clean[1]).to include("fare_step_km" => nil)
    expect(clean[2]).to include("fare_step_km" => 1.0)
    expect(errors_for(base.merge(fare_step_km: -1)).first).to include(field: "fare_step_km")
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
        from_access_point_id: "AP_A", to_access_point_id: "AP_B", travel_time_minutes: 3, distance_km: 0.2,
        polyline: [{ lat: 14.5, lng: 121 }, { lat: 14.6, lng: 121 }] },
      { type: "transfer_add", from_station_id: "MRT_TAFT", to_station_id: "MRT_TAFT",
        from_access_point_id: "AP_A", to_access_point_id: "AP_B", travel_time_minutes: 3, distance_km: 0.2,
        polyline: [{ lat: 14.5, lng: 121 }, { lat: 14.6, lng: 121 }] }
    )

    expect(errors.map { |e| [e[:index], e[:field]] }).to eq([[0, "from_station_id"], [1, "to_station_id"]])
  end

  it "accepts bidirectional alone on a transfer update" do
    clean, errors = validate({ type: "transfer_update", edge_id: "X__A__B", bidirectional: false })

    expect(errors).to be_empty
    expect(clean.first["bidirectional"]).to be false
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

  describe "payment fields" do
    it "cleans a valid payment method add" do
      clean, errors = validate({ type: "payment_method_add", payment_method_id: "mari_bank", name: " MariBank ",
                                 color_hex: "#ff5722", accepted_by_modes: %w[jeepney], notes: " QR scan. " })

      expect(errors).to be_empty
      expect(clean.first).to include("name" => "MariBank", "color_hex" => "#FF5722", "notes" => "QR scan.")
    end

    it "rejects a new payment method ID that is not lowercase snake case" do
      fields = %w[MariBank mari-bank _bank].map do |id|
        errors_for({ type: "payment_method_add", payment_method_id: id, name: "Bank" }).first[:field]
      end

      expect(fields).to eq(%w[payment_method_id] * 3)
    end

    it "rejects a null color, repeated modes, and an update with no field" do
      errors = errors_for({ type: "payment_method_update", payment_method_id: "cash", color_hex: nil },
                          { type: "payment_method_update", payment_method_id: "cash", accepted_by_modes: %w[bus bus] },
                          { type: "payment_method_update", payment_method_id: "cash" })

      expect(errors.map { |e| [e[:index], e[:field]] }).to eq([[0, "color_hex"], [1, "accepted_by_modes"], [2, nil]])
    end

    it "rejects an empty payment list for a line and for a mode default" do
      errors = errors_for({ type: "line_payments", line_id: "MRT3", accepted_payments: [] },
                          { type: "mode_default_payments", mode_id: "train", accepted_payments: [] })

      expect(errors.pluck(:field)).to eq(%w[accepted_payments accepted_payments])
    end
  end

  describe "service area fields" do
    let(:ring) { [{ lat: 14.5, lng: 121.0 }, { lat: 14.5, lng: 121.02 }, { lat: 14.52, lng: 121.01 }] }
    let(:terminal) { { name: " Gate ", lat: 14.51, lng: 121.01 } }
    let(:add) do
      { type: "service_area_add", line_id: "SAPB_Z", name: "Zone", mode: "tricycle", boundary: ring,
        terminals: [terminal], base_fare: 15, base_km: 1, fare_per_km: 5, accepted_payments: %w[cash],
        open: "05:00", close: "21:00" }
    end

    it "cleans a valid add" do
      clean, errors = validate(add.merge(special_trip_fare: nil, detour_factor: 1))

      expect(errors).to be_empty
      expect(clean.first).to include("boundary" => ring.map(&:stringify_keys), "special_trip_fare" => nil,
                                     "terminals" => [{ "name" => "Gate", "lat" => 14.51, "lng" => 121.01 }])
    end

    it "rejects a boundary with too few points or a bad coordinate" do
      few = errors_for(add.merge(boundary: ring.first(2)))
      bad = errors_for(add.merge(boundary: ring.first(2) + [{ lat: 95, lng: 121 }]))

      expect([few, bad].map { |e| e.first[:field] }).to eq(%w[boundary boundary])
    end

    it "rejects a terminal list that is empty, too long, or has an unknown key" do
      fields = [[], Array.new(21) { terminal }, [terminal.merge(color: "red")], [terminal.merge(lat: "x")]].map do |list|
        errors_for(add.merge(terminals: list)).first[:field]
      end

      expect(fields).to eq(%w[terminals] * 4)
    end

    it "keeps a short name in a terminal and rejects an empty one" do
      clean, = validate(add.merge(terminals: [terminal.merge(short_name: "GT")]))

      expect(clean.first["terminals"].first["short_name"]).to eq("GT")
      expect(errors_for(add.merge(terminals: [terminal.merge(short_name: "")])).first[:field]).to eq("terminals")
    end

    it "rejects payment IDs that are empty, repeated, or not text" do
      fields = [[], %w[cash cash], [1]].map { |ids| errors_for(add.merge(accepted_payments: ids)).first[:field] }

      expect(fields).to eq(%w[accepted_payments] * 3)
    end

    it "rejects a detour factor below 1 and a negative special trip fare" do
      errors = errors_for(add.merge(detour_factor: 0.5, special_trip_fare: -1))

      expect(errors.pluck(:field)).to contain_exactly("detour_factor", "special_trip_fare")
    end

    it "needs one timing value and accepts a null special trip fare in a fare change" do
      expect(errors_for({ type: "service_area_timing", line_id: "L" }).first[:message]).to include("at least one")
      expect(errors_for({ type: "service_area_fare", line_id: "L", base_fare: 1, base_km: 1, fare_per_km: 1,
                          special_trip_fare: nil })).to be_empty
    end
  end
end
