class CreateRailFareTables < ActiveRecord::Migration[7.1]
  # One row per rail line. `fares[i][j]` is the fare from `station_ids[i]` to `station_ids[j]`.
  def change
    create_table :rail_fare_tables, id: false do |t|
      t.string :line_id, null: false, primary_key: true
      t.jsonb :station_ids, null: false, default: []
      t.jsonb :fares, null: false, default: []
      t.timestamps
    end
  end
end
