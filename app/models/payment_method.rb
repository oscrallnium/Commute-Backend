class PaymentMethod < ApplicationRecord
  self.primary_key = "id"
  self.table_name  = "payment_methods"
end
