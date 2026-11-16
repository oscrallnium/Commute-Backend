class CreateServiceScheduleExceptions < ActiveRecord::Migration[7.1]
  # One row replaces the regular service of a line, or one direction of it, for a date range.
  def change
    create_table :service_schedule_exceptions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :line_id, null: false
      t.string :direction
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :kind, null: false
      t.string :start_time
      t.string :end_time
      t.string :departure_times, array: true, null: false, default: []
      t.string :note
      t.timestamps
    end

    add_index :service_schedule_exceptions, %i[line_id start_date]
    add_check_constraint :service_schedule_exceptions, "end_date >= start_date",
                         name: "service_schedule_exceptions_dates_check"
    add_foreign_key :service_schedule_exceptions, :lines, column: :line_id, primary_key: :id,
                                                          on_delete: :cascade
  end
end
