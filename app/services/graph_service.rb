# app/services/graph_service.rb
#
# Ports all transit graph write logic from the Hono microservice into Rails.
# Replaces: src/routes/addRoute.ts, src/geo.ts, src/validation.ts, src/graph.ts
#
# Thread safety: ActiveRecord transactions + DB-level constraints replace the
# in-process async mutex from the Hono service. Postgres handles concurrent
# writes correctly; no in-process mutex needed in Rails with a proper DB.

class GraphService
  EARTH_RADIUS_KM  = 6371.0
  MIN_TRAVEL_TIME  = 2.0 # minutes
  # Average speed in km/h per mode for an edge shorter than EXPRESS_GAP_KM.
  SPEED_KMH_BY_MODE = { "bus" => 22.0, "jeepney" => 16.0, "tricycle" => 15.0, "train" => 30.0 }.freeze
  DEFAULT_SPEED_KMH = 22.0
  ROAD_MODES        = %w[bus jeepney tricycle].freeze
  # A road edge at least EXPRESS_GAP_KM long runs on an expressway at EXPRESS_SPEED_KMH.
  EXPRESS_GAP_KM    = 5.0
  EXPRESS_SPEED_KMH = 45.0
  # A stop with the same name this close on the same chain is the same stop.
  DUPLICATE_STOP_RADIUS_M = 5.0

  # Rule for a new line id: uppercase, digits, single underscores. No hyphen, no dot.
  NEW_LINE_ID_RE    = /\A[A-Z][A-Z0-9]*(_[A-Z0-9]+)*\z/
  # Rule for a line id that already has stations. It still accepts dots, e.g. "STACRUZ.LRT_BUENDIA".
  LEGACY_LINE_ID_RE = /\A[A-Z0-9_.]+\z/
  # A generated stop id: the chain, then `_STOP<n>` (legacy) or `_S<n>`.
  STOP_ID_RE  = /\A(.+)_(?:STOP|S)(\d+)\z/
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

    passes       = normalize_passes(payload)
    line_id      = payload[:lineID]     || payload["lineID"]
    mode         = payload[:mode]       || payload["mode"]
    display_name = payload[:displayName] || payload["displayName"]
    stations = []
    edges    = []

    ActiveRecord::Base.transaction do
      # The line row is locked until commit, so two writers cannot take the same stop number.
      line_record = lock_line!(line_id, display_name: display_name, mode: mode)
      last_stop_number = line_record.last_stop_number

      passes.each do |pass|
        direction = pass[:direction]
        stops     = pass[:stops]
        # One-wayness used to be derived from the direction label (`bidirectional:
        # direction.nil?`), which made the two inseparable: an untagged route was always
        # two-way. That forced any genuinely one-way route with no meaningful compass
        # direction — a jeepney circuit that runs out to a terminus and back along the
        # same corridor on the *other* side of the road — to either invent a direction
        # tag or accept reverse edges. Reverse edges there are actively wrong: they let
        # the router walk the outbound stop sequence backwards and tell a homebound rider
        # to alight at a stop that only serves outbound traffic.
        #
        # An explicit `bidirectional` on the pass now wins; when it's absent the old rule
        # still applies, so existing payloads (iOS Loop Creator, web admin flat shape)
        # and every route already in the database behave exactly as before.
        bidirectional = pass[:bidirectional].nil? ? direction.nil? : pass[:bidirectional]
        # A direction-less pass uses the line id as its chain (`LINE_S1`). A northbound or
        # southbound pass gets its own chain (`LINE_NB_S1`), so both passes share one line id.
        tag       = direction_tag(direction)
        id_prefix = tag ? "#{line_id}_#{tag}" : line_id

        stop_ids = []
        stops.each_with_index do |stop, i|
          stop_name  = stop[:name] || stop["name"]
          stop_lat   = (stop[:lat] || stop["lat"]).to_f
          stop_lng   = (stop[:lng] || stop["lng"]).to_f
          short_name = stop[:shortName] || stop["shortName"] || derive_short_name(stop_name)
          stop_id    = "#{id_prefix}_S#{last_stop_number += 1}"
          stop_ids << stop_id

          stations << {
            station_id: stop_id,
            name: stop_name,
            short_name: short_name,
            line: line_id,
            sequence: i + 1,
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
          from_id   = stop_ids[i - 1]
          edge_id   = line_edge_id(from_id, stop_id)

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
          time_min = travel_time_minutes(dist_km, mode)

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
            bidirectional: bidirectional,
            direction: direction,
            polyline_coordinates: poly_points,
            mk_directions_transport_type: mk_type_for(mode),
            is_road_snapped: pass[:is_road_snapped],
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        # Closing (loop-back) segment — only meaningful for a direction-less pass (a
        # northbound/southbound leg is inherently one-way, so the client never sends
        # closesLoop for those); honored here regardless of direction since nothing
        # downstream assumes otherwise.
        next unless pass[:closes_loop] && stops.length >= 2

        first_id   = stop_ids.first
        last_id    = stop_ids.last
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
          edge_id: line_edge_id(last_id, first_id),
          from_station: last_id,
          to_station: first_id,
          mode: mode,
          line: line_id,
          travel_time_minutes: travel_time_minutes(closing_dist, mode),
          distance_km: closing_dist,
          base_fare: payload[:baseFare].to_f,
          fare_per_km: payload[:farePerKm].to_f,
          accepted_payments: payload[:acceptedPayments] || payload["acceptedPayments"] || [],
          is_air_conditioned: payload[:isAirConditioned] || payload["isAirConditioned"] || false,
          crowd_factor: payload[:crowdFactor].to_f,
          reliability: payload[:reliability].to_f,
          bidirectional: bidirectional,
          direction: direction,
          polyline_coordinates: closing_points,
          mk_directions_transport_type: mk_type_for(mode),
          is_road_snapped: pass[:is_road_snapped],
          created_at: Time.current,
          updated_at: Time.current
        }
      end

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

      # Persists the display name for GET /api/v1/graph's `lines` section. A repeated lineID
      # (the "extend a route" flow) also corrects the name, and stores the stop counter.
      line_record.update!(display_name: display_name, mode: mode, last_stop_number: last_stop_number,
                          **color_attrs(payload))

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
    line_id = line_id.to_s
    station_count = 0
    edge_count    = 0

    # A delete that matches nothing is a failure, not a no-op success. Reporting 200 with
    # zeroed counts is what let a mis-parsed line id ("STACRUZ" instead of
    # "STACRUZ.LRT_BUENDIA") look like it worked: the client dropped the row optimistically,
    # then the untouched route reappeared on the next sync. Bumping the graph version for a
    # delete that changed nothing made that worse — every client resynced to fetch the same
    # graph back.
    if Station.where(line: line_id).none? && Edge.where(line: line_id).none?
      return Result.new(success?: false, errors: [
        { field: "line_id", message: "No route found with line ID '#{line_id}'." }
      ])
    end

    ActiveRecord::Base.transaction do
      # Includes the INTERCHANGE edges that join this line to another line. Edges on
      # other lines that point at a deleted station leave the graph inconsistent.
      station_ids   = Station.where(line: line_id).pluck(:station_id)
      edge_count    = Edge.where(line: line_id)
                          .or(Edge.where(from_station: station_ids))
                          .or(Edge.where(to_station: station_ids))
                          .delete_all
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
  # Supported only where the change is unambiguous:
  #
  # 1. Never on `mode == "train"`. MRT and LRT stations serve both directions, so a change
  #    to one direction's edge would leave the other direction out of step.
  # 2. A closed loop has an edge from its last stop to its first. That edge is an ordinary
  #    segment: insert_stop splits it and remove_stop merges across it.
  # 3. Only on stations whose id ends in `_STOP<n>` or `_S<n>`. Those ids form a chain.
  #
  # Both methods change `stations.sequence` and the line edges only. A station id and an
  # edge id never change, because tables such as saved_routes, incidents, and ar_world_maps
  # store station ids with no foreign key.

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
    prefix  = chain_prefix(ref.station_id)
    unless prefix
      return Result.new(success?: false, errors: [{ field: "referenceStationId",
                         message: "This station doesn't use the standard stop-numbering scheme; inserting isn't supported for it." }])
    end

    ordered = ordered_chain(line_id, prefix)
    n = ordered.length
    closed_loop = closed_loop?(line_id, ordered)

    # A retry of an insert whose response the client never received finds its own stop
    # here. Returning that stop keeps the request idempotent and adds no second copy.
    existing = ordered.find do |s|
      s.name == name && haversine(s.lat.to_f, s.lng.to_f, lat, lng) * 1000 <= DUPLICATE_STOP_RADIUS_M
    end
    return Result.new(success?: true, data: { line_id: line_id, station_id: existing.station_id }) if existing

    idx = ordered.index { |s| s.station_id == ref.station_id }
    p = position == "after" ? idx + 2 : idx + 1 # 1-based target position of the new stop
    # A loop has no head: the slot before the first stop is the slot after the last stop.
    p = n + 1 if closed_loop && p == 1

    prev_stop = p > 1 ? ordered[p - 2] : nil
    next_stop = p <= n ? ordered[p - 1] : (closed_loop ? ordered.first : nil)
    old_split_edge = prev_stop && next_stop ? find_chain_edge(line_id, prev_stop, next_stop) : nil

    # Road geometry for the edges this insert creates, supplied by the client in creation
    # order, each oriented from → to. A mid-chain split of recorded geometry ignores it.
    supplied_polys = normalize_supplied_polylines(
      payload[:newEdgePolylines] || payload["newEdgePolylines"]
    )

    short_name = (payload[:shortName] || payload["shortName"]).presence || derive_short_name(name)
    open_time  = (payload[:openTime]  || payload["openTime"]).presence  || ref.open_time
    close_time = (payload[:closeTime] || payload["closeTime"]).presence || ref.close_time
    new_sequence   = p <= n ? ordered[p - 1].sequence : ordered.last.sequence + 1
    new_station_id = nil

    ActiveRecord::Base.transaction do
      line_record = lock_line!(line_id, display_name: line_id, mode: ref.type)
      new_station_id = "#{prefix}_S#{line_record.last_stop_number + 1}"
      line_record.update!(last_stop_number: line_record.last_stop_number + 1)
      Station.where(station_id: ordered.drop(p - 1).map(&:station_id)).update_all("sequence = sequence + 1")

      Station.create!(
        station_id: new_station_id, name: name, short_name: short_name,
        line: line_id, sequence: new_sequence, type: ref.type, lat: lat, lng: lng,
        is_terminal: false, is_interchange: false, amenities: [],
        open_time: open_time, close_time: close_time
      )

      if old_split_edge
        prev_lat, prev_lng = coords_of(prev_stop.station_id)
        next_lat, next_lng = coords_of(next_stop.station_id)
        # A polyline with fewer than two points draws nothing, so it counts as empty here.
        poly = old_split_edge.polyline_coordinates || []
        poly = [] if poly.length < 2

        # With nothing to slice, both halves take the client's fetched road routes, or stay
        # empty when the client supplied none.
        if poly.empty? && supplied_polys.length == 2
          first_half  = pin_polyline_ends(supplied_polys[0], [prev_lat, prev_lng], [lat, lng])
          second_half = pin_polyline_ends(supplied_polys[1], [lat, lng], [next_lat, next_lng])
        else
          split_idx = split_point_index(poly, lat, lng)
          # Both halves need two points to draw. Clamping the split one vertex inside the
          # polyline gives that. A two-point polyline is a chord and stays whole.
          split_idx = split_idx.clamp(1, poly.length - 2) if poly.length >= 3
          first_half  = poly.empty? ? [] : poly[0..split_idx]
          second_half = poly.empty? ? [] : poly[split_idx..-1]
        end

        dist1 = poly_length_km(first_half)  || haversine(prev_lat, prev_lng, lat, lng)
        dist2 = poly_length_km(second_half) || haversine(lat, lng, next_lat, next_lng)

        # Sliced halves inherit the original's trustworthiness; fetched halves are road
        # routes by construction, so either way "snapped" tracks whether there is geometry.
        old_split_edge.delete
        halves_snapped = poly.empty? ? first_half.any? : old_split_edge.is_road_snapped
        Edge.create!(edge_attrs(old_split_edge, edge_id: line_edge_id(prev_stop.station_id, new_station_id),
                                from: prev_stop.station_id, to: new_station_id, distance_km: dist1, polyline: first_half,
                                is_road_snapped: halves_snapped))
        Edge.create!(edge_attrs(old_split_edge, edge_id: line_edge_id(new_station_id, next_stop.station_id),
                                from: new_station_id, to: next_stop.station_id, distance_km: dist2, polyline: second_half,
                                is_road_snapped: halves_snapped))
      elsif p == 1
        template = find_chain_edge(line_id, ordered[0], ordered[1])
        next_lat, next_lng = coords_of(next_stop.station_id)
        # The client's fetched road route is the only geometry for a head or tail insert.
        poly = pin_polyline_ends(supplied_polys.first, [lat, lng], [next_lat, next_lng])
        dist = poly_length_km(poly) || haversine(lat, lng, next_lat, next_lng)
        Edge.create!(edge_attrs(template, edge_id: line_edge_id(new_station_id, next_stop.station_id),
                                from: new_station_id, to: next_stop.station_id, distance_km: dist, polyline: poly,
                                is_road_snapped: poly.any?, mode: ref.type, line: line_id))
      else # p == n + 1 — append after the last stop
        template = find_chain_edge(line_id, ordered[n - 2], ordered[n - 1])
        prev_lat, prev_lng = coords_of(prev_stop.station_id)
        poly = pin_polyline_ends(supplied_polys.first, [prev_lat, prev_lng], [lat, lng])
        dist = poly_length_km(poly) || haversine(prev_lat, prev_lng, lat, lng)
        Edge.create!(edge_attrs(template, edge_id: line_edge_id(prev_stop.station_id, new_station_id),
                                from: prev_stop.station_id, to: new_station_id, distance_km: dist, polyline: poly,
                                is_road_snapped: poly.any?, mode: ref.type, line: line_id))
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
    prefix  = chain_prefix(station.station_id)
    unless prefix
      return Result.new(success?: false, errors: [{ field: "id",
                         message: "This station doesn't use the standard stop-numbering scheme; removing isn't supported for it." }])
    end

    ordered = ordered_chain(line_id, prefix)
    n = ordered.length
    if n <= 2
      return Result.new(success?: false, errors: [{ field: "base", message: "A route needs at least 2 stops — delete the whole route instead." }])
    end
    closed_loop = closed_loop?(line_id, ordered)

    idx = ordered.index { |s| s.station_id == station.station_id }
    # A loop wraps: the stop before the first is the last, and the stop after the last is the first.
    prev_stop = idx.zero? && !closed_loop ? nil : ordered[idx - 1]
    next_stop = idx == n - 1 && !closed_loop ? nil : ordered[(idx + 1) % n]

    ActiveRecord::Base.transaction do
      merged = if prev_stop && next_stop
        merged_edge_attrs(find_chain_edge(line_id, prev_stop, station), find_chain_edge(line_id, station, next_stop),
                          line_id: line_id, from_id: prev_stop.station_id, to_id: next_stop.station_id)
      end

      Edge.where(from_station: station.station_id).or(Edge.where(to_station: station.station_id)).delete_all
      Station.where(station_id: station.station_id).delete_all
      Station.where(station_id: ordered.drop(idx + 1).map(&:station_id)).update_all("sequence = sequence - 1")
      Edge.create!(merged) if merged

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
    lines    = Line.order(:id)
    peak     = PeakHourConfig.first
    fares    = FareMatrix.all
    # includes(:access_points): station_json reads them per station, and without the
    # preload that is one query per station on a payload that already assembles the whole
    # graph in a single request.
    stations = Station.includes(:access_points).order(:line, :station_id)
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
      lines: lines.to_h { |l| [l.id, line_json(l)] },
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
    errors << { field: "colorHex", message: "Color must look like #RRGGBB." } if invalid_color?(payload)
    passes = normalize_passes(payload)

    display_name = payload[:displayName] || payload["displayName"]
    errors << { field: "displayName", message: "Display name is required." } if display_name.blank?

    line_id = payload[:lineID] || payload["lineID"]
    line_exists = line_id.present? && Station.exists?(line: line_id)
    if line_id.blank?
      errors << { field: "lineID", message: "Line ID is required." }
    elsif line_id.include?(" ")
      errors << { field: "lineID", message: "Line ID must not contain spaces." }
    elsif line_exists && line_id !~ LEGACY_LINE_ID_RE
      errors << { field: "lineID", message: "Line ID must only contain uppercase letters, digits, underscores, and dots." }
    elsif !line_exists && line_id !~ NEW_LINE_ID_RE
      errors << { field: "lineID", message: "Line ID must start with an uppercase letter and use only uppercase letters, digits, and single underscores." }
    elsif line_exists
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

      # A bidirectional edge gets a synthetic reverse on the client, and that reverse
      # carries the *flipped* direction label. Combining the two therefore claims this
      # pass serves both directions of travel, which is never what a directional
      # recording means — reject it rather than silently generating edges that say so.
      if pass[:bidirectional] && direction
        errors << { field: "passes[#{p_idx}].bidirectional",
                    message: "A direction-tagged pass can't be bidirectional." }
      end

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
  # Reads a key that may arrive under either a Symbol or a String, distinguishing
  # "absent" from "present but false" — the `hash[:k] || hash["k"]` idiom used
  # elsewhere in this file collapses those two, which matters for a boolean flag
  # whose default is not simply `false`.
  def fetch_either(hash, key)
    return hash[key] if hash.key?(key)
    hash[key.to_s] if hash.respond_to?(:key?) && hash.key?(key.to_s)
  end

  def normalize_passes(payload)
    raw_passes = payload[:passes] || payload["passes"]
    raw_passes = [
      {
        direction: payload[:direction] || payload["direction"],
        bidirectional: fetch_either(payload, :bidirectional),
        stops: payload[:stops] || payload["stops"] || [],
        closesLoop: payload[:closesLoop] || payload["closesLoop"],
        closingPolyline: payload[:closingPolyline] || payload["closingPolyline"]
      }
    ] if raw_passes.blank?

    raw_passes.map do |pass|
      # nil means "caller didn't say" — add_route falls back to the legacy
      # `direction.nil?` rule for those. Cast explicitly so a JSON `false` (and the
      # string "false" a form-encoded client might send) doesn't read as "unset".
      raw_bidirectional = fetch_either(pass, :bidirectional)
      {
        direction: pass[:direction] || pass["direction"],
        bidirectional: raw_bidirectional.nil? ? nil : ActiveModel::Type::Boolean.new.cast(raw_bidirectional),
        stops: pass[:stops] || pass["stops"] || [],
        closes_loop: pass[:closesLoop] || pass["closesLoop"],
        closing_polyline: pass[:closingPolyline] || pass["closingPolyline"] || [],
        # True only when every segment recorded in this pass was actually
        # snapped to a road via MKDirections (set by the iOS Loop Creator;
        # absent/false for the legacy flat payload shape and any pass where a
        # snap attempt fell back to a straight line) — lets Explore trust this
        # polyline directly instead of silently re-computing and discarding it.
        is_road_snapped: ActiveModel::Type::Boolean.new.cast(pass[:isRoadSnapped] || pass["isRoadSnapped"]) || false
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

  def travel_time_minutes(dist_km, mode)
    [MIN_TRAVEL_TIME, dist_km / (speed_kmh(dist_km, mode) / 60.0)].max
  end

  def speed_kmh(dist_km, mode)
    return EXPRESS_SPEED_KMH if ROAD_MODES.include?(mode) && dist_km >= EXPRESS_GAP_KM

    SPEED_KMH_BY_MODE.fetch(mode, DEFAULT_SPEED_KMH)
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

  def payload_color(payload)
    (payload[:colorHex] || payload["colorHex"]).presence&.to_s&.strip&.upcase
  end

  def invalid_color?(payload)
    color = payload_color(payload)
    color.present? && color !~ Line::COLOR_HEX_FORMAT
  end

  # Empty when the payload omits colorHex, so extending a route keeps the stored color.
  def color_attrs(payload)
    payload.key?(:colorHex) || payload.key?("colorHex") ? { color_hex: payload_color(payload) } : {}
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
    errors
  end

  # Attributes of the edge that replaces `inbound` and `outbound` when the stop between them
  # leaves the chain. Either edge may be nil; the other one supplies the attributes.
  def merged_edge_attrs(inbound, outbound, line_id:, from_id:, to_id:)
    poly1 = inbound&.polyline_coordinates || []
    poly2 = outbound&.polyline_coordinates || []
    # Drop the first coordinate of the second half — it duplicates the shared
    # junction point at the station being removed (same invariant as stitching
    # polylines across merged legs elsewhere in the app).
    merged_poly = (poly1.empty? && poly2.empty?) ? [] : (poly1 + poly2.drop(1))
    merged_dist = inbound&.distance_km.to_f + outbound&.distance_km.to_f
    merged_time = inbound&.travel_time_minutes.to_f + outbound&.travel_time_minutes.to_f

    # Both halves must allow reverse travel for the merged edge to; a nil half (one
    # side missing) can't vouch for anything, so it doesn't grant two-way either.
    halves = [inbound, outbound].compact
    merged_bidirectional = halves.any? && halves.all?(&:bidirectional)
    # Directions should already agree — both halves come from one chain — so a
    # mismatch means the chain is malformed. Drop the label rather than assert one.
    directions = halves.map(&:direction).uniq
    merged_direction = directions.length == 1 ? directions.first : nil
    if directions.length > 1
      Rails.logger.warn(
        "[GraphService#remove_stop] #{line_id}: merging edges with different directions " \
        "(#{directions.inspect}) — dropping the direction label."
      )
    end

    merged_mode = inbound&.mode || outbound&.mode
    {
      edge_id: line_edge_id(from_id, to_id), from_station: from_id, to_station: to_id,
      mode: merged_mode, line: line_id,
      travel_time_minutes: merged_time.positive? ? merged_time : travel_time_minutes(merged_dist, merged_mode),
      distance_km: merged_dist,
      base_fare: inbound&.base_fare || outbound&.base_fare || 0,
      fare_per_km: inbound&.fare_per_km || outbound&.fare_per_km || 0,
      accepted_payments: inbound&.accepted_payments || outbound&.accepted_payments || [],
      is_air_conditioned: inbound&.is_air_conditioned || outbound&.is_air_conditioned || false,
      crowd_factor: inbound&.crowd_factor || outbound&.crowd_factor || 0.5,
      reliability: inbound&.reliability || outbound&.reliability || 0.9,
      # The merged edge inherits directionality. Where the halves disagree, the more
      # restrictive answer wins: merging must not invent the ability to ride in reverse.
      bidirectional: merged_bidirectional, direction: merged_direction,
      polyline_coordinates: merged_poly,
      # Only trustworthy if BOTH source edges were — one straight/unsnapped
      # half would make the whole merged shape suspect.
      is_road_snapped: (inbound&.is_road_snapped || false) && (outbound&.is_road_snapped || false),
      mk_directions_transport_type: inbound&.mk_directions_transport_type || outbound&.mk_directions_transport_type || mk_type_for(inbound&.mode)
    }
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

  # The chain of a generated stop id: the part before `_STOP<n>` or `_S<n>`. Returns nil for a
  # hand-authored id such as a named MRT-3 station.
  def chain_prefix(station_id)
    station_id[STOP_ID_RE, 1]
  end

  # Postgres pattern that matches every generated stop id of `prefix`.
  def chain_pattern(prefix)
    "^#{Regexp.escape(prefix)}_(STOP|S)[0-9]+$"
  end

  # The stations of one chain in travel order. A nil sequence sorts last, then the number in
  # the id breaks the tie.
  def ordered_chain(line_id, prefix)
    Station.where(line: line_id).where("station_id ~ ?", chain_pattern(prefix)).to_a
           .sort_by { |s| [s.sequence ? 0 : 1, s.sequence.to_i, s.station_id[STOP_ID_RE, 2].to_i] }
  end

  # The edge on the line that runs from `from` to `to`, or nil.
  def find_chain_edge(line_id, from, to)
    return unless from && to

    Edge.find_by(line: line_id, from_station: from.station_id, to_station: to.station_id)
  end

  # A chain is a closed loop when an edge runs from its last stop to its first.
  def closed_loop?(line_id, ordered)
    ordered.length > 1 && find_chain_edge(line_id, ordered.last, ordered.first).present?
  end

  # Locks the line row until the transaction ends, so two writers never take the same stop
  # number. A line with no row gets one.
  def lock_line!(line_id, display_name:, mode:)
    Line.lock.find_by(id: line_id) ||
      Line.create!(id: line_id, display_name: display_name, mode: mode, last_stop_number: 0)
  end

  def line_edge_id(from_id, to_id)
    "#{from_id}__#{to_id}"
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

  # Client-supplied road geometry for the newly created edges → an array of clean
  # [{lat:, lng:}] polylines, or [] when absent/unusable. A polyline of fewer than three
  # points is rejected: two points is a straight chord, which is exactly what this whole
  # change exists to stop storing. Rejection is all-or-nothing so a partially usable
  # payload can't leave one new edge with a road route and the other with a chord.
  def normalize_supplied_polylines(raw)
    return [] unless raw.is_a?(Array) && raw.first.is_a?(Array)

    polys = raw.map { |poly| normalize_supplied_polyline(poly) }
    polys.all? ? polys : []
  end

  def normalize_supplied_polyline(raw)
    return nil unless raw.is_a?(Array)

    points = raw.filter_map do |p|
      lat = p[:lat] || p["lat"]
      lng = p[:lng] || p["lng"]
      next if lat.nil? || lng.nil?
      lat_f = lat.to_f
      lng_f = lng.to_f
      next unless (-90.0..90.0).cover?(lat_f) && (-180.0..180.0).cover?(lng_f)
      { lat: lat_f, lng: lng_f }
    end
    points.length >= 3 ? points : nil
  end

  # Forces a polyline to start and end exactly on its edge's two stations. MKDirections
  # snaps its endpoints to the nearest road, which can sit tens of metres from the stop
  # the admin actually placed — and the map draws stop pins from the station coordinates,
  # so any drift shows up as a gap between the pin and the line. Same rule the iOS engine
  # applies when stitching leg polylines.
  def pin_polyline_ends(points, from_latlng, to_latlng)
    return [] if points.blank?

    pinned = points.dup
    pinned[0]  = { lat: from_latlng[0], lng: from_latlng[1] }
    pinned[-1] = { lat: to_latlng[0],   lng: to_latlng[1] }
    pinned
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
  def edge_attrs(template, edge_id:, from:, to:, distance_km:, polyline:, is_road_snapped:, mode: nil, line: nil)
    edge_mode = mode || template&.mode
    {
      edge_id: edge_id, from_station: from, to_station: to,
      mode: edge_mode, line: line || template&.line,
      travel_time_minutes: travel_time_minutes(distance_km, edge_mode),
      distance_km: distance_km,
      base_fare: template&.base_fare || 0,
      fare_per_km: template&.fare_per_km || 0,
      accepted_payments: template&.accepted_payments || [],
      is_air_conditioned: template&.is_air_conditioned || false,
      crowd_factor: template&.crowd_factor || 0.5,
      reliability: template&.reliability || 0.9,
      # Directionality is inherited like everything else here. Hardcoding
      # `bidirectional: true, direction: nil` meant inserting a stop silently turned the
      # two halves of the split segment two-way — and, on a directional chain, dropped
      # the direction label — while every other attribute was faithfully copied. The
      # client synthesises a reverse edge for anything bidirectional, so a two-way
      # segment in the middle of a one-way route lets the router run that stretch
      # backwards and send a rider to a stop that only serves the other direction.
      #
      # `template` is the edge being split (or, for a head/tail insert, its neighbour on
      # the same chain) — in both cases the correct value was already in hand.
      bidirectional: template&.bidirectional.nil? ? true : template.bidirectional,
      direction: template&.direction,
      polyline_coordinates: polyline,
      is_road_snapped: is_road_snapped,
      mk_directions_transport_type: template&.mk_directions_transport_type || mk_type_for(mode || template&.mode)
    }
  end

  # Sets is_terminal on the first and last stop of the chain, in `sequence` order.
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

  def line_json(l)
    h = { id: l.id, displayName: l.display_name, mode: l.mode, lastStopNumber: l.last_stop_number }
    h[:colorHex] = l.color_hex if l.color_hex.present?
    h
  end

  # camelCase twin of Station#as_api_json — change the two together. A field present in
  # only one of them goes missing on whichever path does not carry it, which is what
  # already happened to `interchangesWith`: it is in the bundled transit_graph_v3.json
  # and in the iOS Station model, but neither serialiser emits it, so an OTA sync nils it
  # for every station.
  #
  # `accessPoints` is omitted rather than sent empty when a station has no doors
  # surveyed, so the payload does not grow by 60 empty arrays for a feature that starts
  # out unpopulated. The iOS side decodes it as optional and falls back to `coordinates`.
  def station_json(s)
    json = { id: s.station_id, name: s.name, shortName: s.short_name,
             line: s.line, type: s.type,
             coordinates: { lat: s.lat.to_f, lng: s.lng.to_f },
             isTerminal: s.is_terminal, isInterchange: s.is_interchange,
             amenities: s.amenities,
             operatingHours: { open: s.open_time, close: s.close_time } }

    json[:sequence] = s.sequence if s.sequence
    points = s.access_points
    json[:accessPoints] = points.map(&:as_graph_json) if points.any?
    json
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
          mkDirectionsTransportType: e.mk_directions_transport_type,
          isRoadSnapped: e.is_road_snapped }
    h[:direction] = e.direction if e.direction.present?
    h
  end
end
