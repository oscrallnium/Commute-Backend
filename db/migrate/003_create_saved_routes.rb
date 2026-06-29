class CreateSavedRoutes < ActiveRecord::Migration[7.1]
  def change
    create_table :saved_routes, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string  :name
      t.string  :origin_station_id
      t.string  :destination_station_id
      t.jsonb   :legs,               null: false, default: []
      t.integer :total_time_minutes
      t.timestamps
    end

    add_index :saved_routes, :origin_station_id
    add_index :saved_routes, :destination_station_id
  end
end
