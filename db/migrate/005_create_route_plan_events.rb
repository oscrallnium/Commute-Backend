class CreateRoutePlanEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :route_plan_events, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :user, null: true, foreign_key: true, type: :uuid
      t.string   :origin_station_id
      t.string   :destination_station_id
      t.jsonb    :legs,               null: false, default: []
      t.integer  :total_time_minutes
      t.string   :modes_used,         array: true, default: []
      t.datetime :occurred_at,        null: false
    end

    add_index :route_plan_events, :occurred_at
    add_index :route_plan_events, :origin_station_id
    add_index :route_plan_events, :destination_station_id
  end
end
