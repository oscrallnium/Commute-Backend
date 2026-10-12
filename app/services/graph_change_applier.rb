# Writes one clean publish change. It runs inside the publish transaction and does not raise the
# graph version. It raises Rejected when a referenced row is missing or a rule refuses the change.
class GraphChangeApplier
  class Rejected < StandardError
    attr_reader :field

    def initialize(message, field: nil)
      super(message)
      @field = field
    end
  end

  # Line changes that the reserved INTERCHANGE line refuses.
  INTERCHANGE_LOCKED_TYPES = %w[line_direction line_enabled line_road_fare line_rail_fares line_delete].freeze
  NO_ROAD_FARE_MODES       = %w[train walk].freeze

  # Returns the ID of the row that an add change creates, or nil.
  def apply(change)
    send("apply_#{change["type"]}", change)
  rescue ActiveRecord::RecordInvalid => e
    raise Rejected, e.record.errors.full_messages.to_sentence
  end

  private

  # ── Lines ──

  def apply_line_name(c)  = line_for(c).update!(display_name: c["name"]) && nil
  def apply_line_color(c) = line_for(c).update!(color_hex: c["color_hex"]) && nil

  def apply_line_enabled(c)
    line_for(c).update!(enabled: c["enabled"], disabled_reason: c["reason"])
    nil
  end

  # The line direction also sets `bidirectional` on every edge of the line.
  def apply_line_direction(c)
    line = line_for(c)
    both = c["direction"] == "both"
    if both && Edge.where(line: line.id).where.not(direction: nil).exists?
      raise Rejected.new("Line '#{line.id}' has edges with a compass direction. Those edges cannot run both ways.",
                         field: "direction")
    end
    line.update!(direction: c["direction"])
    Edge.where(line: line.id).update_all(bidirectional: both, updated_at: Time.current)
    nil
  end

  def apply_line_road_fare(c)
    line = line_for(c)
    if NO_ROAD_FARE_MODES.include?(line.mode)
      raise Rejected.new("Line '#{line.id}' is a #{line.mode} line. It has no road fare.", field: "line_id")
    end

    edges = Edge.where(line: line.id)
    raise Rejected.new("Line '#{line.id}' has no edges to carry the fare.", field: "line_id") unless edges.exists?

    edges.update_all(base_fare: c["base_fare"], fare_per_km: c["fare_per_km"], updated_at: Time.current)
    line.update!(base_km: c["base_km"])
    nil
  end

  def apply_line_rail_fares(c)
    line = line_for(c)
    raise Rejected.new("Line '#{line.id}' is not a train line.", field: "line_id") unless line.mode == "train"

    on_line = Station.where(line: line.id, station_id: c["station_ids"]).pluck(:station_id)
    missing = c["station_ids"] - on_line
    raise Rejected.new("These stops are not on line '#{line.id}': #{missing.join(", ")}.", field: "station_ids") if missing.any?

    table = RailFareTable.find_or_initialize_by(line_id: line.id)
    table.update!(station_ids: c["station_ids"], fares: c["fares"])
    nil
  end

  def apply_line_delete(c)
    line_for(c)
    LineDeletion.delete!(c["line_id"])
    nil
  rescue LineDeletion::Error => e
    raise Rejected.new(e.message, field: "line_id")
  end

  def line_for(c)
    line = Line.find_by(id: c["line_id"])
    raise Rejected.new("Line '#{c["line_id"]}' was not found.", field: "line_id") unless line
    if line.id == Line::INTERCHANGE_ID && INTERCHANGE_LOCKED_TYPES.include?(c["type"])
      raise Rejected.new("INTERCHANGE is a reserved line. It does not accept #{c["type"]}.", field: "line_id")
    end

    line
  end

  # ── Stops ──

  def apply_stop_name(c)       = stop_for(c).update!(name: c["name"]) && nil
  def apply_stop_short_name(c) = stop_for(c).update!(short_name: c["short_name"]) && nil
  def apply_stop_boarding(c)   = stop_for(c).update!(boarding: c["boarding"]) && nil
  def apply_stop_hours(c)      = stop_for(c).update!(open_time: c["open"], close_time: c["close"]) && nil

  def apply_stop_enabled(c)
    stop_for(c).update!(enabled: c["enabled"], disabled_reason: c["reason"])
    nil
  end

  def stop_for(c, field: "station_id")
    Station.find_by(station_id: c[field]) ||
      raise(Rejected.new("Stop '#{c[field]}' was not found.", field: field))
  end

  # ── Edges ──

  def apply_edge_travel_time(c) = edge_for(c).update!(travel_time_minutes: c["travel_time_minutes"]) && nil
  def apply_edge_distance(c)    = edge_for(c).update!(distance_km: c["distance_km"]) && nil

  def apply_edge_enabled(c)
    edge_for(c).update!(enabled: c["enabled"], disabled_reason: c["reason"])
    nil
  end

  def edge_for(c)
    Edge.find_by(edge_id: c["edge_id"]) || raise(Rejected.new("Edge '#{c["edge_id"]}' was not found.", field: "edge_id"))
  end

  # ── Access points ──

  def apply_access_point_add(c)
    stop = stop_for(c)
    id = c["access_point_id"] || generated_access_point_id(stop.station_id)
    raise Rejected.new("Access point '#{id}' already exists.", field: "access_point_id") if StationAccessPoint.exists?(id)

    StationAccessPoint.create!(
      access_point_id: id, station_id: stop.station_id, name: c.fetch("name", ""), kind: c["kind"],
      direction: c["direction"], lat: c["lat"], lng: c["lng"],
      position: (stop.access_points.maximum(:position) || -1) + 1
    )
    id
  end

  def apply_access_point_update(c)
    point = access_point_for(c)
    point.update!(c.slice("name", "kind", "direction", "lat", "lng"))
    nil
  end

  def apply_access_point_delete(c)
    access_point_for(c).delete
    nil
  end

  def access_point_for(c)
    StationAccessPoint.find_by(access_point_id: c["access_point_id"]) ||
      raise(Rejected.new("Access point '#{c["access_point_id"]}' was not found.", field: "access_point_id"))
  end

  # A legacy stop ID can hold a dot or a hyphen, so the generated ID replaces them with an underscore.
  def generated_access_point_id(station_id)
    base = station_id.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    "#{base}_AP_#{SecureRandom.hex(4).upcase}"
  end

  # ── Transfers ──

  def apply_transfer_add(c)
    from = stop_for(c, field: "from_station_id")
    to   = stop_for(c, field: "to_station_id")
    edge_id = "X__#{from.station_id}__#{to.station_id}"
    if transfer_between?(from.station_id, to.station_id)
      raise Rejected.new("A transfer between '#{from.station_id}' and '#{to.station_id}' already exists.", field: "to_station_id")
    end

    Edge.create!(transfer_attrs(c, edge_id: edge_id, from: from.station_id, to: to.station_id))
    Station.where(station_id: [from.station_id, to.station_id]).update_all(is_interchange: true, updated_at: Time.current)
    edge_id
  end

  def apply_transfer_update(c)
    edge = transfer_for(c)
    attrs = c.slice("travel_time_minutes", "distance_km")
    attrs["polyline_coordinates"] = c["polyline"] if c.key?("polyline")
    edge.update!(attrs)
    nil
  end

  def apply_transfer_delete(c)
    edge = transfer_for(c)
    edge.delete
    [edge.from_station, edge.to_station].each { |id| refresh_interchange_flag(id) }
    nil
  end

  def transfer_for(c)
    edge = edge_for(c)
    return edge if edge.line == Line::INTERCHANGE_ID

    raise Rejected.new("Edge '#{edge.edge_id}' is on line '#{edge.line}', not INTERCHANGE.", field: "edge_id")
  end

  def transfer_between?(a, b)
    Edge.where(line: Line::INTERCHANGE_ID)
        .where(from_station: a, to_station: b).or(Edge.where(line: Line::INTERCHANGE_ID, from_station: b, to_station: a))
        .exists?
  end

  def transfer_attrs(c, edge_id:, from:, to:)
    {
      edge_id: edge_id, from_station: from, to_station: to, mode: "walk", line: Line::INTERCHANGE_ID,
      travel_time_minutes: c["travel_time_minutes"], distance_km: c["distance_km"],
      base_fare: 0, fare_per_km: 0, accepted_payments: PaymentMethod.order(:id).pluck(:id),
      is_air_conditioned: false, crowd_factor: 0.8, reliability: 1.0,
      bidirectional: c.fetch("bidirectional", true), direction: nil,
      polyline_coordinates: c["polyline"], mk_directions_transport_type: "walking", is_road_snapped: false
    }
  end

  def refresh_interchange_flag(station_id)
    linked = Edge.where(line: Line::INTERCHANGE_ID).exists?(["from_station = :id OR to_station = :id", id: station_id])
    Station.where(station_id: station_id).update_all(is_interchange: linked, updated_at: Time.current)
  end
end
