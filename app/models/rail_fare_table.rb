class RailFareTable < ApplicationRecord
  self.primary_key = "line_id"

  # camelCase, for the graph payload. `fares[i][j]` is the fare from `stationIds[i]` to `stationIds[j]`.
  def as_graph_json
    { stationIds: station_ids, fares: fares }
  end
end
