class CreateArWorldMaps < ActiveRecord::Migration[7.1]
  def change
    create_table :ar_world_maps, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :user, null: true, foreign_key: true, type: :uuid
      t.string  :station_id, null: false   # TEXT FK to stations
      t.integer :version,    null: false, default: 1
      t.integer :status,     null: false, default: 0  # pending/approved/rejected
      t.jsonb   :metadata,   null: false, default: {}
      t.timestamps
    end

    add_index :ar_world_maps, :station_id
    add_index :ar_world_maps, [:station_id, :version]
    add_index :ar_world_maps, :status
    add_index :ar_world_maps, :metadata, using: :gin
  end
end
