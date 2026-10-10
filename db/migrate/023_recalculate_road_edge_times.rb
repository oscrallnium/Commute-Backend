class RecalculateRoadEdgeTimes < ActiveRecord::Migration[7.1]
  # The rule is fixed here so a later change to GraphService does not change this migration.
  # Old rule: 24 km/h for every road mode, minimum 2 minutes.
  OLD_TIME_SQL = "GREATEST(2.0, distance_km / 0.4)".freeze
  # New rule: 45 km/h from 5 km, else 22 km/h bus, 16 km/h jeepney, 15 km/h tricycle.
  NEW_TIME_SQL = <<~SQL.squish.freeze
    GREATEST(2.0, distance_km / ((CASE
      WHEN distance_km >= 5 THEN 45.0
      WHEN mode = 'bus' THEN 22.0
      WHEN mode = 'jeepney' THEN 16.0
      ELSE 15.0 END) / 60.0))
  SQL
  # An edge matches a rule when its stored time is within this many minutes of the rule value.
  TOLERANCE_MINUTES = 0.01
  ROAD_EDGES_SQL = "mode IN ('bus', 'jeepney', 'tricycle') AND line <> 'INTERCHANGE'".freeze

  # Changes only edges that hold the old rule value. A hand-set time stays unchanged.
  def up
    transaction do
      retime_edges!(from: OLD_TIME_SQL, to: NEW_TIME_SQL)
      bump_graph_version!
    end
    clear_graph_cache!
  end

  # Restores the old value on every road edge that holds the new rule value. A hand-set time
  # that equals the new rule value also reverts, so `down` is not exact for that edge.
  def down
    transaction do
      retime_edges!(from: NEW_TIME_SQL, to: OLD_TIME_SQL)
      bump_graph_version!
    end
    clear_graph_cache!
  end

  private

  def retime_edges!(from:, to:)
    execute <<~SQL.squish
      UPDATE edges
      SET travel_time_minutes = #{to}, updated_at = NOW()
      WHERE #{ROAD_EDGES_SQL}
        AND ABS(travel_time_minutes - #{from}) <= #{TOLERANCE_MINUTES}
        AND ABS(#{to} - #{from}) > #{TOLERANCE_MINUTES}
    SQL
  end

  def bump_graph_version!
    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # Runs after the commit, so no request can cache the old times again. A cache error does
  # not fail the migration, because each entry also expires on its own.
  def clear_graph_cache!
    %w[full_graph graph_version routes_index].each { |key| Rails.cache.delete(key) }
    Rails.cache.delete_matched("stations*")
  rescue StandardError => e
    say "Graph cache not cleared: #{e.class}: #{e.message}"
  end
end
