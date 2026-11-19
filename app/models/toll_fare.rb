class TollFare < ApplicationRecord
  belongs_to :entry_plaza, class_name: "TollPlaza", inverse_of: :entry_fares
  belongs_to :exit_plaza, class_name: "TollPlaza", inverse_of: :exit_fares

  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :exit_plaza_id, uniqueness: { scope: :entry_plaza_id }
  validate :plazas_differ

  private

  def plazas_differ
    errors.add(:exit_plaza_id, "must differ from the entry plaza") if entry_plaza_id == exit_plaza_id
  end
end
