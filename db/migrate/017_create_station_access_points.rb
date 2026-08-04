class CreateStationAccessPoints < ActiveRecord::Migration[7.1]
  # Street-level doors. A station row carries one coordinate — the centroid of the
  # structure — and for rail that point is on a viaduct or inside a building, not on any
  # pedestrian way. Every walk the client measures starts or ends at it, so MKDirections
  # has to snap it to whatever footpath happens to be nearest, and the transfer between
  # MRT-3 Taft Avenue and LRT-1 EDSA gets routed between two arbitrary snap points rather
  # than between the exit and the entrance the footbridge actually joins.
  #
  # ── Why a table and not columns on `stations` ─────────────────────────────────
  #
  # A station has an unbounded number of doors — Araneta-Cubao alone has several — so
  # fixed `entrance_lat`/`exit_lat` columns would either cap the count or fill the table
  # with nulls. Rows also let the admin editor add, move and delete one door at a time,
  # and give us ON DELETE CASCADE: GraphService#remove_stop already deletes stations, and
  # orphaned doors inside a jsonb blob would survive silently.
  #
  # ── The direction rule ────────────────────────────────────────────────────────
  #
  # `direction` NULL means "serves every direction". That is not a fallback bolted on for
  # awkward cases — it is the common case. Only MRT-3 has directional edges at all, so 33
  # of the 46 rail stations cannot express a direction even in principle, and stations
  # like MRT Ayala have a single concourse feeding both platforms.
  #
  # Selection is therefore one predicate, with no special-casing — see
  # StationAccessPoint.serving, which is where it lives:
  #
  #     WHERE station_id = :id
  #       AND (direction IS NULL OR direction = :dir)   -- only when :dir is known
  #       AND kind IN ('both', :needed)
  #
  #   • one NULL-direction row      → returned for northbound and southbound alike
  #   • two direction-tagged rows   → only the matching one is returned
  #   • a shared hall plus a
  #     direction-only side exit    → both returned; the caller picks the nearer
  #   • caller passes no direction  → every door returned, nearest-wins decides
  #   • no rows at all              → caller falls back to stations.lat/lng
  #
  # That fourth case is load-bearing and easy to get wrong: dropping to `direction IS
  # NULL` when the caller has no direction would make a station whose doors are all
  # direction-tagged report no doors at all, on exactly the LRT-1 and LRT-2 legs that can
  # never supply one.
  #
  # That last line is what makes this shippable empty: with no rows, every client behaves
  # exactly as it does today. Doors can be surveyed and added station by station, and
  # each one improves only its own station.
  #
  # ── Ownership ─────────────────────────────────────────────────────────────────
  #
  # CLAUDE.md reserves the `stations` and `edges` schemas to the Hono microservice. This
  # creates a new table and alters neither, and Rails is what actually assembles and
  # serves the graph — GraphController#show calls GraphService.assemble_graph against
  # these models, while HONO_API_URL is declared in render.yaml and referenced nowhere in
  # app/. A Hono reseed does not know this table exists and will leave it untouched,
  # which is the safe failure mode; the same is not true of migration 016's row updates.

  def up
    create_table :station_access_points, id: false do |t|
      # TEXT PK to match `stations` and `edges` — ids are meaningful and graph-shaped,
      # e.g. "MRT_TAFT_AVE_AP_FOOTBRIDGE", not opaque integers.
      t.string :access_point_id, null: false, primary_key: true
      t.string :station_id, null: false

      # Human label for the admin list and, later, for turn-by-turn text:
      # "Taft Ave / EDSA footbridge", "Gate 2 — Trinoma".
      t.string :name, null: false, default: ""

      # 'entrance' | 'exit' | 'both'. A string, matching how `type`, `mode`, `line` and
      # `direction` are already modelled here. 'both' is the default because most Manila
      # rail halls turnstile in and out through the same doors.
      t.string :kind, null: false, default: "both"

      # 'northbound' | 'southbound' | NULL. Mirrors `edges.direction`, which is also a
      # nullable string, so the two can be compared without translation.
      t.string :direction

      # Same precision as stations.lat/lng — 7 decimal places is ~1 cm, far finer than
      # anything a door needs, but keeping the columns identical means no rounding
      # surprises when a client compares an access point against a centroid.
      t.decimal :lat, precision: 10, scale: 7, null: false
      t.decimal :lng, precision: 10, scale: 7, null: false

      # Display order in the admin editor. Ties broken by access_point_id so the list is
      # never non-deterministic.
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :station_access_points, :station_id
    add_index :station_access_points, %i[station_id direction]

    # CASCADE, not nullify: a door belongs to its station and means nothing without it.
    add_foreign_key :station_access_points, :stations,
                    column: :station_id, primary_key: "station_id", on_delete: :cascade

    # Enforced in the database, not only in the model. The graph is written by three
    # different paths — the admin controllers, GraphService, and hand-run SQL — and a
    # 'entry' or 'eastbound' slipping in through any of them would make the selection
    # predicate above silently return nothing, which reads as "no doors" rather than as
    # an error.
    add_check_constraint :station_access_points,
                         "kind IN ('entrance', 'exit', 'both')",
                         name: "station_access_points_kind_check"
    add_check_constraint :station_access_points,
                         "direction IS NULL OR direction IN ('northbound', 'southbound')",
                         name: "station_access_points_direction_check"
    add_check_constraint :station_access_points,
                         "lat BETWEEN -90 AND 90 AND lng BETWEEN -180 AND 180",
                         name: "station_access_points_coords_check"
  end

  def down
    drop_table :station_access_points
  end
end
