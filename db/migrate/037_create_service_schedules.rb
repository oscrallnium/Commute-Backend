class CreateServiceSchedules < ActiveRecord::Migration[7.1]
  # One row gives a line, or one direction of it, service days and either a window or trip times.
  def change
    create_table :service_schedules, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :line_id, null: false
      t.string :direction
      t.string :days, array: true, null: false, default: []
      t.string :kind, null: false
      t.string :start_time
      t.string :end_time
      t.string :departure_times, array: true, null: false, default: []
      t.string :note
      t.timestamps
    end

    add_index :service_schedules, %i[line_id direction]
    add_foreign_key :service_schedules, :lines, column: :line_id, primary_key: :id, on_delete: :cascade
  end
end
