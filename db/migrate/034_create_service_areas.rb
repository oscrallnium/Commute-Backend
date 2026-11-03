class CreateServiceAreas < ActiveRecord::Migration[7.1]
  def change
    create_table :service_areas, id: false do |t|
      t.string  :line_id, null: false, primary_key: true
      t.jsonb   :boundary, null: false, default: []
      t.decimal :base_fare, precision: 8, scale: 2, null: false, default: 0
      t.decimal :base_km, precision: 6, scale: 2, null: false, default: 0
      t.decimal :fare_per_km, precision: 8, scale: 2, null: false, default: 0
      t.decimal :special_trip_fare, precision: 8, scale: 2
      t.decimal :speed_kmh, precision: 5, scale: 2, null: false, default: 15
      t.decimal :detour_factor, precision: 4, scale: 2, null: false, default: 1.3
      t.decimal :wait_minutes, precision: 5, scale: 2, null: false, default: 3
      t.string  :accepted_payments, array: true, null: false, default: []
      t.timestamps

      t.check_constraint "base_fare >= 0", name: "service_areas_base_fare_check"
      t.check_constraint "base_km >= 0", name: "service_areas_base_km_check"
      t.check_constraint "fare_per_km >= 0", name: "service_areas_fare_per_km_check"
      t.check_constraint "special_trip_fare IS NULL OR special_trip_fare >= 0",
                         name: "service_areas_special_trip_fare_check"
      t.check_constraint "speed_kmh > 0", name: "service_areas_speed_kmh_check"
      t.check_constraint "detour_factor >= 1", name: "service_areas_detour_factor_check"
      t.check_constraint "wait_minutes >= 0", name: "service_areas_wait_minutes_check"
    end

    add_foreign_key :service_areas, :lines, column: :line_id, primary_key: :id, on_delete: :cascade
  end
end
