require "rails_helper"

# A closed loop stores n stops and n edges. The closing edge runs from the last stop to the first.
RSpec.describe "GraphService stop editing on a closed loop" do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }

    result = GraphService.add_route({
      "displayName" => "Loop", "lineID" => "LOOP", "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [{ "bidirectional" => false, "closesLoop" => true, "stops" => stops }]
    })
    raise "fixture failed: #{result.errors.inspect}" unless result.success?
  end

  after { GraphService.delete_route("LOOP") }

  let(:stops) do
    (1..4).map { |i| { "name" => "S#{i}", "lat" => 14.20 + i * 0.01, "lng" => 121.0 } }
  end

  # Edges as [from name, to name] pairs, sorted by the sequence of the from stop.
  def loop_edges
    sequence = Station.where(line: "LOOP").to_h { |st| [st.station_id, st.sequence] }
    names = Station.where(line: "LOOP").to_h { |st| [st.station_id, st.name] }
    Edge.where(line: "LOOP").sort_by { |e| sequence[e.from_station] }
        .map { |e| [names[e.from_station], names[e.to_station]] }
  end

  def travel_order
    Station.where(line: "LOOP").order(:sequence).pluck(:name)
  end

  def insert(ref, position)
    GraphService.insert_stop("referenceStationId" => ref, "position" => position,
                             "name" => "New", "lat" => 14.235, "lng" => 121.0)
  end

  it "splits a mid-chain segment, keeps every other id, and keeps the loop closed" do
    ids_before = Station.where(line: "LOOP").pluck(:station_id)
    edges_before = Edge.where(line: "LOOP").pluck(:edge_id)

    result = insert("LOOP_S2", "after")

    expect(result.success?).to be true
    expect(result.data[:station_id]).to eq("LOOP_S5")
    expect(travel_order).to eq(%w[S1 S2 New S3 S4])
    expect(loop_edges).to eq([%w[S1 S2], %w[S2 New], %w[New S3], %w[S3 S4], %w[S4 S1]])
    expect(Station.where(line: "LOOP").pluck(:station_id)).to include(*ids_before)
    expect(Edge.where(line: "LOOP").pluck(:edge_id)).to include(*(edges_before - ["LOOP_S2__LOOP_S3"]))
    expect(Edge.exists?("LOOP_S2__LOOP_S5")).to be true
    expect(Edge.exists?("LOOP_S5__LOOP_S3")).to be true
  end

  it "splits the closing edge for an insert after the last stop" do
    result = insert("LOOP_S4", "after")
    expect(result.success?).to be true
    expect(result.data[:station_id]).to eq("LOOP_S5")
    expect(travel_order).to eq(%w[S1 S2 S3 S4 New])
    expect(loop_edges).to eq([%w[S1 S2], %w[S2 S3], %w[S3 S4], %w[S4 New], %w[New S1]])
  end

  it "treats an insert before the first stop as a split of the closing edge" do
    result = insert("LOOP_S1", "before")
    expect(result.success?).to be true
    expect(result.data[:station_id]).to eq("LOOP_S5")
    expect(travel_order).to eq(%w[S1 S2 S3 S4 New])
    expect(loop_edges).to include(%w[New S1])
    expect(loop_edges.size).to eq(5)
  end

  it "merges across the removed stop and keeps every other id" do
    expect(GraphService.remove_stop("LOOP_S2").success?).to be true
    expect(Station.where(line: "LOOP").pluck(:station_id)).to match_array(%w[LOOP_S1 LOOP_S3 LOOP_S4])
    expect(Station.where(line: "LOOP").order(:sequence).pluck(:sequence)).to eq([1, 2, 3])
    expect(travel_order).to eq(%w[S1 S3 S4])
    expect(loop_edges).to eq([%w[S1 S3], %w[S3 S4], %w[S4 S1]])
    expect(Edge.exists?("LOOP_S1__LOOP_S3")).to be true
  end

  it "merges into a new closing edge when the last stop is removed" do
    expect(GraphService.remove_stop("LOOP_S4").success?).to be true
    expect(travel_order).to eq(%w[S1 S2 S3])
    expect(loop_edges).to eq([%w[S1 S2], %w[S2 S3], %w[S3 S1]])
  end

  it "merges into a new closing edge when the first stop is removed" do
    expect(GraphService.remove_stop("LOOP_S1").success?).to be true
    expect(Station.where(line: "LOOP").pluck(:name)).to match_array(%w[S2 S3 S4])
    expect(Station.find("LOOP_S2").sequence).to eq(1)
    expect(travel_order).to eq(%w[S2 S3 S4])
    expect(loop_edges).to eq([%w[S2 S3], %w[S3 S4], %w[S4 S2]])
  end
end
