class AddFareKmRoundingToLines < ActiveRecord::Migration[7.1]
  def change
    add_column :lines, :fare_km_rounding, :string
    add_check_constraint :lines, "fare_km_rounding IS NULL OR fare_km_rounding IN ('up', 'down')",
                         name: "lines_fare_km_rounding_check"
  end
end
