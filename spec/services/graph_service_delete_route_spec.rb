require "rails_helper"

RSpec.describe "GraphService#delete_route" do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }

    %w[KEEP DROP].each_with_index do |line, n|
      stops = (1..3).map { |i| { "name" => "#{line} #{i}", "lat" => 14.20 + i * 0.01, "lng" => 121.0 + n * 0.001 } }
      result = GraphService.add_route({
        "displayName" => line, "lineID" => line, "mode" => "jeepney",
        "openTime" => "05:00", "closeTime" => "22:00",
        "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
        "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
        "passes" => [{ "bidirectional" => false, "stops" => stops }]
      })
      raise "fixture failed: #{result.errors.inspect}" unless result.success?
    end
    Edge.create!(edge_id: "E_INTERCHANGE_KEEP_DROP", from_station: "KEEP_S2", to_station: "DROP_S2",
                 mode: "jeepney", line: "INTERCHANGE", travel_time_minutes: 5, distance_km: 0.1)
  end

  after { %w[KEEP DROP].each { |l| GraphService.delete_route(l) } }

  it "removes the interchange edges that point at the deleted stations" do
    result = GraphService.delete_route("DROP")

    expect(result.success?).to be true
    expect(Edge.exists?("E_INTERCHANGE_KEEP_DROP")).to be false
    expect(Edge.where(line: "KEEP").count).to eq(2)
  end
end
