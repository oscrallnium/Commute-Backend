class Station < ApplicationRecord
  self.primary_key        = "station_id" # TEXT PK — matches the graph e.g. "MRT_NORTH_AVE"
  self.inheritance_column = nil

  has_many :ar_world_maps, primary_key: :station_id, dependent: :destroy
  has_many :incidents, primary_key: :station_id, dependent: :destroy
  # dependent: :destroy mirrors the FK's ON DELETE CASCADE so the rows go whether the
  # station is removed through the model or straight from SQL.
  has_many :access_points, -> { ordered },
           class_name: "StationAccessPoint", primary_key: :station_id,
           foreign_key: :station_id, dependent: :destroy

  validates :station_id, :name, :line, :type, presence: true

  scope :search, lambda { |q|
    where("name ILIKE :q OR short_name ILIKE :q OR line ILIKE :q", q: "%#{q}%")
  }

  def as_api_json
    {
      id: station_id,
      name: name,
      short_name: short_name,
      line: line,
      type: type,
      coordinates: { lat: lat.to_f, lng: lng.to_f },
      is_terminal: is_terminal,
      is_interchange: is_interchange,
      amenities: amenities,
      operating_hours: { open: open_time, close: close_time },
      # snake_case here, camelCase in GraphService#station_json. Both must carry this
      # field: `interchangesWith` is already in the bundled transit_graph_v3.json and in
      # the iOS Station model but is emitted by neither serialiser, so every OTA sync
      # silently nils it out (AdminRoutesView.swift:76 patches around it). Do not let
      # access points repeat that.
      access_points: access_points.map(&:as_api_json)
    }
  end
end
