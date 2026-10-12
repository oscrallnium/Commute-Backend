# A small graph for the ops publish specs: a road line, a rail line, one transfer, and an empty line.
# Every ID starts with OPST so the specs can run on a database that already holds a graph.
module OpsGraphFixture
  def build_ops_graph!
    GraphMeta.first || GraphMeta.create!
    { "bus" => "bus", "train" => "train", "walk" => "walking" }.each do |id, mk|
      TransportMode.find_or_create_by!(id: id) do |m|
        m.display_name = id.capitalize
        m.mk_directions_type = mk
      end
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }
    Line.find_or_create_by!(id: "INTERCHANGE") do |l|
      l.display_name = "Interchange"
      l.mode = "walk"
    end

    build_line!("OPST_ROAD", "bus", %w[OPST_ROAD_S1 OPST_ROAD_S2 OPST_ROAD_S3], bidirectional: false)
    build_line!("OPST_RAIL", "train", %w[OPST_RAIL_A OPST_RAIL_B OPST_RAIL_C], bidirectional: true)
    Line.create!(id: "OPST_EMPTY", display_name: "Empty", mode: "bus")
    TransportMode.where(id: "bus").update_all(["lines = array_append(lines, ?)", "OPST_EMPTY"])
    FareMatrix.create!(line_name: "OPST_EMPTY", type: "flat_with_distance", data: { "brackets" => [] })
    FareMatrix.create!(line_name: "OPST_RAIL", type: "flat_with_distance",
                       data: { "type" => "flat_with_distance", "brackets" => [{ "fare" => 13, "maxStations" => 4 }],
                               "maximumFare" => 13, "minimumFare" => 13 })
    Edge.create!(ops_edge_attrs("X__OPST_ROAD_S2__OPST_RAIL_B", "OPST_ROAD_S2", "OPST_RAIL_B", "INTERCHANGE", "walk",
                                bidirectional: true))
    Station.where(station_id: %w[OPST_ROAD_S2 OPST_RAIL_B]).update_all(is_interchange: true)
  end

  def build_line!(line_id, mode, station_ids, bidirectional:)
    Line.create!(id: line_id, display_name: line_id.titleize, mode: mode)
    station_ids.each_with_index do |id, i|
      Station.create!(station_id: id, name: id.titleize.to_s, short_name: id[-2..], line: line_id, type: mode,
                      lat: 14.5 + (i * 0.01), lng: 121.0, sequence: i + 1)
    end
    station_ids.each_cons(2) do |from, to|
      Edge.create!(ops_edge_attrs("#{from}__#{to}", from, to, line_id, mode, bidirectional: bidirectional))
    end
  end

  def ops_edge_attrs(id, from, to, line, mode, bidirectional:)
    { edge_id: id, from_station: from, to_station: to, line: line, mode: mode, travel_time_minutes: 3,
      distance_km: 1.1, base_fare: 13, fare_per_km: 1.8, accepted_payments: ["cash"], bidirectional: bidirectional,
      polyline_coordinates: [{ "lat" => 14.5, "lng" => 121.0 }, { "lat" => 14.51, "lng" => 121.0 }] }
  end

  def admin_user
    @admin_user ||= User.create!(email: "ops_admin_#{SecureRandom.hex(4)}@test.com", password: "Password1!",
                                 display_name: "Ops Admin", role: :admin)
  end

  def rider_user
    @rider_user ||= User.create!(email: "ops_rider_#{SecureRandom.hex(4)}@test.com", password: "Password1!",
                                 display_name: "Rider")
  end

  def graph_version_now
    GraphMeta.first!.version
  end
end

RSpec.configure do |config|
  config.include OpsGraphFixture
end
