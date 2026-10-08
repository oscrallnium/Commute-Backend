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

    # Order on save is A, B, C, D. Put the whole road on the closing edge B -> A, as the
    # broken recording did, and move B to the end so the stored order is A, C, D, B.
    Edge.where(line: "RESLICE").delete_all
    { "RESLICE_S1" => 1, "RESLICE_S3" => 2, "RESLICE_S4" => 3, "RESLICE_S2" => 4 }.each do |id, sequence|
      Station.find(id).update!(sequence: sequence)
    end
    template = { mode: "jeepney", line: "RESLICE", travel_time_minutes: 2, distance_km: 1, bidirectional: false }
    [%w[S1 S3], %w[S3 S4], %w[S4 S2]].each do |from, to|
      Edge.create!(template.merge(edge_id: "RESLICE_#{from}__RESLICE_#{to}",
                                  from_station: "RESLICE_#{from}", to_station: "RESLICE_#{to}"))
    end
    Edge.create!(template.merge(edge_id: "RESLICE_S2__RESLICE_S1", from_station: "RESLICE_S2",
                                to_station: "RESLICE_S1", polyline_coordinates: road))
  end

  after { GraphService.delete_route("RESLICE") }

  def names(ids) = ids.map { |id| Station.find(id).name }

  it "sets the sequence and gives each edge its own part of the road" do
    order = %w[RESLICE_S1 RESLICE_S2 RESLICE_S3 RESLICE_S4] # A, B, C, D
    reslicer = described_class.new(prefix: "RESLICE", order: order, source_edge_id: "RESLICE_S4__RESLICE_S2")
    expect { reslicer.plan }.to raise_error(ArgumentError) # not the closing edge

    reslicer = described_class.new(prefix: "RESLICE", order: order, source_edge_id: "RESLICE_S2__RESLICE_S1")
    reslicer.apply!(reslicer.plan)

    expect(Station.where(line: "RESLICE").pluck(:station_id)).to match_array(order)
    expect(names(Station.where(line: "RESLICE").order(:sequence).pluck(:station_id))).to eq(%w[A B C D])
    edges = order.each_cons(2).to_a.push([order.last, order.first]).map do |from, to|
      Edge.find("#{from}__#{to}")
    end
    expect(edges.map { |e| names([e.from_station, e.to_station]) }).to eq([%w[A B], %w[B C], %w[C D], %w[D A]])
    expect(edges.map { |e| e.polyline_coordinates.length }).to eq([2, 41, 41, 2])
    expect(edges.map(&:is_road_snapped)).to eq([false, true, true, true])
    expect(edges.sum(&:distance_km).to_f).to be_within(0.02).of(1.94)
  end
end
