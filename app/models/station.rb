class Station < ApplicationRecord
  self.primary_key        = "station_id" # TEXT PK — matches the graph e.g. "MRT_NORTH_AVE"
  self.inheritance_column = nil

  has_many :ar_world_maps, primary_key: :station_id, dependent: :destroy
  has_many :incidents, primary_key: :station_id, dependent: :destroy

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
      operating_hours: { open: open_time, close: close_time }
    }
  end
end
