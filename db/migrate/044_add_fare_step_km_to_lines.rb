class AddFareStepKmToLines < ActiveRecord::Migration[7.1]
  def up
    add_column :lines, :fare_step_km, :decimal, precision: 6, scale: 2
    add_check_constraint :lines, "fare_step_km IS NULL OR fare_step_km >= 0", name: "lines_fare_step_km_check"
  end

  def down
    remove_check_constraint :lines, name: "lines_fare_step_km_check"
    remove_column :lines, :fare_step_km
  end
end
