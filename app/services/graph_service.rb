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

  # Inserts a single new stop immediately before/after an existing station on the
  # same line, splitting (or extending) the edge chain around it. See `#insert_stop`.
  def self.insert_stop(payload)
    new.insert_stop(payload)
  end

  # Removes a single stop from a line, merging its two adjacent edges (or just
  # dropping the one adjacent edge if it was a terminal). See `#remove_stop`.
  def self.remove_stop(station_id)
    new.remove_stop(station_id)
  end

  def self.assemble_graph
    new.assemble_graph
  end

  def self.graph_version
    new.graph_version
  end

  # Public entry point for controllers that mutate a single station/edge outside
  # add_route/delete_route (e.g. EdgesController#update) and need to bump the
  # version themselves. add_route/delete_route call the private instance method
  # directly since they already run inside their own transaction.
  def self.bump_version!
    new.send(:bump_graph_version!)
  end

  # Haversine distance (km) summed over consecutive polyline points. Public so
  # controllers can recompute distance_km when a client overwrites polyline_coordinates.
  def self.polyline_distance_km(points)
    new.send(:polyline_distance_km, points)
  end

  # ── add_route ───────────────────────────────────────────────────────────────

  def add_route(payload)
    errors = validate(payload)
    return Result.new(success?: false, errors: errors) if errors.any?

    passes   = normalize_passes(payload)
    line_id  = payload[:lineID] || payload["lineID"]
    mode     = payload[:mode]   || payload["mode"]
    stations = []
    edges    = []

    passes.each do |pass|
      direction = pass[:direction]
      stops     = pass[:stops]
      # A direction-less pass keeps the original unscoped IDs (`LINE_STOP1`, `LINE_SEG1`)
      # so existing routes/web-admin payloads are unaffected. A northbound/southbound
      # pass gets its own ID namespace (`LINE_NB_STOP1`) since those stops are modeled as
      # independent stations (real jeepney/bus stops on opposite one-way streets usually
      # sit at different corners) — this also lets both passes coexist under one lineID
      # without station_id collisions.
      tag       = direction_tag(direction)
      id_prefix = tag ? "#{line_id}_#{tag}" : line_id

      stops.each_with_index do |stop, i|
        stop_name  = stop[:name] || stop["name"]
        stop_lat   = (stop[:lat] || stop["lat"]).to_f
        stop_lng   = (stop[:lng] || stop["lng"]).to_f
        short_name = stop[:shortName] || stop["shortName"] || derive_short_name(stop_name)
        stop_id    = "#{id_prefix}_STOP#{i + 1}"

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
        prev_lat  = (prev_stop[:lat] || prev_stop["lat"]).to_f
        prev_lng  = (prev_stop[:lng] || prev_stop["lng"]).to_f
        edge_id   = "#{id_prefix}_SEG#{i}"
        from_id   = "#{id_prefix}_STOP#{i}"

        # Optional per-segment polyline (road-following points from the client, e.g. an
        # MKDirections-snapped trace) — when present, use its actual length instead of the
        # prev/current stop haversine chord, and persist the points instead of discarding
        # them. Falls back to a straight two-point chord for callers that don't send one
        # (existing web-admin payloads keep working unchanged).
        raw_polyline = stop[:polyline] || stop["polyline"] || []
        poly_points = raw_polyline.filter_map do |p|
          lat = p[:lat] || p["lat"]
          lng = p[:lng] || p["lng"]
          next if lat.nil? || lng.nil?
          { lat: lat.to_f, lng: lng.to_f }
        end

        if poly_points.length >= 2
          dist_km = poly_points.each_cons(2).sum { |a, b| haversine(a[:lat], a[:lng], b[:lat], b[:lng]) }
        else
          poly_points = []
          dist_km = haversine(prev_lat, prev_lng, stop_lat, stop_lng)
        end
        time_min = travel_time_minutes(dist_km)

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
          # A directional pass is a one-way leg — no synthetic reverse edge should ever be
          # inferred from it, so bidirectional is false whenever a direction is set. A
          # direction-less pass keeps today's behavior (bidirectional true, no direction).
          bidirectional: direction.nil?,
          direction: direction,
          polyline_coordinates: poly_points,
          mk_directions_transport_type: mk_type_for(mode),
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # Closing (loop-back) segment — only meaningful for a direction-less pass (a
      # northbound/southbound leg is inherently one-way, so the client never sends
      # closesLoop for those); honored here regardless of direction since nothing
      # downstream assumes otherwise.
      next unless pass[:closes_loop] && stops.length >= 2

      first_stop = stops.first
      last_stop  = stops.last
      first_lat  = (first_stop[:lat] || first_stop["lat"]).to_f
      first_lng  = (first_stop[:lng] || first_stop["lng"]).to_f
      last_lat   = (last_stop[:lat]  || last_stop["lat"]).to_f
      last_lng   = (last_stop[:lng]  || last_stop["lng"]).to_f

      closing_points = pass[:closing_polyline].filter_map do |p|
        lat = p[:lat] || p["lat"]
        lng = p[:lng] || p["lng"]
        next if lat.nil? || lng.nil?
        { lat: lat.to_f, lng: lng.to_f }
      end

      if closing_points.length >= 2
        closing_dist = closing_points.each_cons(2).sum { |a, b| haversine(a[:lat], a[:lng], b[:lat], b[:lng]) }
      else
        closing_points = []
        closing_dist = haversine(last_lat, last_lng, first_lat, first_lng)
      end

      edges << {
        edge_id: "#{id_prefix}_SEG#{stops.length}",
        from_station: "#{id_prefix}_STOP#{stops.length}",
        to_station: "#{id_prefix}_STOP1",
        mode: mode,
        line: line_id,
        travel_time_minutes: travel_time_minutes(closing_dist),
        distance_km: closing_dist,
        base_fare: payload[:baseFare].to_f,
        fare_per_km: payload[:farePerKm].to_f,
        accepted_payments: payload[:acceptedPayments] || payload["acceptedPayments"] || [],
        is_air_conditioned: payload[:isAirConditioned] || payload["isAirConditioned"] || false,
        crowd_factor: payload[:crowdFactor].to_f,
        reliability: payload[:reliability].to_f,
        bidirectional: direction.nil?,
        direction: direction,
        polyline_coordinates: closing_points,
        mk_directions_transport_type: mk_type_for(mode),
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    ActiveRecord::Base.transaction do
      # Insert stations — skip duplicates. `record_timestamps: false` because the hashes
      # already set created_at/updated_at explicitly; without this, Rails 7.2's upsert_all
      # additionally injects its own `updated_at` into the ON CONFLICT SET clause, colliding
      # with the one already in `update_only:` and producing an invalid "multiple
      # assignments to same column" SQL statement (discovered while testing insert/remove
      # stop — this silently broke add_route entirely, not just this new feature).
      Station.upsert_all(stations, unique_by: :station_id, update_only: [:updated_at], record_timestamps: false) if stations.any?

      # Insert edges
      Edge.upsert_all(edges, unique_by: :edge_id, update_only: [:updated_at], record_timestamps: false) if edges.any?

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

  # ── insert_stop / remove_stop ────────────────────────────────────────────────
  #
  # Deliberately scoped to the one case this can be done safely and unambiguously:
  #
  # 1. Never on `mode == "train"` — MRT/LRT stations are shared by both directions'
  #    edges (northbound and southbound both touch the same physical station).
  #    Splitting/merging just one direction's edge would leave the other direction
  #    silently bypassing the change, an asymmetric graph. Out of scope.
  # 2. Never on a closed-loop route — the closing edge is real recorded geometry
  #    between two specific endpoints; if a terminal shifts, there's no principled
  #    way to auto-repair that geometry. Detected via edge-count >= station-count.
  # 3. Only on stations following the auto-generated "<prefix>_STOP<n>" convention
  #    (i.e. routes built via the iOS Loop Creator) — that's what makes sequential
  #    renumbering well-defined. Hand-authored named stations (trains) don't use
  #    this convention and are already excluded by #1 anyway.
  #
  # Renumbering only touches `stations`/`edges`. It does NOT chase down every other
  # table that might reference a station/edge id by string (saved_routes,
  # route_plan_events, ar_world_maps, incidents) — there's no DB-level FK, so a
  # renumbered id could leave those pointing at a since-renamed station. Accepted
  # tradeoff: renumbering was chosen over keeping ids stable.

  def insert_stop(payload)
    ref_id   = payload[:referenceStationId] || payload["referenceStationId"]
    position = (payload[:position] || payload["position"]).to_s
    name     = (payload[:name] || payload["name"]).to_s.strip
    lat_raw  = payload[:lat] || payload["lat"]
    lng_raw  = payload[:lng] || payload["lng"]

    errors = validate_insert_stop(ref_id: ref_id, position: position, name: name, lat: lat_raw, lng: lng_raw)
    return Result.new(success?: false, errors: errors) if errors.any?

    lat = lat_raw.to_f
    lng = lng_raw.to_f
    ref = Station.find_by(station_id: ref_id)
    return Result.new(success?: false, errors: [{ field: "referenceStationId", message: "Reference station not found." }]) unless ref
    if ref.type == "train"
      return Result.new(success?: false, errors: [{ field: "mode", message: "Inserting stops isn't supported for train lines (shared bidirectional stations)." }])
    end

    line_id = ref.line
    prefix  = sequence_prefix(ref.station_id)
    unless prefix
      return Result.new(success?: false, errors: [{ field: "referenceStationId",
                         message: "This station doesn't use the standard stop-numbering scheme; inserting isn't supported for it." }])
    end

    ordered = ordered_chain(line_id, prefix)
    n = ordered.length
    if scoped_seg_count(line_id, prefix) >= n
      return Result.new(success?: false, errors: [{ field: "base",
                         message: "This route closes into a loop; inserting stops on closed-loop routes isn't supported yet." }])
    end

    idx = ordered.index { |s| s.station_id == ref.station_id }
    p = position == "after" ? idx + 2 : idx + 1 # 1-based target position of the new stop

    short_name = (payload[:shortName] || payload["shortName"]).presence || derive_short_name(name)
    open_time  = (payload[:openTime]  || payload["openTime"]).presence  || ref.open_time
    close_time = (payload[:closeTime] || payload["closeTime"]).presence || ref.close_time
    new_station_id = "#{prefix}_STOP#{p}"
    old_split_edge = (p > 1 && p <= n) ? Edge.find_by(edge_id: "#{prefix}_SEG#{p - 1}") : nil

    ActiveRecord::Base.transaction do
      # Shift everything at/after the insertion point up one slot — highest index
      # first so a rename target is always vacated before something else claims it.
      n.downto(p) do |i|
        old_id = "#{prefix}_STOP#{i}"
        new_id = "#{prefix}_STOP#{i + 1}"
        Station.where(station_id: old_id).update_all(station_id: new_id)
        Edge.where(from_station: old_id).update_all(from_station: new_id)
        Edge.where(to_station: old_id).update_all(to_station: new_id)
      end
      (n - 1).downto(p) do |i|
        Edge.where(edge_id: "#{prefix}_SEG#{i}").update_all(edge_id: "#{prefix}_SEG#{i + 1}")
      end

      Station.create!(
        station_id: new_station_id, name: name, short_name: short_name,
        line: line_id, type: ref.type, lat: lat, lng: lng,
        is_terminal: false, is_interchange: false, amenities: [],
        open_time: open_time, close_time: close_time
      )

      if old_split_edge
        prev_id = "#{prefix}_STOP#{p - 1}"
        next_id = "#{prefix}_STOP#{p + 1}" # was STOP(p), shifted above
        prev_lat, prev_lng = coords_of(prev_id)
        next_lat, next_lng = coords_of(next_id)
        poly = old_split_edge.polyline_coordinates || []
        split_idx = split_point_index(poly, lat, lng)
        first_half  = poly.empty? ? [] : poly[0..split_idx]
        second_half = poly.empty? ? [] : poly[split_idx..-1]
        dist1 = poly_length_km(first_half)  || haversine(prev_lat, prev_lng, lat, lng)
        dist2 = poly_length_km(second_half) || haversine(lat, lng, next_lat, next_lng)

        Edge.where(edge_id: old_split_edge.edge_id).delete_all
        Edge.create!(edge_attrs(old_split_edge, edge_id: "#{prefix}_SEG#{p - 1}",
                                from: prev_id, to: new_station_id, distance_km: dist1, polyline: first_half))
        Edge.create!(edge_attrs(old_split_edge, edge_id: "#{prefix}_SEG#{p}",
                                from: new_station_id, to: next_id, distance_km: dist2, polyline: second_half))
      elsif p == 1
        template = Edge.find_by(edge_id: "#{prefix}_SEG2") # old SEG1, already shifted
        next_id = "#{prefix}_STOP2"
        next_lat, next_lng = coords_of(next_id)
        dist = haversine(lat, lng, next_lat, next_lng)
        Edge.create!(edge_attrs(template, edge_id: "#{prefix}_SEG1",
                                from: new_station_id, to: next_id, distance_km: dist, polyline: [],
                                mode: ref.type, line: line_id))
      else # p == n + 1 — append after the last stop
        template = Edge.find_by(edge_id: "#{prefix}_SEG#{n - 1}")
        prev_id = "#{prefix}_STOP#{n}"
        prev_lat, prev_lng = coords_of(prev_id)
        dist = haversine(prev_lat, prev_lng, lat, lng)
        Edge.create!(edge_attrs(template, edge_id: "#{prefix}_SEG#{n}",
                                from: prev_id, to: new_station_id, distance_km: dist, polyline: [],
                                mode: ref.type, line: line_id))
      end

      recompute_terminals!(line_id, prefix)
      bump_graph_version!
    end

    Result.new(success?: true, data: { line_id: line_id, station_id: new_station_id })
  rescue => e
    Rails.logger.error("[GraphService#insert_stop] #{e.message}")
    Result.new(success?: false, errors: [{ field: "base", message: "Database write failed: #{e.message}" }])
  end

  def remove_stop(station_id)
    station = Station.find_by(station_id: station_id)
    return Result.new(success?: false, errors: [{ field: "id", message: "Station not found." }]) unless station
    if station.type == "train"
      return Result.new(success?: false, errors: [{ field: "mode", message: "Removing stops isn't supported for train lines (shared bidirectional stations)." }])
    end

    line_id = station.line
    prefix  = sequence_prefix(station.station_id)
    unless prefix
      return Result.new(success?: false, errors: [{ field: "id",
                         message: "This station doesn't use the standard stop-numbering scheme; removing isn't supported for it." }])
    end

    ordered = ordered_chain(line_id, prefix)
    n = ordered.length
    if n <= 2
      return Result.new(success?: false, errors: [{ field: "base", message: "A route needs at least 2 stops — delete the whole route instead." }])
    end
    if scoped_seg_count(line_id, prefix) >= n
      return Result.new(success?: false, errors: [{ field: "base",
                         message: "This route closes into a loop; removing stops on closed-loop routes isn't supported yet." }])
    end

    p = ordered.index { |s| s.station_id == station.station_id } + 1 # 1-based

    ActiveRecord::Base.transaction do
      if p == 1
        Edge.where(edge_id: "#{prefix}_SEG1").delete_all
        Station.where(station_id: "#{prefix}_STOP1").delete_all
        2.upto(n) do |i|
          old_id = "#{prefix}_STOP#{i}"
          new_id = "#{prefix}_STOP#{i - 1}"
          Station.where(station_id: old_id).update_all(station_id: new_id)
          Edge.where(from_station: old_id).update_all(from_station: new_id)
          Edge.where(to_station: old_id).update_all(to_station: new_id)
        end
        2.upto(n - 1) do |i|
          Edge.where(edge_id: "#{prefix}_SEG#{i}").update_all(edge_id: "#{prefix}_SEG#{i - 1}")
        end
      elsif p == n
        Edge.where(edge_id: "#{prefix}_SEG#{n - 1}").delete_all
        Station.where(station_id: "#{prefix}_STOP#{n}").delete_all
      else
        edge1 = Edge.find_by(edge_id: "#{prefix}_SEG#{p - 1}") # prev -> removed
        edge2 = Edge.find_by(edge_id: "#{prefix}_SEG#{p}")     # removed -> next
        poly1 = edge1&.polyline_coordinates || []
        poly2 = edge2&.polyline_coordinates || []
        # Drop the first coordinate of the second half — it duplicates the shared
        # junction point at the station being removed (same invariant as stitching
        # polylines across merged legs elsewhere in the app).
        merged_poly = (poly1.empty? && poly2.empty?) ? [] : (poly1 + poly2.drop(1))
        merged_dist = edge1&.distance_km.to_f + edge2&.distance_km.to_f
        merged_time = edge1&.travel_time_minutes.to_f + edge2&.travel_time_minutes.to_f
        prev_id = "#{prefix}_STOP#{p - 1}"

        Edge.where(edge_id: "#{prefix}_SEG#{p - 1}").delete_all
        Edge.where(edge_id: "#{prefix}_SEG#{p}").delete_all
        Station.where(station_id: "#{prefix}_STOP#{p}").delete_all

        (p + 1).upto(n) do |i|
          old_id = "#{prefix}_STOP#{i}"
          new_id = "#{prefix}_STOP#{i - 1}"
          Station.where(station_id: old_id).update_all(station_id: new_id)
          Edge.where(from_station: old_id).update_all(from_station: new_id)
          Edge.where(to_station: old_id).update_all(to_station: new_id)
        end
        (p + 1).upto(n - 1) do |i|
          Edge.where(edge_id: "#{prefix}_SEG#{i}").update_all(edge_id: "#{prefix}_SEG#{i - 1}")
        end

        new_next_id = "#{prefix}_STOP#{p}" # was STOP(p+1), just renamed above
        Edge.create!(
          edge_id: "#{prefix}_SEG#{p - 1}", from_station: prev_id, to_station: new_next_id,
          mode: edge1&.mode || edge2&.mode, line: line_id,
          travel_time_minutes: merged_time.positive? ? merged_time : travel_time_minutes(merged_dist),
          distance_km: merged_dist,
          base_fare: edge1&.base_fare || edge2&.base_fare || 0,
          fare_per_km: edge1&.fare_per_km || edge2&.fare_per_km || 0,
          accepted_payments: edge1&.accepted_payments || edge2&.accepted_payments || [],
          is_air_conditioned: edge1&.is_air_conditioned || edge2&.is_air_conditioned || false,
          crowd_factor: edge1&.crowd_factor || edge2&.crowd_factor || 0.5,
          reliability: edge1&.reliability || edge2&.reliability || 0.9,
          bidirectional: true, direction: nil,
          polyline_coordinates: merged_poly,
          mk_directions_transport_type: edge1&.mk_directions_transport_type || edge2&.mk_directions_transport_type || mk_type_for(edge1&.mode)
        )
      end

      recompute_terminals!(line_id, prefix)
      bump_graph_version!
    end

    Result.new(success?: true, data: { line_id: line_id })
  rescue => e
    Rails.logger.error("[GraphService#remove_stop] #{e.message}")
    Result.new(success?: false, errors: [{ field: "base", message: "Database write failed: #{e.message}" }])
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
      enforceOperatingHours: meta.enforce_operating_hours,
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
    passes = normalize_passes(payload)

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
      # Not an outright rejection — this is also the path for adding the missing
      # northbound/southbound direction to a route that already has the other one.
      # #existing_line_append_error decides which case it actually is.
      append_error = existing_line_append_error(line_id, passes)
      errors << { field: "lineID", message: append_error } if append_error
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

    seen_directions = []
    passes.each_with_index do |pass, p_idx|
      direction = pass[:direction]
      stops     = pass[:stops]
      label     = direction ? "#{direction} pass" : (passes.length > 1 ? "pass #{p_idx + 1}" : "route")

      unless direction.nil? || %w[northbound southbound].include?(direction)
        errors << { field: "passes[#{p_idx}].direction",
                    message: "direction must be \"northbound\", \"southbound\", or omitted." }
      end

      if direction && seen_directions.include?(direction)
        errors << { field: "passes[#{p_idx}].direction",
                    message: "Direction '#{direction}' was submitted more than once." }
      end
      seen_directions << direction if direction

      if stops.length < 2
        errors << { field: "passes[#{p_idx}].stops", message: "#{label.capitalize}: at least 2 stops are required." }
      else
        stops.each_with_index do |stop, i|
          lat = stop[:lat]&.to_f || stop["lat"]&.to_f
          lng = stop[:lng]&.to_f || stop["lng"]&.to_f
          if (stop[:name] || stop["name"]).blank?
            errors << { field: "passes[#{p_idx}].stops[#{i}].name",
                        message: "#{label.capitalize}, stop #{i + 1}: name is required." }
          end
          unless lat && (-90.0..90.0).cover?(lat)
            errors << { field: "passes[#{p_idx}].stops[#{i}].lat",
                        message: "#{label.capitalize}, stop #{i + 1}: lat must be between -90 and 90." }
          end
          unless lng && (-180.0..180.0).cover?(lng)
            errors << { field: "passes[#{p_idx}].stops[#{i}].lng",
                        message: "#{label.capitalize}, stop #{i + 1}: lng must be between -180 and 180." }
          end
          next unless lat && lng

          in_mm = lat.between?(MM_LAT_MIN, MM_LAT_MAX) && lng.between?(MM_LNG_MIN, MM_LNG_MAX)
          unless in_mm
            errors << { field: "passes[#{p_idx}].stops[#{i}].coordinates",
                        message: "#{label.capitalize}, stop #{i + 1}: coordinates (#{lat}, #{lng}) appear outside Metro Manila." }
          end

          polyline = stop[:polyline] || stop["polyline"]
          next unless polyline.present?

          polyline.each_with_index do |p, j|
            p_lat = p[:lat]&.to_f || p["lat"]&.to_f
            p_lng = p[:lng]&.to_f || p["lng"]&.to_f
            unless p_lat && (-90.0..90.0).cover?(p_lat) && p_lng && (-180.0..180.0).cover?(p_lng)
              errors << { field: "passes[#{p_idx}].stops[#{i}].polyline[#{j}]",
                          message: "#{label.capitalize}, stop #{i + 1}: polyline point #{j + 1} has an invalid coordinate." }
            end
          end
        end
      end
    end

    errors
  end

  # Accepts either the new multi-pass shape (`passes: [{direction:, stops:, closesLoop:,
  # closingPolyline:}, ...]` — used by the iOS Loop Creator to submit an optional
  # northbound + southbound pair in one call) or the legacy flat shape (top-level
  # `stops`/`closesLoop`/`closingPolyline`/`direction`, still sent by the web admin) —
  # wrapped here into a single implicit pass so both shapes flow through identical code.
  def normalize_passes(payload)
    raw_passes = payload[:passes] || payload["passes"]
    raw_passes = [
      {
        direction: payload[:direction] || payload["direction"],
        stops: payload[:stops] || payload["stops"] || [],
        closesLoop: payload[:closesLoop] || payload["closesLoop"],
        closingPolyline: payload[:closingPolyline] || payload["closingPolyline"]
      }
    ] if raw_passes.blank?

    raw_passes.map do |pass|
      {
        direction: pass[:direction] || pass["direction"],
        stops: pass[:stops] || pass["stops"] || [],
        closes_loop: pass[:closesLoop] || pass["closesLoop"],
        closing_polyline: pass[:closingPolyline] || pass["closingPolyline"] || []
      }
    end
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

  def polyline_distance_km(points)
    pts = points.filter_map do |p|
      lat = p[:lat] || p["lat"]
      lng = p[:lng] || p["lng"]
      next if lat.nil? || lng.nil?
      { lat: lat.to_f, lng: lng.to_f }
    end
    return nil if pts.length < 2

    pts.each_cons(2).sum { |a, b| haversine(a[:lat], a[:lng], b[:lat], b[:lng]) }
  end

  def derive_short_name(name)
    name.to_s.strip.split.first.to_s[0, 6].upcase
  end

  def mk_type_for(mode)
    { "train" => "train", "bus" => "bus", "jeepney" => "automobile",
      "e_jeepney" => "automobile", "tricycle" => "automobile" }.fetch(mode, "transit")
  end

  def direction_tag(direction)
    { "northbound" => "NB", "southbound" => "SB" }[direction]
  end

  def bump_graph_version!
    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # ── insert_stop / remove_stop helpers ─────────────────────────────────────

  def validate_insert_stop(ref_id:, position:, name:, lat:, lng:)
    errors = []
    errors << { field: "referenceStationId", message: "referenceStationId is required." } if ref_id.blank?
    errors << { field: "position", message: "position must be \"before\" or \"after\"." } unless %w[before after].include?(position)
    errors << { field: "name", message: "name is required." } if name.blank?

    lat_f = lat.present? ? lat.to_f : nil
    lng_f = lng.present? ? lng.to_f : nil
    errors << { field: "lat", message: "lat must be between -90 and 90." } unless lat_f && (-90.0..90.0).cover?(lat_f)
    errors << { field: "lng", message: "lng must be between -180 and 180." } unless lng_f && (-180.0..180.0).cover?(lng_f)
    if lat_f && lng_f && !(lat_f.between?(MM_LAT_MIN, MM_LAT_MAX) && lng_f.between?(MM_LNG_MIN, MM_LNG_MAX))
      errors << { field: "coordinates", message: "Coordinates (#{lat_f}, #{lng_f}) appear outside Metro Manila." }
    end
    errors
  end

  # Decides whether add_route may write into an *existing* line_id — the only
  # legitimate case is adding the one missing direction (northbound/southbound) to
  # a route that already has the other. Returns nil when that's exactly what this
  # payload is doing (safe to proceed); otherwise a user-facing rejection message.
  #
  # Never allowed for train mode: MRT/LRT stations are shared by both directions'
  # edges already (see the same reasoning in insert_stop/remove_stop above) — the
  # concept of "add the missing direction" doesn't apply to them the same way, and
  # this tool isn't how train lines get authored anyway (they're seeded, not
  # admin-drawn).
  def existing_line_append_error(line_id, passes)
    existing_mode = Station.where(line: line_id).pick(:type)
    return "Train lines can't be extended via Add Route." if existing_mode == "train"

    existing_directions = Edge.where(line: line_id).distinct.pluck(:direction).compact
    if existing_directions.empty?
      return "Line ID '#{line_id}' already exists (recorded without a direction) — pick a different Line ID."
    end

    new_directions = passes.filter_map { |p| p[:direction] }
    if new_directions.empty?
      return "Line ID '#{line_id}' already exists — pick a different Line ID, or record a Northbound/Southbound " \
             "direction to add it to that route."
    end

    colliding = new_directions & existing_directions
    return "#{colliding.first.capitalize} already exists for '#{line_id}'." if colliding.any?

    nil # Genuinely new direction(s) for an existing, direction-using, non-train line — allow it.
  end

  # The shared prefix of an auto-generated "<prefix>_STOP<n>" station id, or nil
  # for a hand-authored id (e.g. a named MRT-3 station) that doesn't follow it.
  def sequence_prefix(station_id)
    station_id[/\A(.+)_STOP\d+\z/, 1]
  end

  # All stations for `prefix` on `line_id`, ordered by their STOP<n> suffix —
  # simpler and more robust than walking the edge chain (which a closed loop's
  # wrap-around edge would otherwise confuse).
  def ordered_chain(line_id, prefix)
    Station.where(line: line_id)
           .where("station_id ~ ?", "^#{Regexp.escape(prefix)}_STOP[0-9]+$")
           .to_a
           .sort_by { |s| s.station_id[/_STOP(\d+)\z/, 1].to_i }
  end

  # Count of SEG-convention edges in this scope — used to detect a closed loop
  # (n stations should have exactly n-1 chain edges in an open path; n or more
  # means a wrap-around closing edge exists).
  def scoped_seg_count(line_id, prefix)
    Edge.where(line: line_id).where("edge_id ~ ?", "^#{Regexp.escape(prefix)}_SEG[0-9]+$").count
  end

  def coords_of(station_id)
    s = Station.find(station_id)
    [s.lat.to_f, s.lng.to_f]
  end

  # Index of the polyline point nearest (lat, lng) — same "closest existing point"
  # approach as the iOS admin polyline editor's insert/move tool.
  def split_point_index(points, lat, lng)
    return 0 if points.empty?
    points.each_with_index.min_by do |p, _|
      p_lat = (p[:lat] || p["lat"]).to_f
      p_lng = (p[:lng] || p["lng"]).to_f
      ((p_lat - lat)**2) + ((p_lng - lng)**2)
    end.last
  end

  def poly_length_km(points)
    pts = (points || []).filter_map do |p|
      lat = p[:lat] || p["lat"]
      lng = p[:lng] || p["lng"]
      next if lat.nil? || lng.nil?
      { lat: lat.to_f, lng: lng.to_f }
    end
    return nil if pts.length < 2
    pts.each_cons(2).sum { |a, b| haversine(a[:lat], a[:lng], b[:lat], b[:lng]) }
  end

  # Builds a new edge's attribute hash, inheriting fare/quality/vehicle metadata
  # from `template` (an existing edge on the same line) since that metadata
  # describes the line as a whole, not any one segment.
  def edge_attrs(template, edge_id:, from:, to:, distance_km:, polyline:, mode: nil, line: nil)
    {
      edge_id: edge_id, from_station: from, to_station: to,
      mode: mode || template&.mode, line: line || template&.line,
      travel_time_minutes: travel_time_minutes(distance_km),
      distance_km: distance_km,
      base_fare: template&.base_fare || 0,
      fare_per_km: template&.fare_per_km || 0,
      accepted_payments: template&.accepted_payments || [],
      is_air_conditioned: template&.is_air_conditioned || false,
      crowd_factor: template&.crowd_factor || 0.5,
      reliability: template&.reliability || 0.9,
      bidirectional: true,
      direction: nil,
      polyline_coordinates: polyline,
      mk_directions_transport_type: template&.mk_directions_transport_type || mk_type_for(mode || template&.mode)
    }
  end

  # Recomputes is_terminal for every station in this scope after an insert/remove
  # shifts what the first/last stop is.
  def recompute_terminals!(line_id, prefix)
    ordered = ordered_chain(line_id, prefix)
    ordered.each_with_index do |s, i|
      is_term = i.zero? || i == ordered.length - 1
      s.update_column(:is_terminal, is_term) if s.is_terminal != is_term
    end
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
