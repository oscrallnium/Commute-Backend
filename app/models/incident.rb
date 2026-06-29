class Incident < ApplicationRecord
  belongs_to :station, foreign_key: :station_id, primary_key: :station_id, optional: true

  enum category: { delay: 0, crowding: 1, breakdown: 2, closure: 3, other: 4 }, _default: :other

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  validates :category, presence: true

  def as_api_json
    {
      id:          id,
      station_id:  station_id,
      line_id:     line_id,
      category:    category,
      description: description,
      reported_by: reported_by,
      created_at:  created_at
    }
  end
end
