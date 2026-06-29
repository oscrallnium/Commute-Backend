# app/services/graph_service.rb
#
# Ports all transit graph write logic from the Hono microservice into Rails.
# Replaces: src/routes/addRoute.ts, src/geo.ts, src/validation.ts, src/graph.ts
#
# Thread safety: ActiveRecord transactions + DB-level constraints replace the
# in-process async mutex from the Hono service. Postgres handles concurrent
# writes correctly; no in-process mutex needed in Rails with a proper DB.

class GraphService
  # Metro Manila bounding box — same as Hono validation.ts
  MM_LAT_MIN = 14.3
  MM_LAT_MAX = 14.9
  MM_LNG_MIN = 120.8
  MM_LNG_MAX = 121.3

  EARTH_RADIUS_KM  = 6371.0
  AVG_SPEED_KMH    = 24.0
  MIN_TRAVEL_TIME  = 2.0 # minutes

  LINE_ID_RE  = /\A[A-Z0-9_]+\z/
  TIME_RE     = /\A([01]\d|2[0-3]):[0-5]\d\z/

  Result = Struct.new(:success?, :data, :errors, keyword_init: true)

  # ── Public API ──────────────────────────────────────────────────────────────

  # Adds a route: validates payload, creates stations + edges in Postgres,
  # bumps graph version. Wraps everything in a transaction — either all
  # rows are written or none are.
  def self.add_route(payload)
    new.add_route(payload)
  end

  def self.delete_route(line_id)
    new.delete_route(line_id)
  end

  def self.assemble_graph
    new.assemble_graph
  end

  def self.graph_version
    new.graph_version
  end

  # ── add_route ───────────────────────────────────────────────────────────────

  def add_route(payload)
    errors = validate(payload)
    return Result.new(success?: false, errors: errors) if errors.any?

    stops      = payload[:stops] || payload["stops"] || []
    line_id    = payload[:lineID] || payload["lineID"]
    mode       = payload[:mode]   || payload["mode"]
    stations   = []
    edges      = []

    stops.each_with_index do |stop, i|
      stop_name  = stop[:name] || stop["name"]
      stop_lat   = stop[:lat].to_f
      stop_lng   = stop[:lng].to_f
      short_name = stop[:shortName] || stop["shortName"] || derive_short_name(stop_name)
      stop_id    = "#{line_id}_STOP#{i + 1}"

      stations << {
        station_id: stop_id,
        name: stop_name,
        short_name: short_name,
        line: line_id,
        type: mode,
        lat: stop_lat,
        lng: stop_lng,
        is_terminal: i.zero? || i == stops.length - 1,
        is_interchange: false,
        amenities: [],
        open_time: payload[:openTime] || payload["openTime"] || "05:00",
        close_time: payload[:closeTime] || payload["closeTime"] || "23:00",
        created_at: Time.current,
        updated_at: Time.current
      }

      # Build edge from previous stop to this stop
      next if i.zero?

      prev_stop = stops[i - 1]
      prev_lat  = prev_stop[:lat].to_f
      prev_lng  = prev_stop[:lng].to_f
      dist_km   = haversine(prev_lat, prev_lng, stop_lat, stop_lng)
      time_min  = travel_time_minutes(dist_km)
      edge_id   = "#{line_id}_SEG#{i}"
      from_id   = "#{line_id}_STOP#{i}"

      edges << {
        edge_id: edge_id,
        from_station: from_id,
        to_station: stop_id,
        mode: mode,
        line: line_id,
        travel_time_minutes: time_min,
        distance_km: dist_km,
        base_fare: payload[:baseFare].to_f,
        fare_per_km: payload[:farePerKm].to_f,
        accepted_payments: payload[:acceptedPayments] || payload["acceptedPayments"] || [],
        is_air_conditioned: payload[:isAirConditioned] || payload["isAirConditioned"] || false,
        crowd_factor: payload[:crowdFactor].to_f,
        reliability: payload[:reliability].to_f,
        bidirectional: true,
        direction: nil,
        polyline_coordinates: [],
        mk_directions_transport_type: mk_type_for(mode),
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    ActiveRecord::Base.transaction do
      # Insert stations — skip duplicates
      Station.upsert_all(stations, unique_by: :station_id, update_only: [:updated_at]) if stations.any?

      # Insert edges
      Edge.upsert_all(edges, unique_by: :edge_id, update_only: [:updated_at]) if edges.any?

      # Append lineID to transport_mode lines array
      TransportMode.where(id: mode)
                   .where.not("? = ANY(lines)", line_id)
                   .update_all("lines = array_append(lines, '#{line_id.gsub("'", "''")}')")

      bump_graph_version!
    end

    Result.new(
      success?: true,
      data: {
        line_id: line_id,
        stations_added: stations.length,
        edges_added: edges.length
      }
    )
  rescue => e
    Rails.logger.error("[GraphService#add_route] #{e.message}")
    Result.new(success?: false, errors: [{ field: "base", message: "Database write failed: #{e.message}" }])
  end

  # ── delete_route ─────────────────────────────────────────────────────────────

  def delete_route(line_id)
    station_count = 0
    edge_count    = 0

    ActiveRecord::Base.transaction do
      # Edges reference stations — delete edges first to avoid FK issues
      edge_count    = Edge.where(line: line_id).delete_all
      station_count = Station.where(line: line_id).delete_all

      # Remove lineID from transport_mode lines arrays
      TransportMode.where("? = ANY(lines)", line_id)
                   .update_all("lines = array_remove(lines, '#{line_id.gsub("'", "''")}')")

      bump_graph_version!
    end

    Result.new(
      success?: true,
      data: { line_id: line_id, stations_removed: station_count, edges_removed: edge_count }
    )
  rescue => e
    Rails.logger.error("[GraphService#delete_route] #{e.message}")
    Result.new(success?: false, errors: [{ field: "base", message: e.message }])
  end

  # ── assemble_graph ──────────────────────────────────────────────────────────
  # Builds the full JSON payload identical in shape to transit_graph_v3.json.
  # Used by GET /api/v1/graph.

  def assemble_graph
    meta     = GraphMeta.first!
    modes    = TransportMode.order(:position)
    payments = PaymentMethod.order(:id)
    peak     = PeakHourConfig.first
    fares    = FareMatrix.all
    stations = Station.order(:line, :station_id)
    edges    = Edge.order(:line, :edge_id)

    {
      version: meta.version,
      lastModified: meta.last_modified.iso8601,
      metadata: {
        region: meta.region,
        currency: meta.currency,
        schemaVersion: meta.schema_version,
        polylineNote: "polylineCoordinates define the static display shape of each edge. Fixed — never changes with traffic."
      },
      transportModes: modes.to_h { |m| [m.id, mode_json(m)] },
      paymentMethods: payments.to_h { |p| [p.id, payment_json(p)] },
      peakHourMultipliers: peak&.data || {},
      fareMatrix: fares.to_h { |f| [f.line_name, f.data] },
      stations: stations.map { |s| station_json(s) },
      edges: edges.map { |e| edge_json(e) }
    }
  end

  # ── graph_version ────────────────────────────────────────────────────────────

  def graph_version
    meta = GraphMeta.first!
    {
      version: meta.version,
      lastModified: meta.last_modified.iso8601,
      stationCount: Station.count,
      edgeCount: Edge.count
    }
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  private

  def validate(payload)
    errors = []
    stops  = payload[:stops] || payload["stops"] || []

    display_name = payload[:displayName] || payload["displayName"]
    errors << { field: "displayName", message: "Display name is required." } if display_name.blank?

    line_id = payload[:lineID] || payload["lineID"]
    if line_id.blank?
      errors << { field: "lineID", message: "Line ID is required." }
    elsif line_id.include?(" ")
      errors << { field: "lineID", message: "Line ID must not contain spaces." }
    elsif line_id !~ LINE_ID_RE
      errors << { field: "lineID", message: "Line ID must only contain uppercase letters, digits, and underscores." }
    elsif Station.exists?(line: line_id)
      errors << { field: "lineID", message: "Line ID '#{line_id}' already exists." }
    end

    mode = payload[:mode] || payload["mode"]
    valid_modes = TransportMode.pluck(:id)
    unless valid_modes.include?(mode)
      errors << { field: "mode",
                  message: "Mode '#{mode}' is invalid. Valid: #{valid_modes.join(", ")}." }
    end

    base_fare = (payload[:baseFare] || payload["baseFare"]).to_f
    errors << { field: "baseFare", message: "baseFare must be >= 0." } if base_fare.negative?

    fare_per_km = (payload[:farePerKm] || payload["farePerKm"]).to_f
    errors << { field: "farePerKm", message: "farePerKm must be >= 0." } if fare_per_km.negative?

    crowd_factor = (payload[:crowdFactor] || payload["crowdFactor"]).to_f
    unless (0.0..1.0).cover?(crowd_factor)
      errors << { field: "crowdFactor",
                  message: "crowdFactor must be between 0 and 1." }
    end

    reliability = (payload[:reliability] || payload["reliability"]).to_f
    unless (0.0..1.0).cover?(reliability)
      errors << { field: "reliability",
                  message: "reliability must be between 0 and 1." }
    end

    payments       = payload[:acceptedPayments] || payload["acceptedPayments"] || []
    valid_payments = PaymentMethod.pluck(:id)
    if payments.empty?
      errors << { field: "acceptedPayments", message: "At least one payment method is required." }
    else
      invalid = payments - valid_payments
      if invalid.any?
        errors << { field: "acceptedPayments",
                    message: "Unknown payment methods: #{invalid.join(", ")}." }
      end
    end

    open_time  = payload[:openTime]  || payload["openTime"]
    close_time = payload[:closeTime] || payload["closeTime"]
    if open_time.blank? || open_time !~ TIME_RE
      errors << { field: "openTime",
                  message: "openTime must be HH:mm format." }
    end
    if close_time.blank? || close_time !~ TIME_RE
      errors << { field: "closeTime",
                  message: "closeTime must be HH:mm format." }
    end

    if stops.length < 2
      errors << { field: "stops", message: "At least 2 stops are required." }
    else
      stops.each_with_index do |stop, i|
        lat = stop[:lat]&.to_f || stop["lat"]&.to_f
        lng = stop[:lng]&.to_f || stop["lng"]&.to_f
        if (stop[:name] || stop["name"]).blank?
          errors << { field: "stops[#{i}].name",
                      message: "Stop #{i + 1}: name is required." }
        end
        unless lat && (-90.0..90.0).cover?(lat)
          errors << { field: "stops[#{i}].lat",
                      message: "Stop #{i + 1}: lat must be between -90 and 90." }
        end
        unless lng && (-180.0..180.0).cover?(lng)
          errors << { field: "stops[#{i}].lng",
                      message: "Stop #{i + 1}: lng must be between -180 and 180." }
        end
        next unless lat && lng

        in_mm = lat.between?(MM_LAT_MIN, MM_LAT_MAX) && lng.between?(MM_LNG_MIN, MM_LNG_MAX)
        unless in_mm
          errors << { field: "stops[#{i}].coordinates",
                      message: "Stop #{i + 1}: coordinates (#{lat}, #{lng}) appear outside Metro Manila." }
        end
      end
    end

    errors
  end

  # ── Haversine — direct port of geo.ts ─────────────────────────────────────

  def haversine(lat1, lng1, lat2, lng2)
    d_lat = (lat2 - lat1) * Math::PI / 180
    d_lng = (lng2 - lng1) * Math::PI / 180
    a = (Math.sin(d_lat / 2)**2) +
        (Math.cos(lat1 * Math::PI / 180) *
        Math.cos(lat2 * Math::PI / 180) *
        (Math.sin(d_lng / 2)**2))
    EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  def travel_time_minutes(dist_km)
    [MIN_TRAVEL_TIME, dist_km / (AVG_SPEED_KMH / 60.0)].max
  end

  def derive_short_name(name)
    name.to_s.strip.split.first.to_s[0, 6].upcase
  end

  def mk_type_for(mode)
    { "train" => "train", "bus" => "bus", "jeepney" => "automobile",
      "e_jeepney" => "automobile", "tricycle" => "automobile" }.fetch(mode, "transit")
  end

  def bump_graph_version!
    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # ── JSON serializers ──────────────────────────────────────────────────────

  def mode_json(m)
    { id: m.id, displayName: m.display_name, pluralName: m.plural_name,
      sfSymbol: m.sf_symbol, colorHex: m.color_hex,
      mapLineWidthPt: m.map_line_width_pt.to_f, mapLineDash: m.map_line_dash,
      mkDirectionsTransportType: m.mk_directions_type,
      isUserSelectable: m.is_user_selectable, isAlwaysAllowed: m.is_always_allowed,
      lines: m.lines, defaultAcceptedPayments: m.default_accepted_payments,
      notes: m.notes }.merge(m.extra || {})
  end

  def payment_json(p)
    { id: p.id, displayName: p.display_name, sfSymbol: p.sf_symbol,
      colorHex: p.color_hex, isDefault: p.is_default,
      acceptedByModes: p.accepted_by_modes, notes: p.notes }
  end

  def station_json(s)
    { id: s.station_id, name: s.name, shortName: s.short_name,
      line: s.line, type: s.type,
      coordinates: { lat: s.lat.to_f, lng: s.lng.to_f },
      isTerminal: s.is_terminal, isInterchange: s.is_interchange,
      amenities: s.amenities,
      operatingHours: { open: s.open_time, close: s.close_time } }
  end

  def edge_json(e)
    h = { id: e.edge_id, from: e.from_station, to: e.to_station,
          mode: e.mode, line: e.line,
          travelTimeMinutes: e.travel_time_minutes.to_f,
          distanceKm: e.distance_km.to_f,
          baseFare: e.base_fare.to_f, farePerKm: e.fare_per_km.to_f,
          acceptedPayments: e.accepted_payments,
          isAirConditioned: e.is_air_conditioned,
          crowdFactor: e.crowd_factor.to_f, reliability: e.reliability.to_f,
          bidirectional: e.bidirectional,
          polylineCoordinates: e.polyline_coordinates,
          mkDirectionsTransportType: e.mk_directions_transport_type }
    h[:direction] = e.direction if e.direction.present?
    h
  end
end
