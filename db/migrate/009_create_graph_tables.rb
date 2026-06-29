class CreateGraphTables < ActiveRecord::Migration[7.1]
  def change
    # ── graph_meta — single-row version tracker ──────────────────────────────
    create_table :graph_meta, force: :cascade do |t|
      t.integer  :version,        null: false, default: 1
      t.datetime :last_modified,  null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.string   :schema_version, null: false, default: "3.0.0"
      t.string   :region,         null: false, default: "Metro Manila, Philippines"
      t.string   :currency,       null: false, default: "PHP"
    end

    # ── transport_modes ───────────────────────────────────────────────────────
    create_table :transport_modes, id: false do |t|
      t.string   :id,                        null: false  # PK: 'train', 'jeepney', etc.
      t.string   :display_name,              null: false
      t.string   :plural_name,               null: false, default: ""
      t.string   :sf_symbol,                 null: false, default: ""
      t.string   :color_hex,                 null: false, default: "#000000"
      t.decimal  :map_line_width_pt,         null: false, default: 4.0
      t.jsonb    :map_line_dash,             null: false, default: []
      t.string   :mk_directions_type,        null: false, default: "transit"
      t.boolean  :is_user_selectable,        null: false, default: true
      t.boolean  :is_always_allowed,         null: false, default: false
      t.string   :lines,                     array: true, default: []
      t.string   :default_accepted_payments, array: true, default: []
      t.text     :notes,                     null: false, default: ""
      t.integer  :position,                  null: false, default: 0
      t.jsonb    :extra,                     null: false, default: {}
    end
    add_index :transport_modes, :id, unique: true

    # ── payment_methods ───────────────────────────────────────────────────────
    create_table :payment_methods, id: false do |t|
      t.string  :id,               null: false  # PK: 'cash', 'beep_card', etc.
      t.string  :display_name,     null: false
      t.string  :sf_symbol,        null: false, default: ""
      t.string  :color_hex,        null: false, default: "#000000"
      t.boolean :is_default,       null: false, default: false
      t.string  :accepted_by_modes, array: true, default: []
      t.text    :notes,            null: false, default: ""
    end
    add_index :payment_methods, :id, unique: true

    # ── peak_hour_config — single-row JSONB blob ──────────────────────────────
    create_table :peak_hour_config, force: :cascade do |t|
      t.jsonb :data, null: false, default: {}
    end

    # ── fare_matrix — one row per line ────────────────────────────────────────
    create_table :fare_matrix, id: false do |t|
      t.string :line_name, null: false  # PK: 'MRT-3', 'LRT-1', etc.
      t.string :type,      null: false, default: "flat"
      t.jsonb  :data,      null: false, default: {}
    end
    add_index :fare_matrix, :line_name, unique: true

    # ── stations ──────────────────────────────────────────────────────────────
    create_table :stations, id: false do |t|
      t.string   :station_id,     null: false  # PK: 'MRT_NORTH_AVE'
      t.string   :name,           null: false
      t.string   :short_name,     null: false, default: ""
      t.string   :line,           null: false
      t.string   :type,           null: false
      t.decimal  :lat,            null: false, precision: 10, scale: 7
      t.decimal  :lng,            null: false, precision: 10, scale: 7
      t.boolean  :is_terminal,    null: false, default: false
      t.boolean  :is_interchange, null: false, default: false
      t.string   :amenities,      array: true, default: []
      t.string   :open_time,      null: false, default: "05:00"
      t.string   :close_time,     null: false, default: "23:00"
      t.timestamps
    end
    add_index :stations, :station_id, unique: true
    add_index :stations, :line
    add_index :stations, :type
    execute "CREATE INDEX idx_stations_name_trgm ON stations USING gin (name gin_trgm_ops)"

    # ── edges ─────────────────────────────────────────────────────────────────
    create_table :edges, id: false do |t|
      t.string   :edge_id,                      null: false  # PK
      t.string   :from_station,                 null: false
      t.string   :to_station,                   null: false
      t.string   :mode,                         null: false
      t.string   :line,                         null: false
      t.decimal  :travel_time_minutes,          null: false
      t.decimal  :distance_km,                  null: false
      t.decimal  :base_fare,                    null: false, default: 0
      t.decimal  :fare_per_km,                  null: false, default: 0
      t.string   :accepted_payments,            array: true, default: []
      t.boolean  :is_air_conditioned,           null: false, default: false
      t.decimal  :crowd_factor,                 null: false, default: 0.5
      t.decimal  :reliability,                  null: false, default: 0.9
      t.boolean  :bidirectional,                null: false, default: true
      t.string   :direction
      t.jsonb    :polyline_coordinates,         null: false, default: []
      t.string   :mk_directions_transport_type, null: false, default: "transit"
      t.timestamps
    end
    add_index :edges, :edge_id, unique: true
    add_index :edges, :line
    add_index :edges, :mode
    add_index :edges, :from_station
    add_index :edges, :to_station
  end
end
