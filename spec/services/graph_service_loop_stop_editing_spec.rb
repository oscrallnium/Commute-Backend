require "rails_helper"

# A closed loop stores STOP1..STOP<n> and n edges; SEG<n> is the closing edge STOP<n> -> STOP1.
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

  def chain
    Edge.where(line: "LOOP").to_h { |e| [e.edge_id, [e.from_station, e.to_station]] }
  end

  def insert(ref, position)
    GraphService.insert_stop("referenceStationId" => ref, "position" => position,
                             "name" => "New", "lat" => 14.235, "lng" => 121.0)
  end

  it "splits a mid-chain segment and shifts the closing edge" do
    result = insert("LOOP_STOP2", "after")
    expect(result.success?).to be true
    expect(result.data[:station_id]).to eq("LOOP_STOP3")
    expect(chain).to eq(
      "LOOP_SEG1" => %w[LOOP_STOP1 LOOP_STOP2],
      "LOOP_SEG2" => %w[LOOP_STOP2 LOOP_STOP3],
      "LOOP_SEG3" => %w[LOOP_STOP3 LOOP_STOP4],
      "LOOP_SEG4" => %w[LOOP_STOP4 LOOP_STOP5],
      "LOOP_SEG5" => %w[LOOP_STOP5 LOOP_STOP1]
    )
  end

  it "splits the closing edge for an insert after the last stop" do
    result = insert("LOOP_STOP4", "after")
    expect(result.success?).to be true
    expect(result.data[:station_id]).to eq("LOOP_STOP5")
    expect(chain).to include(
      "LOOP_SEG4" => %w[LOOP_STOP4 LOOP_STOP5],
      "LOOP_SEG5" => %w[LOOP_STOP5 LOOP_STOP1]
    )
    expect(chain.size).to eq(5)
  end

  it "treats an insert before the first stop as a split of the closing edge" do
    result = insert("LOOP_STOP1", "before")
    expect(result.success?).to be true
    expect(result.data[:station_id]).to eq("LOOP_STOP5")
    expect(chain).to include("LOOP_SEG5" => %w[LOOP_STOP5 LOOP_STOP1])
    expect(chain.size).to eq(5)
  end

  it "merges across the removed stop and shifts the closing edge" do
    expect(GraphService.remove_stop("LOOP_STOP2").success?).to be true
    expect(chain).to eq(
      "LOOP_SEG1" => %w[LOOP_STOP1 LOOP_STOP2],
      "LOOP_SEG2" => %w[LOOP_STOP2 LOOP_STOP3],
      "LOOP_SEG3" => %w[LOOP_STOP3 LOOP_STOP1]
    )
  end

  it "merges into a new closing edge when the last stop is removed" do
    expect(GraphService.remove_stop("LOOP_STOP4").success?).to be true
    expect(chain).to eq(
      "LOOP_SEG1" => %w[LOOP_STOP1 LOOP_STOP2],
      "LOOP_SEG2" => %w[LOOP_STOP2 LOOP_STOP3],
      "LOOP_SEG3" => %w[LOOP_STOP3 LOOP_STOP1]
    )
  end

  it "merges into a new closing edge when the first stop is removed" do
    expect(GraphService.remove_stop("LOOP_STOP1").success?).to be true
    expect(Station.where(line: "LOOP").pluck(:name).sort).to eq(%w[S2 S3 S4])
    expect(Station.find_by(station_id: "LOOP_STOP1").name).to eq("S2")
    expect(chain).to eq(
      "LOOP_SEG1" => %w[LOOP_STOP1 LOOP_STOP2],
      "LOOP_SEG2" => %w[LOOP_STOP2 LOOP_STOP3],
      "LOOP_SEG3" => %w[LOOP_STOP3 LOOP_STOP1]
    )
  end
end
