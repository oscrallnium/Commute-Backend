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

ActiveRecord::Schema[7.2].define(version: 47) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
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

  create_table "edges", primary_key: "edge_id", id: :string, force: :cascade do |t|
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
    t.boolean "is_road_snapped", default: false, null: false
    t.boolean "enabled", default: true, null: false
    t.string "disabled_reason"
    t.string "from_access_point_id"
    t.string "to_access_point_id"
    t.boolean "custom_path", default: false, null: false
    t.string "toll_entry_plaza_id"
    t.string "toll_exit_plaza_id"
    t.index ["from_access_point_id"], name: "index_edges_on_from_access_point_id"
    t.index ["from_station"], name: "index_edges_on_from_station"
    t.index ["line"], name: "index_edges_on_line"
    t.index ["mode"], name: "index_edges_on_mode"
    t.index ["to_access_point_id"], name: "index_edges_on_to_access_point_id"
    t.index ["to_station"], name: "index_edges_on_to_station"
    t.index ["toll_entry_plaza_id"], name: "index_edges_on_toll_entry_plaza_id"
    t.index ["toll_exit_plaza_id"], name: "index_edges_on_toll_exit_plaza_id"
  end

  create_table "fare_matrix", primary_key: "line_name", id: :string, force: :cascade do |t|
    t.string "type", default: "flat", null: false
    t.jsonb "data", default: {}, null: false
  end

  create_table "graph_meta", force: :cascade do |t|
    t.integer "version", default: 1, null: false
    t.datetime "last_modified", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "schema_version", default: "3.0.0", null: false
    t.string "region", default: "Metro Manila, Philippines", null: false
    t.string "currency", default: "PHP", null: false
    t.boolean "enforce_operating_hours", default: true, null: false
    t.integer "scheduled_max_wait_minutes", default: 60, null: false
    t.check_constraint "scheduled_max_wait_minutes >= 1 AND scheduled_max_wait_minutes <= 600", name: "graph_meta_scheduled_max_wait_minutes_check"
  end

  create_table "graph_versions", force: :cascade do |t|
    t.integer "version", null: false
    t.datetime "published_at", null: false
    t.uuid "published_by_id"
    t.jsonb "change_list", default: [], null: false
    t.integer "change_count", null: false
    t.index ["published_by_id"], name: "index_graph_versions_on_published_by_id"
    t.index ["version"], name: "index_graph_versions_on_version", unique: true
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

  create_table "lines", id: :string, force: :cascade do |t|
    t.string "display_name", null: false
    t.string "mode"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "last_stop_number", default: 0, null: false
    t.string "color_hex"
    t.boolean "enabled", default: true, null: false
    t.string "disabled_reason"
    t.decimal "base_km", precision: 6, scale: 2, default: "0.0", null: false
    t.string "direction", default: "both", null: false
    t.integer "toll_load_factor"
    t.decimal "fare_step_km", precision: 6, scale: 2
    t.check_constraint "base_km >= 0::numeric", name: "lines_base_km_check"
    t.check_constraint "direction::text = ANY (ARRAY['both'::character varying::text, 'one_way'::character varying::text])", name: "lines_direction_check"
    t.check_constraint "fare_step_km IS NULL OR fare_step_km >= 0::numeric", name: "lines_fare_step_km_check"
    t.check_constraint "toll_load_factor > 0", name: "lines_toll_load_factor_check"
  end

  create_table "payment_methods", id: :string, force: :cascade do |t|
    t.string "display_name", null: false
    t.string "sf_symbol", default: "", null: false
    t.string "color_hex", default: "#000000", null: false
    t.boolean "is_default", default: false, null: false
    t.string "accepted_by_modes", default: [], array: true
    t.text "notes", default: "", null: false
  end

  create_table "peak_hour_config", force: :cascade do |t|
    t.jsonb "data", default: {}, null: false
  end

  create_table "rail_fare_tables", primary_key: "line_id", id: :string, force: :cascade do |t|
    t.jsonb "station_ids", default: [], null: false
    t.jsonb "fares", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "service_areas", primary_key: "line_id", id: :string, force: :cascade do |t|
    t.jsonb "boundary", default: [], null: false
    t.decimal "base_fare", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "base_km", precision: 6, scale: 2, default: "0.0", null: false
    t.decimal "fare_per_km", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "special_trip_fare", precision: 8, scale: 2
    t.decimal "speed_kmh", precision: 5, scale: 2, default: "15.0", null: false
    t.decimal "detour_factor", precision: 4, scale: 2, default: "1.3", null: false
    t.decimal "wait_minutes", precision: 5, scale: 2, default: "3.0", null: false
    t.string "accepted_payments", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "base_fare >= 0::numeric", name: "service_areas_base_fare_check"
    t.check_constraint "base_km >= 0::numeric", name: "service_areas_base_km_check"
    t.check_constraint "detour_factor >= 1::numeric", name: "service_areas_detour_factor_check"
    t.check_constraint "fare_per_km >= 0::numeric", name: "service_areas_fare_per_km_check"
    t.check_constraint "special_trip_fare IS NULL OR special_trip_fare >= 0::numeric", name: "service_areas_special_trip_fare_check"
    t.check_constraint "speed_kmh > 0::numeric", name: "service_areas_speed_kmh_check"
    t.check_constraint "wait_minutes >= 0::numeric", name: "service_areas_wait_minutes_check"
  end

  create_table "service_schedule_exceptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "line_id", null: false
    t.string "direction"
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.string "kind", null: false
    t.string "start_time"
    t.string "end_time"
    t.string "departure_times", default: [], null: false, array: true
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line_id", "start_date"], name: "index_service_schedule_exceptions_on_line_id_and_start_date"
    t.check_constraint "end_date >= start_date", name: "service_schedule_exceptions_dates_check"
  end

  create_table "service_schedules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "line_id", null: false
    t.string "direction"
    t.string "days", default: [], null: false, array: true
    t.string "kind", null: false
    t.string "start_time"
    t.string "end_time"
    t.string "departure_times", default: [], null: false, array: true
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line_id", "direction"], name: "index_service_schedules_on_line_id_and_direction"
  end

  create_table "station_access_points", primary_key: "access_point_id", id: :string, force: :cascade do |t|
    t.string "station_id", null: false
    t.string "name", default: "", null: false
    t.string "kind", default: "both", null: false
    t.string "direction"
    t.decimal "lat", precision: 10, scale: 7, null: false
    t.decimal "lng", precision: 10, scale: 7, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["station_id", "direction"], name: "index_station_access_points_on_station_id_and_direction"
    t.index ["station_id"], name: "index_station_access_points_on_station_id"
    t.check_constraint "direction IS NULL OR (direction::text = ANY (ARRAY['northbound'::character varying::text, 'southbound'::character varying::text, 'eastbound'::character varying::text, 'westbound'::character varying::text, 'inbound'::character varying::text, 'outbound'::character varying::text]))", name: "station_access_points_direction_check"
    t.check_constraint "kind::text = ANY (ARRAY['entrance'::character varying::text, 'exit'::character varying::text, 'both'::character varying::text])", name: "station_access_points_kind_check"
    t.check_constraint "lat >= '-90'::integer::numeric AND lat <= 90::numeric AND lng >= '-180'::integer::numeric AND lng <= 180::numeric", name: "station_access_points_coords_check"
  end

  create_table "stations", primary_key: "station_id", id: :string, force: :cascade do |t|
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
    t.integer "sequence"
    t.string "boarding", default: "both", null: false
    t.boolean "enabled", default: true, null: false
    t.string "disabled_reason"
    t.decimal "fare_km", precision: 7, scale: 2
    t.index ["line", "sequence"], name: "index_stations_on_line_and_sequence"
    t.index ["line"], name: "index_stations_on_line"
    t.index ["name"], name: "idx_stations_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["type"], name: "index_stations_on_type"
    t.check_constraint "fare_km IS NULL OR fare_km >= 0::numeric", name: "stations_fare_km_check"
  end

  create_table "tester_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.integer "age", null: false
    t.string "location", null: false
    t.citext "email", null: false
    t.string "status", default: "pending", null: false
    t.datetime "consent_at", null: false
    t.string "source", default: "website", null: false
    t.string "asc_beta_tester_id"
    t.datetime "invited_at"
    t.uuid "invited_by_id"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_tester_requests_on_email", unique: true
    t.index ["status", "created_at"], name: "index_tester_requests_on_status_and_created_at"
    t.check_constraint "age >= 16", name: "tester_requests_age_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'inviting'::character varying, 'invited'::character varying, 'failed'::character varying, 'declined'::character varying]::text[])", name: "tester_requests_status_check"
  end

  create_table "toll_fares", force: :cascade do |t|
    t.string "entry_plaza_id", null: false
    t.string "exit_plaza_id", null: false
    t.decimal "amount", precision: 8, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entry_plaza_id", "exit_plaza_id"], name: "index_toll_fares_on_entry_plaza_id_and_exit_plaza_id", unique: true
    t.check_constraint "amount >= 0::numeric", name: "toll_fares_amount_check"
    t.check_constraint "entry_plaza_id::text <> exit_plaza_id::text", name: "toll_fares_distinct_plazas_check"
  end

  create_table "toll_plazas", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "transport_modes", id: :string, force: :cascade do |t|
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
    t.string "service_shape", default: "path", null: false
    t.check_constraint "service_shape::text = ANY (ARRAY['path'::character varying::text, 'area'::character varying::text])", name: "transport_modes_service_shape_check"
  end

  create_table "user_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.integer "provider", null: false
    t.string "uid", null: false
    t.string "email"
    t.text "apple_refresh_token"
    t.boolean "email_relay_enabled"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "uid"], name: "index_user_identities_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_user_identities_on_user_id_and_provider", unique: true
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
  add_foreign_key "edges", "station_access_points", column: "from_access_point_id", primary_key: "access_point_id", on_delete: :cascade, deferrable: :deferred
  add_foreign_key "edges", "station_access_points", column: "to_access_point_id", primary_key: "access_point_id", on_delete: :cascade, deferrable: :deferred
  add_foreign_key "edges", "toll_plazas", column: "toll_entry_plaza_id"
  add_foreign_key "edges", "toll_plazas", column: "toll_exit_plaza_id"
  add_foreign_key "graph_versions", "users", column: "published_by_id", on_delete: :nullify
  add_foreign_key "route_plan_events", "users", on_delete: :nullify
  add_foreign_key "saved_routes", "users"
  add_foreign_key "service_areas", "lines", on_delete: :cascade
  add_foreign_key "service_schedule_exceptions", "lines", on_delete: :cascade
  add_foreign_key "service_schedules", "lines", on_delete: :cascade
  add_foreign_key "station_access_points", "stations", primary_key: "station_id", on_delete: :cascade, deferrable: :deferred
  add_foreign_key "toll_fares", "toll_plazas", column: "entry_plaza_id"
  add_foreign_key "toll_fares", "toll_plazas", column: "exit_plaza_id"
  add_foreign_key "user_identities", "users", on_delete: :cascade
end
