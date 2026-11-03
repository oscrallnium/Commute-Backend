# Writes tricycle service areas and their terminals. Every method runs inside the publish
# transaction and raises GraphChangeApplier::Rejected, with a field, when a rule refuses the change.
# A terminal is deleted with delete_terminal_with_transfers!, so every caller removes its transfers.
class ServiceAreaWriter
  MAX_TERMINALS = 20
  DEFAULT_OPEN  = "05:00".freeze
  DEFAULT_CLOSE = "23:00".freeze
  TIMING_FIELDS = %w[speed_kmh detour_factor wait_minutes].freeze
  FARE_FIELDS   = %w[base_fare base_km fare_per_km].freeze

  # Deletes the terminal and its INTERCHANGE edges. A stop with no transfer left loses its flag.
  # It uses delete_all, as GraphService#remove_stop does. Stored station IDs have no foreign key.
  def self.delete_terminal_with_transfers!(station)
    edges = Edge.where(line: Line::INTERCHANGE_ID)
                .where("from_station = :id OR to_station = :id", id: station.station_id)
    others = edges.flat_map { |edge| [edge.from_station, edge.to_station] }.uniq - [station.station_id]
    edges.delete_all
    Station.where(station_id: station.station_id).delete_all
    others.each { |id| refresh_interchange_flag(id) }
  end

  def self.refresh_interchange_flag(station_id)
    linked = Edge.where(line: Line::INTERCHANGE_ID).exists?(["from_station = :id OR to_station = :id", { id: station_id }])
    Station.where(station_id: station_id).update_all(is_interchange: linked, updated_at: Time.current)
  end

  # Deletes the service area row and every terminal of the line.
  def self.remove_zone!(line)
    Station.where(line: line.id, is_terminal: true).find_each { |station| delete_terminal_with_transfers!(station) }
    ServiceArea.where(line_id: line.id).delete_all
  end

  def add(change)
    line_id = change["line_id"]
    reject!("Line '#{line_id}' already exists.", "line_id") if Line.exists?(line_id) || Station.exists?(line: line_id)
    mode = area_mode!(change["mode"])
    unknown_payments!(change["accepted_payments"])

    create_line!(change, mode)
    area = create_area!(change)
    create_terminals!(change, area, mode)
    nil
  end

  def update_boundary(change)
    area = area_for(change)
    area.boundary = change["boundary"]
    area.validate!
    outside = Station.where(line: area.line_id, is_terminal: true).order(:station_id)
                     .reject { |station| area.contains?(station.lat.to_f, station.lng.to_f) }
    if outside.any?
      reject!("These terminals would fall outside the boundary: #{outside.map(&:station_id).join(", ")}.", "boundary")
    end
    area.save!
    nil
  end

  def update_fare(change)
    area = area_for(change)
    attrs = change.slice(*FARE_FIELDS, "special_trip_fare")
    if change.key?("accepted_payments")
      unknown_payments!(change["accepted_payments"])
      attrs["accepted_payments"] = change["accepted_payments"]
    end
    area.update!(attrs)
    nil
  end

  def update_timing(change)
    area_for(change).update!(change.slice(*TIMING_FIELDS))
    nil
  end

  # Returns the ID of the new terminal.
  def add_terminal(change)
    line = Line.lock.find_by(id: change["line_id"])
    area = area_for(change, line: line)
    terminal = terminal_attrs(change, area: area, index: nil)
    number = line.last_stop_number + 1
    line.update!(last_stop_number: number)
    hours = hours_of_line(line.id)
    station = Station.create!(terminal.merge(station_id: "#{line.id}_S#{number}", line: line.id, type: line.mode, **hours))
    station.station_id
  end

  def delete_terminal(change)
    station = Station.find_by(station_id: change["station_id"])
    reject!("Stop '#{change["station_id"]}' was not found.", "station_id") unless station
    unless station.is_terminal && ServiceArea.exists?(line_id: station.line)
      reject!("Stop '#{station.station_id}' is not a terminal of a service area.", "station_id")
    end
    if Station.where(line: station.line, is_terminal: true).count <= 1
      reject!("A service area needs at least one terminal.", "station_id")
    end
    self.class.delete_terminal_with_transfers!(station)
    nil
  end

  private

  def area_mode!(mode_id)
    mode = TransportMode.find_by(id: mode_id)
    reject!("Mode '#{mode_id}' was not found.", "mode") unless mode
    unless mode.area_service_shape?
      reject!("Mode '#{mode_id}' runs on fixed paths. Use POST /api/v1/admin/graph/routes for it.", "mode")
    end
    mode
  end

  def unknown_payments!(ids)
    unknown = ids - PaymentMethod.pluck(:id)
    reject!("Unknown payment methods: #{unknown.join(", ")}.", "accepted_payments") if unknown.any?
  end

  def create_line!(change, mode)
    Line.create!(id: change["line_id"], display_name: change["name"], mode: mode.id, color_hex: change["color_hex"],
                 direction: "both", last_stop_number: change["terminals"].length)
    TransportMode.where(id: mode.id).where.not("? = ANY(lines)", change["line_id"])
                 .update_all(["lines = array_append(lines, ?)", change["line_id"]])
  end

  def create_area!(change)
    attrs = change.slice("boundary", "accepted_payments", "special_trip_fare", *FARE_FIELDS, *TIMING_FIELDS)
    ServiceArea.create!(attrs.merge(line_id: change["line_id"]))
  end

  def create_terminals!(change, area, mode)
    ids = change["terminals"].each_index.map { |index| "#{area.line_id}_S#{index + 1}" }
    reject!("Stops #{ids.join(", ")} already exist.", "line_id") if Station.exists?(station_id: ids)

    change["terminals"].each_with_index do |terminal, index|
      attrs = terminal_attrs(terminal, area: area, index: index)
      Station.create!(attrs.merge(station_id: ids[index], line: area.line_id, type: mode.id,
                                  open_time: change["open"], close_time: change["close"]))
    end
  end

  # Index is the position in the terminals list, or nil for a single terminal change.
  def terminal_attrs(terminal, area:, index:)
    unless area.contains?(terminal["lat"], terminal["lng"])
      reject!("The terminal '#{terminal["name"]}' is outside the service area boundary.",
              index ? "terminals[#{index}]" : "lat")
    end
    { name: terminal["name"], short_name: terminal["short_name"] || derive_short_name(terminal["name"]),
      lat: terminal["lat"], lng: terminal["lng"], is_terminal: true, sequence: nil }
  end

  def hours_of_line(line_id)
    existing = Station.where(line: line_id, is_terminal: true).order(:station_id).first
    { open_time: existing&.open_time || DEFAULT_OPEN, close_time: existing&.close_time || DEFAULT_CLOSE }
  end

  def area_for(change, line: Line.find_by(id: change["line_id"]))
    reject!("Line '#{change["line_id"]}' was not found.", "line_id") unless line
    line.service_area || reject!("Line '#{line.id}' is not a service area.", "line_id")
  end

  def derive_short_name(name)
    name.to_s.strip.split.first.to_s[0, 6].upcase
  end

  def reject!(message, field)
    raise GraphChangeApplier::Rejected.new(message, field: field)
  end
end
