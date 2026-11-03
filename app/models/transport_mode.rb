class TransportMode < ApplicationRecord
  self.primary_key = "id"
  self.table_name  = "transport_modes"

  enum :service_shape, { path: "path", area: "area" }, suffix: true, validate: true
end
