class CreateLines < ActiveRecord::Migration[7.1]
  # Migration-local, not `::Line` — a migration should not depend on an application model
  # that is free to change shape later. `insert_all` only needs the table name.
  class MigrationLine < ActiveRecord::Base
    self.table_name = "lines"
  end

  # A line's display name has never had anywhere to live. `edges.line` and
  # `stations.line` are the route's *identifier* — "UPLB_KANAN", "EDSA_BUS" — and nothing
  # in the schema records what a passenger should actually read. `GraphService#add_route`
  # already requires the caller to submit a `displayName` (see `#validate`) but never
  # stored it anywhere; the client has been forced to supply a name every time a route is
  # created and the name has been silently discarded every time.
  #
  # A dedicated table, not a column on `edges`/`stations` — the same reason
  # `station_access_points` (migration 017) is its own table rather than columns there:
  # those two schemas are reserved to the Hono microservice, and a table Hono doesn't know
  # about is left untouched by a Hono reseed, whereas a column added there would not be.
  # `transport_modes` and `payment_methods` already establish this "id + display_name"
  # config-table shape; this follows the same one.
  def up
    create_table :lines, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :display_name, null: false
      # Nullable, not a foreign key to `transport_modes.id`: a handful of lines in
      # production (the two `STACRUZ.LRT_BUENDI*` ids) look like data-entry duplicates of
      # each other rather than a mode boundary worth enforcing in the schema, and this
      # table's job is to hold a name, not to police the graph it names.
      t.string :mode
      t.timestamps
    end

    # Backfill for every line already live in production, keyed by the exact `edges.line`
    # values returned by GET /api/v1/graph on 2026-08-08. Sourced from the live API, not
    # from db/seeds.rb's data/transit_graph_v3.json — that file predates several of these
    # (`UPLB_KANAN`, both `STACRUZ.LRT_BUENDI*` ids) and still lists one, `EJEEPNEY_BGC`,
    # that no longer has any edges. `EJEEPNEY_BGC` is kept here anyway: it costs nothing to
    # name a line with no edges yet, and CLAUDE.md's own line reference still documents it.
    now = Time.current
    rows = [
      { id: "MRT-3",                 display_name: "MRT-3",                 mode: "train" },
      { id: "LRT-1",                 display_name: "LRT-1",                 mode: "train" },
      { id: "LRT-2",                 display_name: "LRT-2",                 mode: "train" },
      { id: "EDSA_BUS",              display_name: "EDSA Bus",              mode: "bus" },
      { id: "COMMONWEALTH_BUS",      display_name: "Commonwealth Bus",      mode: "bus" },
      { id: "STACRUZ.LRT_BUENDIA",   display_name: "Sta. Cruz-LRT Buendia", mode: "bus" },
      { id: "STACRUZ.LRT_BUENDI",    display_name: "Sta. Cruz-LRT Buendia", mode: "bus" },
      { id: "JEEPNEY_QUIAPO_CUBAO",  display_name: "Quiapo-Cubao",          mode: "jeepney" },
      { id: "JEEPNEY_CARTIMAR_LRT",  display_name: "Cartimar-LRT",          mode: "jeepney" },
      { id: "JEEPNEY_MAKATI",        display_name: "Makati Jeepney",        mode: "jeepney" },
      { id: "UPLB_KANAN",            display_name: "UPLB Kanan",            mode: "jeepney" },
      { id: "EJEEPNEY_BGC",          display_name: "BGC E-Jeepney",         mode: "jeepney" },
      { id: "TRICYCLE_MANILA",       display_name: "Manila Tricycle",       mode: "tricycle" },
      { id: "INTERCHANGE",           display_name: "Interchange",           mode: "walk" }
    ].map { |r| r.merge(created_at: now, updated_at: now) }
    MigrationLine.reset_column_information
    MigrationLine.insert_all(rows) # the table is brand new, so no conflicts to upsert against
  end

  def down
    drop_table :lines
  end
end
