# Checks the shape and the values of each publish change without a database read, and returns
# the changes with clean values. Reference checks happen in GraphChangeApplier.
# See docs/ops-publish-api.md for every change type.
class GraphChangeValidator
  MAX_CHANGES     = 2000
  MAX_NAME_LENGTH = 120
  MAX_SHORT_NAME  = 20
  MAX_REASON      = 200
  # The character rule for every new graph ID.
  NEW_ID_RE = GraphService::NEW_LINE_ID_RE

  ENABLED_FIELDS = { "enabled" => :boolean, "reason" => :reason }.freeze
  TYPES = {
    "line_name" => { required: { "line_id" => :reference_id, "name" => :name } },
    "line_color" => { required: { "line_id" => :reference_id, "color_hex" => :color } },
    "line_direction" => { required: { "line_id" => :reference_id, "direction" => :line_direction } },
    "line_enabled" => { required: { "line_id" => :reference_id, **ENABLED_FIELDS } },
    "line_road_fare" => { required: { "line_id" => :reference_id, "base_fare" => :non_negative,
                                      "base_km" => :non_negative, "fare_per_km" => :non_negative } },
    "line_rail_fares" => { required: { "line_id" => :reference_id, "station_ids" => :station_ids,
                                       "fares" => :fare_rows } },
    "line_delete" => { required: { "line_id" => :reference_id } },
    "stop_name" => { required: { "station_id" => :reference_id, "name" => :name } },
    "stop_short_name" => { required: { "station_id" => :reference_id, "short_name" => :short_name } },
    "stop_boarding" => { required: { "station_id" => :reference_id, "boarding" => :boarding } },
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
                                    "polyline" => :polyline },
                        optional: { "bidirectional" => :boolean } },
    "transfer_update" => { required: { "edge_id" => :reference_id },
                           optional: { "travel_time_minutes" => :positive, "distance_km" => :non_negative,
                                       "polyline" => :polyline },
                           at_least_one: true },
    "transfer_delete" => { required: { "edge_id" => :reference_id } }
  }.freeze

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
    when "access_point_update" then check_lat_lng_pair(clean, index)
    when "transfer_add" then check_transfer_ends(clean, index)
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

  def check_lat_lng_pair(clean, index)
    return if clean.key?("lat") == clean.key?("lng")

    add_error(index, clean["type"], "lat", "Send lat and lng together.")
  end

  def check_transfer_ends(clean, index)
    from = clean["from_station_id"]
    to = clean["to_station_id"]
    return unless from && to

    add_error(index, clean["type"], "to_station_id", "A transfer needs two different stops.") if from == to
    [["from_station_id", from], ["to_station_id", to]].each do |field, id|
      next if id.match?(NEW_ID_RE)

      add_error(index, clean["type"], field,
                "'#{id}' does not follow the graph ID convention, so the transfer edge ID would not either.")
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

  def clean_line_direction(value) = enum(value, Line::DIRECTIONS)
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

  def clean_non_negative(value)
    number?(value) && value >= 0 ? [value.to_f, nil] : [nil, "must be a number of 0 or more."]
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

  def number?(value)
    value.is_a?(Numeric) && value.to_f.finite?
  end
end
