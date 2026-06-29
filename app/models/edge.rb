class Edge < ApplicationRecord
  self.primary_key        = "edge_id"
  self.inheritance_column = nil

  validates :edge_id, :from_station, :to_station, :line, :mode, presence: true

  def as_api_json
    {
      id:                        edge_id,
      from:                      from_station,
      to:                        to_station,
      mode:                      mode,
      line:                      line,
      travel_time_minutes:       travel_time_minutes.to_f,
      distance_km:               distance_km.to_f,
      base_fare:                 base_fare.to_f,
      fare_per_km:               fare_per_km.to_f,
      accepted_payments:         accepted_payments,
      is_air_conditioned:        is_air_conditioned,
      crowd_factor:              crowd_factor.to_f,
      reliability:               reliability.to_f,
      bidirectional:             bidirectional,
      direction:                 direction,
      polyline_coordinates:      polyline_coordinates,
      mk_directions_transport_type: mk_directions_transport_type
    }
  end
end
