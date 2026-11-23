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
  INTERCHANGE_LOCKED_TYPES = %w[line_direction line_enabled line_road_fare line_rail_fares line_payments
                                line_delete line_toll_load_factor].freeze
  NO_ROAD_FARE_MODES       = %w[train walk].freeze
  NO_TOLL_MODES            = %w[train walk].freeze
  PAYMENT_METHOD_FIELDS    = %w[name sf_symbol color_hex is_default accepted_by_modes notes].freeze

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

  # The line direction also sets `bidirectional` on every edge of the line. `both` also clears the
  # compass `direction` of every edge, so it refuses a line that has two compass directions or
  # schedule rows for one direction. See check_both_ways!.
  def apply_line_direction(c)
    line = line_for(c)
    refuse_service_area!(line, "It has no direction.")
    both = c["direction"] == "both"
    check_both_ways!(line) if both
    line.update!(direction: c["direction"])
    attrs = { bidirectional: both, updated_at: Time.current }
    attrs[:direction] = nil if both
    Edge.where(line: line.id).update_all(attrs)
    nil
  end

  # Two compass directions are two separate chains: two-way edges on both make duplicate routes.
  # A schedule row for one direction matches no edge after the clear, so it must go first.
  def check_both_ways!(line)
    compass = Edge.where(line: line.id).where.not(direction: nil).distinct.order(:direction).pluck(:direction)
    if compass.size > 1
      raise Rejected.new("Line '#{line.id}' has #{compass.to_sentence} edges. Only a line with one compass " \
                         "direction can run both ways. Delete the edges of the other directions first.",
                         field: "direction")
    end

    scheduled = (ServiceSchedule.where(line_id: line.id).where.not(direction: nil).distinct.pluck(:direction) +
                 ServiceScheduleException.where(line_id: line.id).where.not(direction: nil).distinct.pluck(:direction)).uniq
    return if scheduled.empty?

    raise Rejected.new("Line '#{line.id}' has #{scheduled.sort.to_sentence} schedule rows or exceptions. Clear them, " \
                       "or set them for every direction, before the line runs both ways.", field: "direction")
  end

  def apply_line_road_fare(c)
    line = line_for(c)
    refuse_service_area!(line, "Use service_area_fare.")
    if NO_ROAD_FARE_MODES.include?(line.mode)
      raise Rejected.new("Line '#{line.id}' is a #{line.mode} line. It has no road fare.", field: "line_id")
    end

    edges = Edge.where(line: line.id)
    raise Rejected.new("Line '#{line.id}' has no edges to carry the fare.", field: "line_id") unless edges.exists?

    edges.update_all(base_fare: c["base_fare"], fare_per_km: c["fare_per_km"], updated_at: Time.current)
    line.update!(c.slice("base_km", "fare_step_km", "fare_km_rounding"))
    nil
  end

  # Writes every edge of the line, hidden edges included.
  def apply_line_payments(c)
    line = line_for(c)
    refuse_service_area!(line, "Use service_area_fare.")
    edges = Edge.where(line: line.id)
    raise Rejected.new("Line '#{line.id}' has no edges to carry the payments.", field: "line_id") unless edges.exists?

    known_payments!(c["accepted_payments"])
    edges.update_all(accepted_payments: c["accepted_payments"], updated_at: Time.current)
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

  def apply_line_toll_load_factor(c)
    line = line_for(c)
    refuse_toll_mode!(line.mode, "Line '#{line.id}'", "line_id")
    line.update!(toll_load_factor: c["load_factor"])
    nil
  end

  def apply_toll_matrix(c) = TollMatrixWriter.new.replace(c)

  def apply_line_delete(c)
    line_for(c)
    LineDeletion.delete!(c["line_id"])
    nil
  rescue LineDeletion::Error => e
    raise Rejected.new(e.message, field: "line_id")
  end

  def refuse_service_area!(line, advice)
    return unless line.service_area

    raise Rejected.new("Line '#{line.id}' is a service area. #{advice}", field: "line_id")
  end

  def line_for(c)
    line = Line.find_by(id: c["line_id"])
    raise Rejected.new("Line '#{c["line_id"]}' was not found.", field: "line_id") unless line
    if line.id == Line::INTERCHANGE_ID && INTERCHANGE_LOCKED_TYPES.include?(c["type"])
      raise Rejected.new("INTERCHANGE is a reserved line. It does not accept #{c["type"]}.", field: "line_id")
    end

    line
  end

  # ── Payment methods ──

  # Returns the ID of the new payment method.
  def apply_payment_method_add(c)
    id = c["payment_method_id"]
    raise Rejected.new("Payment method '#{id}' already exists.", field: "payment_method_id") if PaymentMethod.exists?(id)

    PaymentMethod.create!(payment_method_attrs(c).merge(id: id))
    id
  end

  def apply_payment_method_update(c)
    payment_method_for(c).update!(payment_method_attrs(c))
    nil
  end

  # Walks pass every payment filter, so INTERCHANGE edges and always-allowed modes lose the ID
  # without a refusal. Any other row that lists the ID refuses the delete.
  def apply_payment_method_delete(c)
    payment = payment_method_for(c)
    uses = payment_method_uses(payment.id)
    if uses.any?
      raise Rejected.new("Payment method '#{payment.id}' is still in use: #{uses.join("; ")}. Remove it there first.",
                         field: "payment_method_id")
    end

    remove_from_walks!(payment.id)
    payment.delete
    nil
  end

  def apply_mode_default_payments(c)
    mode = TransportMode.find_by(id: c["mode_id"])
    raise Rejected.new("Mode '#{c["mode_id"]}' was not found.", field: "mode_id") unless mode

    known_payments!(c["accepted_payments"])
    mode.update!(default_accepted_payments: c["accepted_payments"])
    nil
  end

  def payment_method_for(c)
    PaymentMethod.find_by(id: c["payment_method_id"]) ||
      raise(Rejected.new("Payment method '#{c["payment_method_id"]}' was not found.", field: "payment_method_id"))
  end

  def payment_method_attrs(c)
    known_modes!(c["accepted_by_modes"]) if c.key?("accepted_by_modes")
    c.slice(*PAYMENT_METHOD_FIELDS).transform_keys { |key| key == "name" ? "display_name" : key }
  end

  # Returns one text part for each kind of row that lists the payment method, outside walks.
  def payment_method_uses(id)
    lines = Edge.where("? = ANY(accepted_payments)", id).where.not(line: Line::INTERCHANGE_ID)
                .distinct.order(:line).pluck(:line)
    areas = ServiceArea.where("? = ANY(accepted_payments)", id).order(:line_id).pluck(:line_id)
    modes = TransportMode.where(is_always_allowed: false).where("? = ANY(default_accepted_payments)", id)
                         .order(:id).pluck(:id)
    { "edges of lines" => lines, "service areas" => areas, "mode defaults" => modes }
      .filter_map { |label, ids| "#{label} #{ids.join(", ")}" if ids.any? }
  end

  def remove_from_walks!(id)
    Edge.where(line: Line::INTERCHANGE_ID).where("? = ANY(accepted_payments)", id)
        .update_all(["accepted_payments = array_remove(accepted_payments, ?), updated_at = ?", id, Time.current])
    TransportMode.where(is_always_allowed: true)
                 .update_all(["default_accepted_payments = array_remove(default_accepted_payments, ?)", id])
  end

  def known_payments!(ids)
    unknown = PaymentMethod.unknown_ids(ids)
    raise Rejected.new("Unknown payment methods: #{unknown.join(", ")}.", field: "accepted_payments") if unknown.any?
  end

  def known_modes!(ids)
    unknown = ids - TransportMode.where(id: ids).pluck(:id)
    raise Rejected.new("Unknown modes: #{unknown.join(", ")}.", field: "accepted_by_modes") if unknown.any?
  end

  # ── Service areas ──

  def apply_service_area_add(c)             = ServiceAreaWriter.new.add(c)
  def apply_service_area_boundary(c)        = ServiceAreaWriter.new.update_boundary(c)
  def apply_service_area_fare(c)            = ServiceAreaWriter.new.update_fare(c)
  def apply_service_area_timing(c)          = ServiceAreaWriter.new.update_timing(c)
  def apply_service_area_terminal_add(c)    = ServiceAreaWriter.new.add_terminal(c)
  def apply_service_area_terminal_delete(c) = ServiceAreaWriter.new.delete_terminal(c)

  # ── Service schedules ──

  def apply_service_schedule_set(c)       = ServiceScheduleWriter.new.set(c)
  def apply_service_schedule_clear(c)     = ServiceScheduleWriter.new.clear(c)
  def apply_service_exception_add(c)      = ServiceScheduleWriter.new.add_exception(c)
  def apply_service_exception_update(c)   = ServiceScheduleWriter.new.update_exception(c)
  def apply_service_exception_delete(c)   = ServiceScheduleWriter.new.delete_exception(c)

  # ── Stops ──

  def apply_stop_name(c)       = stop_for(c).update!(name: c["name"]) && nil
  def apply_stop_short_name(c) = stop_for(c).update!(short_name: c["short_name"]) && nil
  def apply_stop_boarding(c)   = stop_for(c).update!(boarding: c["boarding"]) && nil
  def apply_stop_fare_km(c)
    stop = stop_for(c)
    refuse_road_fare_mode!(stop.type, "Stop '#{stop.station_id}'")
    stop.update!(fare_km: c["fare_km"])
    nil
  end

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

  def apply_edge_toll(c)
    edge = edge_for(c)
    if edge.line == Line::INTERCHANGE_ID
      raise Rejected.new("Edge '#{edge.edge_id}' is on INTERCHANGE. It has no toll.", field: "edge_id")
    end

    refuse_toll_mode!(edge.mode, "Edge '#{edge.edge_id}'", "edge_id")
    known_plaza!(c["entry_plaza_id"], "entry_plaza_id")
    known_plaza!(c["exit_plaza_id"], "exit_plaza_id")
    edge.update!(toll_entry_plaza_id: c["entry_plaza_id"], toll_exit_plaza_id: c["exit_plaza_id"])
    nil
  end

  def refuse_road_fare_mode!(type, subject)
    return unless NO_ROAD_FARE_MODES.include?(type)

    raise Rejected.new("#{subject} is a #{type} stop. Only road stops have a fare distance.", field: "station_id")
  end

  def refuse_toll_mode!(mode, subject, field)
    return unless NO_TOLL_MODES.include?(mode)

    raise Rejected.new("#{subject} has mode '#{mode}'. It has no toll.", field: field)
  end

  def known_plaza!(id, field)
    return if id.nil? || TollPlaza.exists?(id)

    raise Rejected.new("Toll plaza '#{id}' was not found.", field: field)
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

  # The foreign key cascade deletes the transfers that use the point, so their stations get a fresh interchange flag.
  def apply_access_point_delete(c)
    point = access_point_for(c)
    stations = Edge.where(line: Line::INTERCHANGE_ID)
                   .where("from_access_point_id = :id OR to_access_point_id = :id", id: point.access_point_id)
                   .pluck(:from_station, :to_station).flatten.uniq
    point.delete
    stations.each { |id| ServiceAreaWriter.refresh_interchange_flag(id) }
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
    from_point = transfer_point!(c, "from_access_point_id", from)
    to_point   = transfer_point!(c, "to_access_point_id", to)
    edge_id = "X__#{from_point || from.station_id}__#{to_point || to.station_id}"
    from_end = { station: from.station_id, point: from_point }
    to_end   = { station: to.station_id, point: to_point }
    check_transfer_free!(from_end, to_end, both_ways: c.fetch("bidirectional", true))

    Edge.create!(transfer_attrs(c, edge_id: edge_id, from_end: from_end, to_end: to_end))
    Station.where(station_id: [from.station_id, to.station_id]).update_all(is_interchange: true, updated_at: Time.current)
    edge_id
  end

  def apply_transfer_update(c)
    edge = transfer_for(c)
    attrs = c.slice("travel_time_minutes", "distance_km", "bidirectional", "custom_path")
    check_reverse_free!(edge) if c["bidirectional"] == true
    attrs["polyline_coordinates"] = c["polyline"] if c.key?("polyline")
    check_custom_path!(attrs.fetch("custom_path", edge.custom_path), attrs.fetch("polyline_coordinates", edge.polyline_coordinates))
    edge.update!(attrs)
    nil
  end

  def apply_transfer_delete(c)
    edge = transfer_for(c)
    edge.delete
    [edge.from_station, edge.to_station].each { |id| ServiceAreaWriter.refresh_interchange_flag(id) }
    nil
  end

  # A drawn path needs at least two points, because the iOS app draws it without asking Apple Maps.
  def check_custom_path!(custom_path, polyline)
    return unless custom_path && (polyline.is_a?(Array) ? polyline.length : 0) < 2

    raise Rejected.new("A custom path needs a polyline with at least two points.", field: "polyline")
  end

  def transfer_for(c)
    edge = edge_for(c)
    return edge if edge.line == Line::INTERCHANGE_ID

    raise Rejected.new("Edge '#{edge.edge_id}' is on line '#{edge.line}', not INTERCHANGE.", field: "edge_id")
  end

  # Returns the access point ID when it exists and belongs to the station. Returns nil when the field is absent.
  def transfer_point!(c, field, station)
    id = c[field]
    return nil if id.nil?

    point = StationAccessPoint.find_by(access_point_id: id)
    raise Rejected.new("Access point '#{id}' was not found.", field: field) unless point
    return id if point.station_id == station.station_id

    raise Rejected.new("Access point '#{id}' belongs to '#{point.station_id}', not '#{station.station_id}'.", field: field)
  end

  # An end is { station:, point: }. This is the only place that compares transfer ends; nil matches nil.
  def transfer_between(from_end, to_end, except: nil)
    scope = Edge.where(line: Line::INTERCHANGE_ID)
    scope = scope.where.not(edge_id: except) if except
    scope.find_by(from_station: from_end[:station], from_access_point_id: from_end[:point],
                  to_station: to_end[:station], to_access_point_id: to_end[:point])
  end

  # Rejects a transfer with the same ends in the same direction, or with the reverse ends when either edge is two-way.
  def check_transfer_free!(from_end, to_end, both_ways:)
    if transfer_between(from_end, to_end)
      raise Rejected.new("A transfer with these ends already exists from '#{from_end[:station]}' to '#{to_end[:station]}'.",
                         field: "to_station_id")
    end

    reverse = transfer_between(to_end, from_end)
    return unless reverse && (both_ways || reverse.bidirectional)

    raise Rejected.new("A two-way transfer between these ends would overlap '#{reverse.edge_id}'.", field: "to_station_id")
  end

  # A transfer becomes two-way only when no other transfer runs between the reverse ends.
  def check_reverse_free!(edge)
    reverse = transfer_between({ station: edge.to_station, point: edge.to_access_point_id },
                               { station: edge.from_station, point: edge.from_access_point_id }, except: edge.edge_id)
    return unless reverse

    raise Rejected.new("Transfer '#{reverse.edge_id}' runs in the reverse direction, so '#{edge.edge_id}' cannot be two-way.",
                       field: "bidirectional")
  end

  def transfer_attrs(c, edge_id:, from_end:, to_end:)
    {
      edge_id: edge_id, from_station: from_end[:station], to_station: to_end[:station],
      from_access_point_id: from_end[:point], to_access_point_id: to_end[:point], mode: "walk", line: Line::INTERCHANGE_ID,
      travel_time_minutes: c["travel_time_minutes"], distance_km: c["distance_km"],
      base_fare: 0, fare_per_km: 0, accepted_payments: PaymentMethod.order(:id).pluck(:id),
      is_air_conditioned: false, crowd_factor: 0.8, reliability: 1.0,
      bidirectional: c.fetch("bidirectional", true), direction: nil,
      polyline_coordinates: c["polyline"], mk_directions_transport_type: "walking", is_road_snapped: false,
      custom_path: c.fetch("custom_path", false)
    }
  end
end
