require "rails_helper"

# A loop whose closing edge holds the geometry for every stop, as the Loop Creator saved it
# when all stops snapped to the end of the recording.
RSpec.describe LoopReslicer do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }

    # Four stops along one street; the recorded road runs B -> C -> D -> A.
    lngs = { "A" => 121.000, "B" => 121.001, "C" => 121.005, "D" => 121.009 }
    stops = lngs.map { |name, lng| { "name" => name, "lat" => 14.5, "lng" => lng } }
    road = (0..80).map { |i| { "lat" => 14.5, "lng" => 121.001 + i * 0.0001 } } +
           [{ "lat" => 14.5, "lng" => 121.000 }]
    result = GraphService.add_route({
      "displayName" => "Loop", "lineID" => "RESLICE", "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [{ "bidirectional" => false, "closesLoop" => true, "stops" => stops }]
    })
    raise "fixture failed: #{result.errors.inspect}" unless result.success?

    # Order on save is A, B, C, D. Put the whole road on the closing edge D -> A, as the
    # broken recording did, and move B to the end so the stored order is A, C, D, B.
    Edge.where(line: "RESLICE").update_all(polyline_coordinates: [])
    Station.find("RESLICE_STOP2").update!(station_id: "RESLICE_TMP")
    %w[3 4].each { |i| Station.find("RESLICE_STOP#{i}").update!(station_id: "RESLICE_STOP#{i.to_i - 1}") }
    Station.find("RESLICE_TMP").update!(station_id: "RESLICE_STOP4")
    Edge.where(line: "RESLICE").delete_all
    template = { mode: "jeepney", line: "RESLICE", travel_time_minutes: 2, distance_km: 1, bidirectional: false }
    Edge.create!(template.merge(edge_id: "RESLICE_SEG1", from_station: "RESLICE_STOP1", to_station: "RESLICE_STOP2"))
    Edge.create!(template.merge(edge_id: "RESLICE_SEG2", from_station: "RESLICE_STOP2", to_station: "RESLICE_STOP3"))
    Edge.create!(template.merge(edge_id: "RESLICE_SEG3", from_station: "RESLICE_STOP3", to_station: "RESLICE_STOP4"))
    Edge.create!(template.merge(edge_id: "RESLICE_SEG4", from_station: "RESLICE_STOP4", to_station: "RESLICE_STOP1",
                                polyline_coordinates: road))
  end

  after { GraphService.delete_route("RESLICE") }

  def names(ids) = ids.map { |id| Station.find(id).name }

  it "renumbers the stops and gives each edge its own part of the road" do
    order = %w[RESLICE_STOP1 RESLICE_STOP4 RESLICE_STOP2 RESLICE_STOP3] # A, B, C, D
    reslicer = described_class.new(prefix: "RESLICE", order: order, source_edge_id: "RESLICE_SEG3")
    expect { reslicer.plan }.to raise_error(ArgumentError) # SEG3 is not the closing edge

    reslicer = described_class.new(prefix: "RESLICE", order: order, source_edge_id: "RESLICE_SEG4")
    reslicer.apply!(reslicer.plan)

    expect(names((1..4).map { |i| "RESLICE_STOP#{i}" })).to eq(%w[A B C D])
    edges = (1..4).map { |i| Edge.find("RESLICE_SEG#{i}") }
    expect(edges.map { |e| names([e.from_station, e.to_station]) }).to eq([%w[A B], %w[B C], %w[C D], %w[D A]])
    expect(edges.map { |e| e.polyline_coordinates.length }).to eq([2, 41, 41, 2])
    expect(edges.map(&:is_road_snapped)).to eq([false, true, true, true])
    expect(edges.sum(&:distance_km).to_f).to be_within(0.02).of(1.94)
  end
end
