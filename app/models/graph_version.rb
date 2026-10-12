class GraphVersion < ApplicationRecord
  belongs_to :published_by, class_name: "User", optional: true

  validates :version, presence: true, uniqueness: true
  validates :published_at, :change_count, presence: true

  def as_api_json(include_changes: false)
    json = {
      version: version,
      published_at: published_at.iso8601,
      published_by: published_by && { id: published_by.id, display_name: published_by.display_name },
      change_count: change_count
    }
    json[:changes] = change_list if include_changes
    json
  end
end
