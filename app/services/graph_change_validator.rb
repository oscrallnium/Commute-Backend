# Checks the shape and the values of each publish change without a database read, and returns
# the changes with clean values. Reference checks happen in GraphChangeApplier.
# See docs/ops-publish-api.md for every change type.
class GraphChangeValidator
  MAX_CHANGES     = 2000
  MAX_NAME_LENGTH = 120
  MAX_SHORT_NAME  = 20
  MAX_REASON      = 200
  MAX_NOTES       = 500
  # The character rule for every new graph ID.
  NEW_ID_RE = GraphService::NEW_LINE_ID_RE

  ENABLED_FIELDS = { "enabled" => :boolean, "reason" => :reason }.freeze
  PAYMENT_METHOD_FIELDS = { "name" => :name, "sf_symbol" => :label, "color_hex" => :required_color,
                            "is_default" => :boolean, "accepted_by_modes" => :mode_ids, "notes" => :notes }.freeze
  EXCEPTION_FIELDS = { "direction" => :direction_word, "start_date" => :date, "end_date" => :date,
                       "kind" => :exception_kind, "start" => :time, "end" => :time,
                       "departures" => :departure_times, "note" => :note }.freeze
  SCHEDULE_ITEM_FIELDS = { "days" => :service_days, "kind" => :schedule_kind, "start" => :time, "end" => :time,
                           "departures" => :departure_times, "note" => :note }.freeze
  DATE_RE = /\A\d{4}-\d{2}-\d{2}\z/
  TYPES = {
    "line_name" => { required: { "line_id" => :reference_id, "name" => :name } },
    "line_color" => { required: { "line_id" => :reference_id, "color_hex" => :color } },
    "line_direction" => { required: { "line_id" => :reference_id, "direction" => :line_direction } },
    "line_enabled" => { required: { "line_id" => :reference_id, **ENABLED_FIELDS } },
    "line_road_fare" => { required: { "line_id" => :reference_id, "base_fare" => :non_negative,
                                      "base_km" => :non_negative, "fare_per_km" => :non_negative },
                          optional: { "fare_step_km" => :optional_non_negative,
                                      "fare_km_rounding" => :optional_fare_km_rounding } },
    "line_rail_fares" => { required: { "line_id" => :reference_id, "station_ids" => :station_ids,
                                       "fares" => :fare_rows } },
    "line_delete" => { required: { "line_id" => :reference_id } },
    "line_toll_load_factor" => { required: { "line_id" => :reference_id, "load_factor" => :load_factor } },
    "toll_matrix" => { required: { "plazas" => :toll_plazas, "fares" => :toll_fares } },
    "edge_toll" => { required: { "edge_id" => :reference_id, "entry_plaza_id" => :nullable_reference_id,
                                 "exit_plaza_id" => :nullable_reference_id } },
    "stop_name" => { required: { "station_id" => :reference_id, "name" => :name } },
    "stop_short_name" => { required: { "station_id" => :reference_id, "short_name" => :short_name } },
    "stop_boarding" => { required: { "station_id" => :reference_id, "boarding" => :boarding } },
    "stop_fare_km" => { required: { "station_id" => :reference_id, "fare_km" => :optional_non_negative } },
    "stop_hours" => { required: { "station_id" => :reference_id, "open" => :time, "close" => :time } },
    "stop_enabled" => { required: { "station_id" => :reference_id, **ENABLED_FIELDS } },
    "edge_travel_time" => { required: { "edge_id" => :reference_id, "travel_time_minutes" => :positive } },
    "edge_distance" => { required: { "edge_id" => :reference_id, "distance_km" => :positive } },
    "edge_enabled" => { required: { "edge_id" => :reference_id, **ENABLED_FIELDS } },
    "access_point_add" => { required: { "station_id" => :reference_id, "kind" => :access_kind,
                                        "lat" => :lat, "lng" => :lng },
                            optional: { "access_point_id" => :new_id, "name" => :label,
                                        "direction" => :access_direction } },
    "access_point_update" => { required: { "access_point_id" => :reference_id },
                               optional: { "name" => :label, "kind" => :access_kind,
                                           "direction" => :access_direction, "lat" => :lat, "lng" => :lng },
                               at_least_one: true },
    "access_point_delete" => { required: { "access_point_id" => :reference_id } },
    "transfer_add" => { required: { "from_station_id" => :reference_id, "to_station_id" => :reference_id,
                                    "travel_time_minutes" => :positive, "distance_km" => :non_negative,
                                    "polyline" => :polyline, "from_access_point_id" => :reference_id,
                                    "to_access_point_id" => :reference_id },
                        optional: { "bidirectional" => :boolean, "custom_path" => :boolean } },
    "transfer_update" => { required: { "edge_id" => :reference_id },
                           optional: { "travel_time_minutes" => :positive, "distance_km" => :non_negative,
                                       "polyline" => :polyline, "bidirectional" => :boolean,
                                       "custom_path" => :boolean },
                           at_least_one: true },
    "transfer_delete" => { required: { "edge_id" => :reference_id } },
    "service_area_add" => { required: { "line_id" => :new_id, "name" => :name, "mode" => :reference_id,
                                        "boundary" => :boundary, "terminals" => :terminals,
                                        "base_fare" => :non_negative, "base_km" => :non_negative,
                                        "fare_per_km" => :non_negative, "accepted_payments" => :payment_ids,
                                        "open" => :time, "close" => :time },
                            optional: { "color_hex" => :color, "special_trip_fare" => :optional_non_negative,
                                        "speed_kmh" => :positive, "detour_factor" => :detour_factor,
                                        "wait_minutes" => :non_negative } },
    "service_area_boundary" => { required: { "line_id" => :reference_id, "boundary" => :boundary } },
    "service_area_fare" => { required: { "line_id" => :reference_id, "base_fare" => :non_negative,
                                         "base_km" => :non_negative, "fare_per_km" => :non_negative },
                             optional: { "special_trip_fare" => :optional_non_negative,
                                         "accepted_payments" => :payment_ids } },
    "service_area_timing" => { required: { "line_id" => :reference_id },
                               optional: { "speed_kmh" => :positive, "detour_factor" => :detour_factor,
                                           "wait_minutes" => :non_negative },
                               at_least_one: true },
    "service_area_terminal_add" => { required: { "line_id" => :reference_id, "name" => :name,
                                                 "lat" => :lat, "lng" => :lng },
                                     optional: { "short_name" => :short_name } },
    "service_area_terminal_delete" => { required: { "station_id" => :reference_id } },
    "payment_method_add" => { required: { "payment_method_id" => :payment_method_id, "name" => :name },
                              optional: PAYMENT_METHOD_FIELDS.except("name") },
    "payment_method_update" => { required: { "payment_method_id" => :reference_id },
                                 optional: PAYMENT_METHOD_FIELDS, at_least_one: true },
    "payment_method_delete" => { required: { "payment_method_id" => :reference_id } },
    "service_schedule_set" => { required: { "line_id" => :reference_id, "schedules" => :schedules },
                                optional: { "direction" => :direction_word } },
    "service_schedule_clear" => { required: { "line_id" => :reference_id },
                                  optional: { "direction" => :direction_word } },
    "service_exception_add" => { required: { "line_id" => :reference_id, "start_date" => :date,
                                             "end_date" => :date, "kind" => :exception_kind },
                                 optional: EXCEPTION_FIELDS.slice("direction", "start", "end", "departures", "note") },
    "service_exception_update" => { required: { "exception_id" => :reference_id },
                                    optional: EXCEPTION_FIELDS, at_least_one: true },
    "service_exception_delete" => { required: { "exception_id" => :reference_id } },
    "line_payments" => { required: { "line_id" => :reference_id, "accepted_payments" => :payment_ids } },
    "mode_default_payments" => { required: { "mode_id" => :reference_id, "accepted_payments" => :payment_ids } }
  }.freeze
  MAX_TERMINALS = 20
  TERMINAL_KEYS = %w[name short_name lat lng].freeze

  Error = Struct.new(:index, :type, :field, :message, keyword_init: true) do
    def to_h = super.compact
  end

  def initialize(changes)
    @changes = changes
    @errors  = []
  end

  # Returns [clean_changes, errors]. The clean changes are valid only when errors is empty.
  def call
    return [[], @errors] unless list_valid?

    clean = @changes.each_with_index.map { |change, index| clean_change(change, index) }
    [clean, @errors]
  end

  private

  def list_valid?
    message = if !@changes.is_a?(Array) then "changes must be an array."
              elsif @changes.empty? then "changes must not be empty."
              elsif @changes.length > MAX_CHANGES then "Send #{MAX_CHANGES} changes or fewer in one publish."
              end
    @errors << Error.new(field: "changes", message: message) if message
    message.nil?
  end

  def clean_change(change, index)
    return add_error(index, nil, "type", "Each change must be a JSON object.") unless change.is_a?(Hash)

    type = change["type"]
    rules = TYPES[type]
    return add_error(index, type, "type", "Unknown change type '#{type}'.") unless rules

    clean = { "type" => type }
    check_fields(change, rules, index, clean)
    check_type_rules(clean, index)
    clean
  end

  def check_fields(change, rules, index, clean)
    allowed = ["type", *rules[:required].keys, *rules.fetch(:optional, {}).keys]
    (change.keys - allowed).each { |key| add_error(index, change["type"], key, "Unknown field '#{key}'.") }

    rules[:required].each do |field, type|
      next add_error(index, change["type"], field, "#{field} is required.") unless change.key?(field)

      clean_field(change, field, type, index, clean)
    end
    rules.fetch(:optional, {}).each do |field, type|
      clean_field(change, field, type, index, clean) if change.key?(field)
    end
    return unless rules[:at_least_one] && !change.keys.intersect?(rules[:optional].keys)

    add_error(index, change["type"], nil, "Send at least one of: #{rules[:optional].keys.join(", ")}.")
  end

  def clean_field(change, field, type, index, clean)
    value, message = send("clean_#{type}", change[field])
    message ? add_error(index, change["type"], field, "#{field} #{message}") : clean[field] = value
  end

  def check_type_rules(clean, index)
    case clean["type"]
    when "line_rail_fares" then check_fare_grid(clean, index)
    when "toll_matrix" then check_toll_matrix(clean, index)
    when "access_point_update" then check_lat_lng_pair(clean, index)
    when "transfer_add" then check_transfer_ends(clean, index)
    when "service_exception_add" then check_exception_add(clean, index)
    when "service_exception_update" then check_exception_update(clean, index)
    end
    clean["reason"] = nil if clean["enabled"] == true
  end

  def check_fare_grid(clean, index)
    ids = clean["station_ids"]
    rows = clean["fares"]
    return unless ids && rows

    unless rows.length == ids.length && rows.all? { |row| row.length == ids.length }
      return add_error(index, clean["type"], "fares", "fares must have one row and one column for each station.")
    end

    rows.each_with_index do |row, i|
      row.each_with_index do |fare, j|
        next row[j] = nil if i == j && (fare.nil? || fare.zero?)
        next if i != j && fare

        add_error(index, clean["type"], "fares[#{i}][#{j}]",
                  i == j ? "A station has no fare to itself. Send null." : "Every station pair needs a fare.")
      end
    end
  end

  # Each fare must name two listed plazas that differ, and a pair must not repeat.
  def check_toll_matrix(clean, index)
    return unless clean["plazas"] && clean["fares"]

    ids = clean["plazas"].pluck("id")
    pairs = clean["fares"].map { |fare| fare.values_at("entry", "exit") }
    fares_error = pairs.filter_map { |entry, exit_id| toll_pair_error(entry, exit_id, ids) }.first
    fares_error ||= "must not list a pair twice." if pairs.uniq.length != pairs.length
    add_error(index, clean["type"], "fares", "fares #{fares_error}") if fares_error
  end

  def toll_pair_error(entry, exit_id, ids)
    return "must not have the same plaza as entry and exit." if entry == exit_id

    unknown = [entry, exit_id].find { |id| ids.exclude?(id) }
    "names plaza '#{unknown}', which is not in plazas." if unknown
  end

  def check_lat_lng_pair(clean, index)
    return if clean.key?("lat") == clean.key?("lng")

    add_error(index, clean["type"], "lat", "Send lat and lng together.")
  end

  def check_transfer_ends(clean, index)
    from = clean["from_station_id"]
    to = clean["to_station_id"]
    return unless from && to

    add_error(index, clean["type"], "to_station_id", "A transfer needs two different stops.") if from == to
    [["from_station_id", from], ["to_station_id", to], ["from_access_point_id", clean["from_access_point_id"]],
     ["to_access_point_id", clean["to_access_point_id"]]].each do |field, id|
      next if id.nil? || id.match?(NEW_ID_RE)

      add_error(index, clean["type"], field,
                "'#{id}' does not follow the graph ID convention, so the transfer edge ID would not either.")
    end
  end

  def check_exception_add(clean, index)
    check_date_order(clean, index)
    check_times_fit_kind(clean, index)
  end

  def check_times_fit_kind(clean, index)
    field, message = time_rule_error(clean)
    add_error(index, clean["type"], field, message) if message
  end

  # An update that sends kind must carry the times of that kind. The writer clears the old times.
  def check_exception_update(clean, index)
    check_date_order(clean, index)
    return check_times_fit_kind(clean, index) if clean["kind"]

    return unless clean["start"] && clean["start"] == clean["end"]

    add_error(index, clean["type"], "end", "end must differ from start.")
  end

  def check_date_order(clean, index)
    return unless clean["start_date"] && clean["end_date"] && clean["end_date"] < clean["start_date"]

    add_error(index, clean["type"], "end_date", "end_date must not be before start_date.")
  end

  # Returns [field, message] when the times do not fit the kind, or nil. Keys are start, end, and departures.
  def time_rule_error(item)
    case item["kind"]
    when "window"
      return ["start", "A window needs start and end."] unless item["start"] && item["end"]
      return ["end", "end must differ from start."] if item["start"] == item["end"]

      ["departures", "A window takes no departures."] if item["departures"]
    when "departures"
      return ["departures", "Departures need a list of times."] unless item["departures"]

      ["start", "Departures take no start or end."] if item["start"] || item["end"]
    when "no_service"
      ["kind", "no_service takes no times."] if item.keys.intersect?(%w[start end departures])
    end
  end

  def add_error(index, type, field, message)
    @errors << Error.new(index: index, type: type, field: field, message: message)
    nil
  end

  # ── Field types. Each returns [clean_value, nil] or [nil, error_message]. ──

  def clean_reference_id(value)
    value.is_a?(String) && value.match?(/\A\S{1,120}\z/) ? [value, nil] : [nil, "must be an existing ID."]
  end

  def clean_new_id(value)
    if value.is_a?(String) && value.match?(NEW_ID_RE)
      [value,
       nil]
    else
      [nil, "must use uppercase letters, digits, and single underscores."]
    end
  end

  def clean_nullable_reference_id(value)
    value.nil? ? [nil, nil] : clean_reference_id(value)
  end

  def clean_load_factor(value)
    return [nil, nil] if value.nil?

    whole = value.is_a?(Numeric) && value.finite? && value == value.to_i
    whole && value.positive? ? [value.to_i, nil] : [nil, "must be a whole number greater than 0, or null."]
  end

  def clean_toll_plazas(value)
    return [nil, "must be a list of plazas."] unless value.is_a?(Array)

    plazas = value.map { |plaza| clean_toll_plaza(plaza) }
    return [nil, "must hold only items with an id and a name."] unless plazas.all?
    return [nil, "must not list a plaza twice."] unless plazas.pluck("id").uniq.length == plazas.length

    [plazas, nil]
  end

  def clean_toll_plaza(plaza)
    return unless plaza.is_a?(Hash) && plaza.keys.sort == %w[id name]

    id = clean_new_id(plaza["id"])
    name = clean_name(plaza["name"])
    { "id" => id.first, "name" => name.first } if id.last.nil? && name.last.nil?
  end

  def clean_toll_fares(value)
    return [nil, "must be a list of fares."] unless value.is_a?(Array)

    fares = value.map { |fare| clean_toll_fare(fare) }
    fares.all? ? [fares, nil] : [nil, "must hold only items with an entry, an exit, and an amount of 0 or more."]
  end

  def clean_toll_fare(fare)
    return unless fare.is_a?(Hash) && fare.keys.sort == %w[amount entry exit]

    entry = clean_reference_id(fare["entry"])
    exit_id = clean_reference_id(fare["exit"])
    amount = clean_non_negative(fare["amount"])
    return unless [entry, exit_id, amount].all? { |_, message| message.nil? }

    { "entry" => entry.first, "exit" => exit_id.first, "amount" => amount.first }
  end

  def clean_name(value)
    text = value.is_a?(String) ? value.strip : ""
    text.empty? || text.length > MAX_NAME_LENGTH ? [nil, "must be 1 to #{MAX_NAME_LENGTH} characters."] : [text, nil]
  end

  def clean_short_name(value)
    text = value.is_a?(String) ? value.strip : ""
    text.empty? || text.length > MAX_SHORT_NAME ? [nil, "must be 1 to #{MAX_SHORT_NAME} characters."] : [text, nil]
  end

  def clean_label(value)
    if value.is_a?(String) && value.strip.length <= MAX_NAME_LENGTH
      [value.strip,
       nil]
    else
      [nil,
       "must be text of #{MAX_NAME_LENGTH} characters or fewer."]
    end
  end

  def clean_reason(value)
    return [nil, nil] if value.nil?
    unless value.is_a?(String) && value.strip.length <= MAX_REASON
      return [nil,
              "must be text of #{MAX_REASON} characters or fewer, or null."]
    end

    [value.strip.presence, nil]
  end

  def clean_boolean(value)
    [true, false].include?(value) ? [value, nil] : [nil, "must be true or false."]
  end

  def clean_color(value)
    return [nil, nil] if value.nil?

    color = value.is_a?(String) ? value.strip.upcase : ""
    color.match?(Line::COLOR_HEX_FORMAT) ? [color, nil] : [nil, "must look like #RRGGBB, or be null."]
  end

  def clean_required_color(value)
    color, = clean_color(value)
    color ? [color, nil] : [nil, "must look like #RRGGBB."]
  end

  def clean_notes(value)
    if value.is_a?(String) && value.strip.length <= MAX_NOTES
      [value.strip, nil]
    else
      [nil, "must be text of #{MAX_NOTES} characters or fewer."]
    end
  end

  def clean_payment_method_id(value)
    if clean_reference_id(value).last.nil? && value.match?(GraphService::PAYMENT_METHOD_ID_RE)
      [value, nil]
    else
      [nil, "must use lowercase letters, digits, and single underscores."]
    end
  end

  def clean_line_direction(value) = enum(value, Line::DIRECTIONS)

  def clean_optional_fare_km_rounding(value)
    value.nil? ? [nil, nil] : enum(value, Line::FARE_KM_ROUNDINGS)
  end

  def clean_boarding(value) = enum(value, Station::BOARDING_VALUES)
  def clean_access_kind(value) = enum(value, StationAccessPoint::KINDS)

  def clean_access_direction(value)
    value.nil? ? [nil, nil] : enum(value, StationAccessPoint::DIRECTIONS)
  end

  def enum(value, allowed)
    allowed.include?(value) ? [value, nil] : [nil, "must be one of: #{allowed.join(", ")}."]
  end

  def clean_time(value)
    value.is_a?(String) && value.match?(GraphService::TIME_RE) ? [value, nil] : [nil, "must be HH:mm (24-hour)."]
  end

  def clean_direction_word(value)
    value.nil? ? [nil, nil] : enum(value, GraphService::DIRECTION_TAGS.keys)
  end

  def clean_schedule_kind(value) = enum(value, GraphService::SCHEDULE_KINDS)
  def clean_exception_kind(value) = enum(value, GraphService::EXCEPTION_KINDS)

  def clean_date(value)
    valid = value.is_a?(String) && value.match?(DATE_RE) && Date.valid_date?(*value.split("-").map(&:to_i))
    valid ? [value, nil] : [nil, "must be a real date as YYYY-MM-DD."]
  end

  def clean_note(value)
    return [nil, nil] if value.nil?

    text, message = clean_notes(value)
    [text.presence, message]
  end

  def clean_service_days(value)
    return [nil, "must list one or more days."] unless value.is_a?(Array) && value.any?
    return [nil, "must use only: #{GraphService::SERVICE_DAYS.join(", ")}."] unless (value - GraphService::SERVICE_DAYS).empty?
    return [nil, "must not list a day twice."] unless value.uniq.length == value.length

    [value, nil]
  end

  def clean_departure_times(value)
    return [nil, "must list one or more times."] unless value.is_a?(Array) && value.any?
    return [nil, "must hold only HH:mm times (24-hour)."] unless value.all? { |time| clean_time(time).last.nil? }
    return [nil, "must not list a time twice."] unless value.uniq.length == value.length

    [value.sort, nil]
  end

  def clean_schedules(value)
    unless value.is_a?(Array) && value.any?
      return [nil, "must list one or more schedules. Use service_schedule_clear to remove them."]
    end

    items = value.each_with_index.map { |item, position| clean_schedule_item(item, position) }
    message = items.filter_map { |_, error| error }.first
    return [nil, message] if message
    return [nil, "must use one kind in all items."] unless items.map { |item, _| item["kind"] }.uniq.length == 1

    [items.map(&:first), nil]
  end

  def clean_schedule_item(item, position)
    label = "item #{position + 1}"
    return [nil, "#{label} must be an object."] unless item.is_a?(Hash)

    unknown = item.keys - SCHEDULE_ITEM_FIELDS.keys
    return [nil, "#{label} has unknown field '#{unknown.first}'."] if unknown.any?
    return [nil, "#{label} needs days and kind."] unless item.key?("days") && item.key?("kind")

    clean = {}
    item.each do |field, raw|
      value, message = send("clean_#{SCHEDULE_ITEM_FIELDS.fetch(field)}", raw)
      return [nil, "#{label} #{field} #{message}"] if message

      clean[field] = value
    end
    _, message = time_rule_error(clean)
    message ? [nil, "#{label}: #{message}"] : [clean, nil]
  end

  def clean_non_negative(value)
    number?(value) && value >= 0 ? [value.to_f, nil] : [nil, "must be a number of 0 or more."]
  end

  def clean_optional_non_negative(value)
    value.nil? ? [nil, nil] : clean_non_negative(value)
  end

  def clean_detour_factor(value)
    number?(value) && value >= 1 ? [value.to_f, nil] : [nil, "must be a number of 1 or more."]
  end

  def clean_positive(value)
    number?(value) && value.positive? ? [value.to_f, nil] : [nil, "must be a number greater than 0."]
  end

  def clean_lat(value)
    number?(value) && value.between?(-90, 90) ? [value.to_f, nil] : [nil, "must be a number from -90 to 90."]
  end

  def clean_lng(value)
    number?(value) && value.between?(-180, 180) ? [value.to_f, nil] : [nil, "must be a number from -180 to 180."]
  end

  def clean_station_ids(value)
    valid = value.is_a?(Array) && value.length >= 2 && value.all? { |id| clean_reference_id(id).last.nil? }
    return [nil, "must list two or more station IDs."] unless valid
    return [nil, "must not list a station twice."] unless value.uniq.length == value.length

    [value, nil]
  end

  def clean_fare_rows(value)
    valid = value.is_a?(Array) && value.all? { |row| row.is_a?(Array) && row.all? { |f| f.nil? || (number?(f) && f >= 0) } }
    valid ? [value.map { |row| row.map { |f| f&.to_f } }, nil] : [nil, "must be rows of numbers of 0 or more, or null."]
  end

  def clean_polyline(value)
    points = value.is_a?(Array) ? value : []
    clean = points.filter_map do |p|
      next unless p.is_a?(Hash) && clean_lat(p["lat"]).last.nil? && clean_lng(p["lng"]).last.nil?

      { "lat" => p["lat"].to_f, "lng" => p["lng"].to_f }
    end
    if clean.length >= 2 && clean.length == points.length
      [clean,
       nil]
    else
      [nil, "must be two or more points with a valid lat and lng."]
    end
  end

  def clean_boundary(value)
    limits = ServiceArea::MIN_VERTICES..ServiceArea::MAX_VERTICES
    return [nil, "must list #{limits.begin} to #{limits.end} points."] unless value.is_a?(Array) && limits.cover?(value.length)

    points = value.map { |point| clean_point(point) }
    points.all? ? [points, nil] : [nil, "must hold only points with a valid lat and lng."]
  end

  def clean_point(point)
    return unless point.is_a?(Hash) && clean_lat(point["lat"]).last.nil? && clean_lng(point["lng"]).last.nil?

    { "lat" => point["lat"].to_f, "lng" => point["lng"].to_f }
  end

  def clean_terminals(value)
    unless value.is_a?(Array) && (1..MAX_TERMINALS).cover?(value.length)
      return [nil, "must list 1 to #{MAX_TERMINALS} terminals."]
    end

    terminals = value.map { |terminal| clean_terminal(terminal) }
    terminals.all? ? [terminals, nil] : [nil, "must hold only terminals with a name, a lat, and a lng."]
  end

  def clean_terminal(terminal)
    return unless terminal.is_a?(Hash) && (terminal.keys - TERMINAL_KEYS).empty?

    name = clean_name(terminal["name"])
    point = clean_point(terminal.slice("lat", "lng"))
    short = terminal.key?("short_name") ? clean_short_name(terminal["short_name"]) : [nil, nil]
    return unless name.last.nil? && point && short.last.nil?

    { "name" => name.first, **point, **(short.first ? { "short_name" => short.first } : {}) }
  end

  def clean_payment_ids(value)
    valid = value.is_a?(Array) && value.any? && value.all? { |id| clean_reference_id(id).last.nil? }
    return [nil, "must list one or more payment method IDs."] unless valid
    return [nil, "must not list a payment method twice."] unless value.uniq.length == value.length

    [value, nil]
  end

  def clean_mode_ids(value)
    valid = value.is_a?(Array) && value.all? { |id| clean_reference_id(id).last.nil? }
    return [nil, "must be a list of mode IDs."] unless valid
    return [nil, "must not list a mode twice."] unless value.uniq.length == value.length

    [value, nil]
  end

  def number?(value)
    value.is_a?(Numeric) && value.to_f.finite?
  end
end
