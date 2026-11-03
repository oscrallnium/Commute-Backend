require "rails_helper"

RSpec.describe ServiceArea do
  let(:square) do
    [{ "lat" => 0.0, "lng" => 0.0 }, { "lat" => 0.0, "lng" => 4.0 },
     { "lat" => 4.0, "lng" => 4.0 }, { "lat" => 4.0, "lng" => 0.0 }]
  end

  before do
    Line.find_or_create_by!(id: "SAST_ZONE") do |l|
      l.display_name = "Zone"
      l.mode = "tricycle"
    end
  end

  def build_zone(boundary: square, **attrs)
    ServiceArea.new({ line_id: "SAST_ZONE", boundary: boundary, accepted_payments: %w[cash] }.merge(attrs))
  end

  it "is valid with a simple ring" do
    expect(build_zone).to be_valid
  end

  it "accepts symbol keys and drops a closing point" do
    ring = square.map { |p| p.symbolize_keys } + [{ lat: 0.0, lng: 0.0 }]
    zone = build_zone(boundary: ring)
    expect(zone).to be_valid
    expect(zone.boundary).to eq(square)
  end

  it "rejects too few vertices" do
    zone = build_zone(boundary: square.first(2))
    expect(zone).not_to be_valid
    expect(zone.errors[:boundary].join).to include("at least 3")
  end

  it "rejects too many vertices" do
    ring = Array.new(201) { |i| { "lat" => 10 + Math.sin(i * 0.03), "lng" => 120 + Math.cos(i * 0.03) } }
    zone = build_zone(boundary: ring)
    expect(zone).not_to be_valid
    expect(zone.errors[:boundary].join).to include("at most 200")
  end

  it "rejects a bow tie" do
    bow = [{ "lat" => 0, "lng" => 0 }, { "lat" => 4, "lng" => 4 },
           { "lat" => 0, "lng" => 4 }, { "lat" => 4, "lng" => 0 }]
    zone = build_zone(boundary: bow)
    expect(zone).not_to be_valid
    expect(zone.errors[:boundary].join).to include("cross itself")
  end

  it "rejects out-of-range coordinates" do
    ring = square.map(&:dup)
    ring[0]["lat"] = 91.0
    expect(build_zone(boundary: ring)).not_to be_valid
  end

  it "rejects consecutive equal points" do
    ring = [square[0], square[1], square[1], square[2], square[3]]
    expect(build_zone(boundary: ring)).not_to be_valid
  end

  it "rejects empty accepted payments" do
    expect(build_zone(accepted_payments: [])).not_to be_valid
  end

  it "rejects a detour factor below 1" do
    expect(build_zone(detour_factor: 0.5)).not_to be_valid
  end

  describe "#contains?" do
    it "finds a point inside and outside a square" do
      zone = build_zone
      expect(zone.contains?(2.0, 2.0)).to be true
      expect(zone.contains?(5.0, 2.0)).to be false
      expect(zone.contains?(2.0, -1.0)).to be false
    end

    it "handles a concave ring" do
      ring = [{ "lat" => 0.0, "lng" => 0.0 }, { "lat" => 0.0, "lng" => 6.0 },
              { "lat" => 6.0, "lng" => 6.0 }, { "lat" => 6.0, "lng" => 4.0 },
              { "lat" => 2.0, "lng" => 4.0 }, { "lat" => 2.0, "lng" => 2.0 },
              { "lat" => 6.0, "lng" => 2.0 }, { "lat" => 6.0, "lng" => 0.0 }]
      zone = build_zone(boundary: ring)
      expect(zone).to be_valid
      expect(zone.contains?(4.0, 3.0)).to be false
      expect(zone.contains?(1.0, 3.0)).to be true
      expect(zone.contains?(4.0, 1.0)).to be true
    end
  end

  describe "#as_graph_json" do
    it "returns camelCase fields and omits specialTripFare when nil" do
      json = build_zone(base_fare: 20, speed_kmh: 15).as_graph_json(terminal_ids: %w[SAST_T1])
      expect(json).to include(line: "SAST_ZONE", terminalIds: %w[SAST_T1], baseFare: 20.0,
                              speedKmh: 15.0, acceptedPayments: %w[cash])
      expect(json[:boundary].first).to eq(lat: 0.0, lng: 0.0)
      expect(json).not_to have_key(:specialTripFare)
    end

    it "includes specialTripFare when set" do
      json = build_zone(special_trip_fare: 80).as_graph_json(terminal_ids: [])
      expect(json[:specialTripFare]).to eq(80.0)
    end
  end

  it "persists and cascades with the line" do
    build_zone.save!
    expect(Line.find("SAST_ZONE").service_area).to be_present
  end
end
