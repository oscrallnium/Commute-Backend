class ArWorldMap < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :station, primary_key: :station_id, optional: true
  has_one_attached :map_file

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  validates :station_id, presence: true
  validates :version,    presence: true, numericality: { greater_than: 0 }

  scope :approved, -> { where(status: :approved) }

  def as_api_json(include_url: false)
    payload = {
      id: id,
      station_id: station_id,
      version: version,
      status: status,
      uploaded_by: user&.display_name,
      file_size_mb: map_file.attached? ? (map_file.byte_size / 1.megabyte.to_f).round(2) : nil,
      created_at: created_at
    }
    if include_url && map_file.attached?
      payload[:download_url] = Rails.application.routes.url_helpers.rails_blob_url(map_file, only_path: false)
    end
    payload
  end
end
