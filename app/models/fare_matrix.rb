class FareMatrix < ApplicationRecord
  self.primary_key        = "line_name"
  self.table_name         = "fare_matrix"
  self.inheritance_column = nil
end
