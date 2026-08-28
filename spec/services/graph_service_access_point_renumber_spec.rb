require "rails_helper"

# station_access_points.station_id carries a DB-level FK to stations.station_id
# (ON DELETE CASCADE, no ON UPDATE CASCADE). insert_stop/remove_stop renumber
# stations by rewriting their primary key in place, so any renumbered station
# with a surveyed access point must have its access points renamed in the same
# transaction, or the renumbering UPDATE trips the FK constraint.
RSpec.describe "GraphService renumbering carries station_access_points along" do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }
  end

  let(:stops) do
    (1..4).map { |i| { "name" => "S#{i}", "lat" => 14.20 + i * 0.01, "lng" => 121.0 } }
  end

  after { GraphService.delete_route("KANAN") }

  it "renames the access point's station_id instead of violating the FK" do
    result = GraphService.add_route({
      "displayName" => "Test", "lineID" => "KANAN", "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [{ "stops" => stops }]
    })
    raise "fixture failed: #{result.errors.inspect}" unless result.success?

    StationAccessPoint.create!(
      access_point_id: "KANAN_STOP3_AP1", station_id: "KANAN_STOP3",
      name: "Gate 1", kind: "both", lat: 14.23, lng: 121.0
    )

    insert_result = GraphService.insert_stop(
      "referenceStationId" => "KANAN_STOP2", "position" => "after",
      "name" => "New", "lat" => 14.235, "lng" => 121.0
    )
    expect(insert_result.success?).to be true
    expect(StationAccessPoint.find_by(access_point_id: "KANAN_STOP3_AP1").station_id).to eq("KANAN_STOP4")

    remove_result = GraphService.remove_stop("KANAN_STOP2")
    expect(remove_result.success?).to be true
    expect(StationAccessPoint.find_by(access_point_id: "KANAN_STOP3_AP1").station_id).to eq("KANAN_STOP3")
  end
end
