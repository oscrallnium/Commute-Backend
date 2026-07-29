class BackfillIsRoadSnappedForDenseEdges < ActiveRecord::Migration[7.1]
  # `is_road_snapped` was added by migration 013 defaulting to false, and nothing
  # backfilled it. Every edge recorded before that — including routes traced through the
  # iOS Loop Creator, whose polylines came straight from MKDirections — therefore claims
  # its geometry can't be trusted.
  #
  # Explore reads that flag to decide what to re-snap, and re-snapping costs one
  # MKDirections request *per consecutive pair of points*. On the live graph that meant
  # 956 requests on a cold launch, 908 of them re-deriving two routes that were already
  # road-traced at ~90 m point spacing. The flag was lying, and the client paid for it.
  #
  # Point spacing is self-describing: a polyline whose points sit closer together than a
  # city block is a recorded trace, not a stop-to-stop chord. Same 150 m threshold the
  # iOS client uses in `ExploreViewModel.needsRoadSnapping` — keep the two in step.
  DENSE_SPACING_METRES = 150.0
  EARTH_RADIUS_METRES  = 6_371_000.0

  # Local model so this migration keeps working if app/models/edge.rb changes later.
  class MigrationEdge < ActiveRecord::Base
    self.table_name  = "edges"
    self.primary_key = "edge_id"
  end

  def up
    updated = 0

    MigrationEdge.where(is_road_snapped: false).find_each do |edge|
      points = normalise(edge.polyline_coordinates)
      next if points.length < 2

      total = points.each_cons(2).sum { |a, b| haversine_metres(a, b) }
      next unless (total / (points.length - 1)) < DENSE_SPACING_METRES

      edge.update_columns(is_road_snapped: true)
      updated += 1
    end

    say "marked #{updated} dense edge(s) as road-snapped"
  end

  # Deliberately irreversible: the pre-migration value was a default nobody set, so
  # restoring it would mean re-introducing the wrong answer.
  def down
    say "no-op — the previous `false` was an unset default, not a recorded fact"
  end

  private

  def normalise(raw)
    (raw || []).filter_map do |p|
      lat = p["lat"] || p[:lat]
      lng = p["lng"] || p[:lng]
      next if lat.nil? || lng.nil?
      [lat.to_f, lng.to_f]
    end
  end

  def haversine_metres(a, b)
    lat1 = a[0] * Math::PI / 180
    lat2 = b[0] * Math::PI / 180
    d_lat = lat2 - lat1
    d_lng = (b[1] - a[1]) * Math::PI / 180
    h = Math.sin(d_lat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(d_lng / 2)**2
    2 * EARTH_RADIUS_METRES * Math.asin(Math.sqrt(h))
  end
end
