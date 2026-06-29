class SavedRoute < ApplicationRecord
  belongs_to :user
  belongs_to :origin_station,      class_name: "Station",
             foreign_key: :origin_station_id,      primary_key: :station_id, optional: true
  belongs_to :destination_station, class_name: "Station",
             foreign_key: :destination_station_id, primary_key: :station_id, optional: true

  validates :user, presence: true

  def as_api_json
    {
      id:                     id,
      name:                   name,
      origin_station_id:      origin_station_id,
      destination_station_id: destination_station_id,
      legs:                   legs,
      created_at:             created_at
    }
  end
end
