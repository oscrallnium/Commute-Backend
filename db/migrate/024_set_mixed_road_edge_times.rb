class SetMixedRoadEdgeTimes < ActiveRecord::Migration[7.1]
  # These edges run partly or fully off expressways, so the 45 km/h gap rule is too fast.
  # Each value comes from the real road mix of the edge.
  FIXED_TIMES = {
    "STACRUZ.LRT_BUENDI_NB_SEG1" => 52.9,
    "UPLB_KANAN_SEG2" => 25.7,
    "STACRUZ.LRT_BUENDI_NB_SEG3" => 78.3,
    "AYALA_ALABANG_SB_S10__AYALA_ALABANG_SB_S11" => 14.2
  }.freeze
  # The rule value of a road edge of 5 km or more. It is fixed here so a later change to
  # GraphService does not change this migration.
  RULE_TIME_SQL = "GREATEST(2.0, distance_km / (45.0 / 60.0))".freeze
  # An edge matches a time when its stored time is within this many minutes of that time.
  TOLERANCE_MINUTES = 0.01

  # Sets a fixed time only on an edge that holds the rule value. A hand-set time stays unchanged.
  def up
    transaction do
      FIXED_TIMES.each do |edge_id, fixed_time|
        retime_edge!(edge_id, from: RULE_TIME_SQL, to: fixed_time.to_s)
      end
      bump_graph_version!
    end
    clear_graph_cache!
  end

  # Restores the rule value only on an edge that holds its fixed time.
  def down
    transaction do
      FIXED_TIMES.each do |edge_id, fixed_time|
        retime_edge!(edge_id, from: fixed_time.to_s, to: RULE_TIME_SQL)
      end
      bump_graph_version!
    end
    clear_graph_cache!
  end

  private

  def retime_edge!(edge_id, from:, to:)
    quoted_id = connection.quote(edge_id)
    matched = update_matching_edge(quoted_id, from: from, to: to)
    return if matched == 1
    return say("Edge not found, skipped: #{edge_id}") unless edge_exists?(quoted_id)

    say("Edge time differs, left unchanged: #{edge_id}")
  end

  def update_matching_edge(quoted_id, from:, to:)
    connection.update(<<~SQL.squish)
      UPDATE edges
      SET travel_time_minutes = #{to}, updated_at = NOW()
      WHERE edge_id = #{quoted_id}
        AND ABS(travel_time_minutes - #{from}) <= #{TOLERANCE_MINUTES}
    SQL
  end

  def edge_exists?(quoted_id)
    connection.select_value("SELECT 1 FROM edges WHERE edge_id = #{quoted_id}").present?
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
