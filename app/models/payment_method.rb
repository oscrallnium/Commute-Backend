class PaymentMethod < ApplicationRecord
  self.primary_key = "id"
  self.table_name  = "payment_methods"

  # Returns each ID in the list that has no payment method row.
  def self.unknown_ids(ids) = ids - where(id: ids).pluck(:id)
end
