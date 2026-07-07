# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 11) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "unaccent"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ar_world_maps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "station_id", null: false
    t.integer "version", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metadata"], name: "index_ar_world_maps_on_metadata", using: :gin
    t.index ["station_id", "version"], name: "index_ar_world_maps_on_station_id_and_version"
    t.index ["station_id"], name: "index_ar_world_maps_on_station_id"
    t.index ["status"], name: "index_ar_world_maps_on_status"
    t.index ["user_id"], name: "index_ar_world_maps_on_user_id"
  end

  create_table "edges", id: false, force: :cascade do |t|
    t.string "edge_id", null: false
    t.string "from_station", null: false
    t.string "to_station", null: false
    t.string "mode", null: false
    t.string "line", null: false
    t.decimal "travel_time_minutes", null: false
    t.decimal "distance_km", null: false
    t.decimal "base_fare", default: "0.0", null: false
    t.decimal "fare_per_km", default: "0.0", null: false
    t.string "accepted_payments", default: [], array: true
    t.boolean "is_air_conditioned", default: false, null: false
    t.decimal "crowd_factor", default: "0.5", null: false
    t.decimal "reliability", default: "0.9", null: false
    t.boolean "bidirectional", default: true, null: false
    t.string "direction"
    t.jsonb "polyline_coordinates", default: [], null: false
    t.string "mk_directions_transport_type", default: "transit", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["edge_id"], name: "index_edges_on_edge_id", unique: true
    t.index ["from_station"], name: "index_edges_on_from_station"
    t.index ["line"], name: "index_edges_on_line"
    t.index ["mode"], name: "index_edges_on_mode"
    t.index ["to_station"], name: "index_edges_on_to_station"
  end

  create_table "fare_matrix", id: false, force: :cascade do |t|
    t.string "line_name", null: false
    t.string "type", default: "flat", null: false
    t.jsonb "data", default: {}, null: false
    t.index ["line_name"], name: "index_fare_matrix_on_line_name", unique: true
  end

  create_table "graph_meta", force: :cascade do |t|
    t.integer "version", default: 1, null: false
    t.datetime "last_modified", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "schema_version", default: "3.0.0", null: false
    t.string "region", default: "Metro Manila, Philippines", null: false
    t.string "currency", default: "PHP", null: false
    t.boolean "enforce_operating_hours", default: true, null: false
  end

  create_table "incidents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "station_id"
    t.string "line_id"
    t.integer "category", default: 4, null: false
    t.text "description"
    t.uuid "reported_by"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_incidents_on_expires_at"
    t.index ["line_id"], name: "index_incidents_on_line_id"
    t.index ["station_id"], name: "index_incidents_on_station_id"
  end

  create_table "payment_methods", id: false, force: :cascade do |t|
    t.string "id", null: false
    t.string "display_name", null: false
    t.string "sf_symbol", default: "", null: false
    t.string "color_hex", default: "#000000", null: false
    t.boolean "is_default", default: false, null: false
    t.string "accepted_by_modes", default: [], array: true
    t.text "notes", default: "", null: false
    t.index ["id"], name: "index_payment_methods_on_id", unique: true
  end

  create_table "peak_hour_config", force: :cascade do |t|
    t.jsonb "data", default: {}, null: false
  end

  create_table "route_plan_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "origin_station_id"
    t.string "destination_station_id"
    t.jsonb "legs", default: [], null: false
    t.integer "total_time_minutes"
    t.string "modes_used", default: [], array: true
    t.datetime "occurred_at", null: false
    t.index ["destination_station_id"], name: "index_route_plan_events_on_destination_station_id"
    t.index ["occurred_at"], name: "index_route_plan_events_on_occurred_at"
    t.index ["origin_station_id"], name: "index_route_plan_events_on_origin_station_id"
    t.index ["user_id"], name: "index_route_plan_events_on_user_id"
  end

  create_table "saved_routes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "name"
    t.string "origin_station_id"
    t.string "destination_station_id"
    t.jsonb "legs", default: [], null: false
    t.integer "total_time_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_station_id"], name: "index_saved_routes_on_destination_station_id"
    t.index ["origin_station_id"], name: "index_saved_routes_on_origin_station_id"
    t.index ["user_id"], name: "index_saved_routes_on_user_id"
  end

  create_table "stations", id: false, force: :cascade do |t|
    t.string "station_id", null: false
    t.string "name", null: false
    t.string "short_name", default: "", null: false
    t.string "line", null: false
    t.string "type", null: false
    t.decimal "lat", precision: 10, scale: 7, null: false
    t.decimal "lng", precision: 10, scale: 7, null: false
    t.boolean "is_terminal", default: false, null: false
    t.boolean "is_interchange", default: false, null: false
    t.string "amenities", default: [], array: true
    t.string "open_time", default: "05:00", null: false
    t.string "close_time", default: "23:00", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line"], name: "index_stations_on_line"
    t.index ["name"], name: "idx_stations_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["station_id"], name: "index_stations_on_station_id", unique: true
    t.index ["type"], name: "index_stations_on_type"
  end

  create_table "transport_modes", id: false, force: :cascade do |t|
    t.string "id", null: false
    t.string "display_name", null: false
    t.string "plural_name", default: "", null: false
    t.string "sf_symbol", default: "", null: false
    t.string "color_hex", default: "#000000", null: false
    t.decimal "map_line_width_pt", default: "4.0", null: false
    t.jsonb "map_line_dash", default: [], null: false
    t.string "mk_directions_type", default: "transit", null: false
    t.boolean "is_user_selectable", default: true, null: false
    t.boolean "is_always_allowed", default: false, null: false
    t.string "lines", default: [], array: true
    t.string "default_accepted_payments", default: [], array: true
    t.text "notes", default: "", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "extra", default: {}, null: false
    t.index ["id"], name: "index_transport_modes_on_id", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "jti", null: false
    t.string "display_name", null: false
    t.integer "role", default: 0, null: false
    t.string "home_station_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["home_station_id"], name: "index_users_on_home_station_id"
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ar_world_maps", "users"
  add_foreign_key "route_plan_events", "users"
  add_foreign_key "saved_routes", "users"
end
