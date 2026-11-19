class TollPlaza < ApplicationRecord
  self.primary_key = "id"

  has_many :entry_fares, class_name: "TollFare", foreign_key: :entry_plaza_id, inverse_of: :entry_plaza,
                         dependent: :restrict_with_error
  has_many :exit_fares, class_name: "TollFare", foreign_key: :exit_plaza_id, inverse_of: :exit_plaza,
                        dependent: :restrict_with_error

  validates :id, format: { with: GraphService::NEW_LINE_ID_RE, message: "must use uppercase letters, digits, and single underscores" }
  validates :name, presence: true

  def as_graph_json = { id: id, name: name }
end
