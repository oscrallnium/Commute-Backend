class SavedRoute < ApplicationRecord
  belongs_to :user
  belongs_to :origin_station,      class_name: "Station", primary_key: :station_id, optional: true
  belongs_to :destination_station, class_name: "Station", primary_key: :station_id, optional: true

  def as_api_json
    {
      id: id,
      name: name,
      origin_station_id: origin_station_id,
      destination_station_id: destination_station_id,
      legs: legs,
      created_at: created_at
    }
  end
end
