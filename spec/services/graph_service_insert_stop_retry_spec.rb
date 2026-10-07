require "rails_helper"

# The client can lose the response to a successful insert and send the same request again.
RSpec.describe "GraphService#insert_stop retry" do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }

    stops = (1..4).map { |i| { "name" => "S#{i}", "lat" => 14.20 + i * 0.01, "lng" => 121.0 } }
    result = GraphService.add_route({
      "displayName" => "Retry", "lineID" => "RETRY", "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [{ "bidirectional" => false, "stops" => stops }]
    })
    raise "fixture failed: #{result.errors.inspect}" unless result.success?
  end

  after { GraphService.delete_route("RETRY") }

  let(:payload) do
    { "referenceStationId" => "RETRY_STOP2", "position" => "after",
      "name" => "New", "lat" => 14.235, "lng" => 121.0 }
  end

  it "returns the stop that the first request added instead of adding a second one" do
    first = GraphService.insert_stop(payload)
    second = GraphService.insert_stop(payload.merge("referenceStationId" => "RETRY_STOP2"))

    expect(first.success?).to be true
    expect(second.success?).to be true
    expect(second.data[:station_id]).to eq(first.data[:station_id])
    expect(Station.where(line: "RETRY").count).to eq(5)
    expect(Edge.where(line: "RETRY").count).to eq(4)
  end

  it "adds a stop with a different name at the same place" do
    GraphService.insert_stop(payload)
    result = GraphService.insert_stop(payload.merge("name" => "Other"))

    expect(result.success?).to be true
    expect(Station.where(line: "RETRY").count).to eq(6)
  end
end
