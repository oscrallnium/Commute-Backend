# Decides which lines, stations, and edges riders see in GET /api/v1/graph.
# A station is hidden when it or its line is disabled. An edge is hidden when it or its line is
# disabled, or when either end is not a visible station. See docs/ops-publish-api.md.
class GraphVisibility
  def initialize(lines:, stations:)
    @disabled_line_ids   = lines.reject(&:enabled).to_set(&:id)
    @visible_station_ids = stations.select { |s| station_visible?(s) }.to_set(&:station_id)
  end

  def line_visible?(line)
    line.enabled
  end

  # A fare row or mode entry can name a line that has no `lines` row. Such a line counts as visible.
  def line_id_visible?(line_id)
    @disabled_line_ids.exclude?(line_id)
  end

  def station_visible?(station)
    station.enabled && @disabled_line_ids.exclude?(station.line)
  end

  def edge_visible?(edge)
    edge.enabled && @disabled_line_ids.exclude?(edge.line) &&
      @visible_station_ids.include?(edge.from_station) && @visible_station_ids.include?(edge.to_station)
  end

  def station_id_visible?(station_id)
    @visible_station_ids.include?(station_id)
  end
end
