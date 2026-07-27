class AddPrimaryKeysToGraphTables < ActiveRecord::Migration[7.1]
  # Migration 009 created every graph table with `id: false` and only a UNIQUE
  # INDEX on its natural key. The Rails models declare `self.primary_key =
  # "station_id"` / `"edge_id"`, but that's an ActiveRecord-level setting only —
  # Postgres itself has no PRIMARY KEY constraint on these tables.
  #
  # Nothing in the Rails app noticed (it always addresses rows by the unique
  # column), but anything that identifies a row generically does: the Supabase
  # table editor refuses to UPDATE or DELETE a row in a table with no primary
  # key ("requires primary identifiers"), and logical replication falls back to
  # REPLICA IDENTITY NOTHING for the same reason.
  #
  # `USING INDEX` promotes the existing unique index into the constraint's index
  # instead of building a second identical one — the index is just renamed to
  # <table>_pkey. Requires the index to be unique, non-partial, and its columns
  # NOT NULL; all five satisfy that already.
  TABLES = {
    stations:        %w[station_id index_stations_on_station_id],
    edges:           %w[edge_id index_edges_on_edge_id],
    transport_modes: %w[id index_transport_modes_on_id],
    payment_methods: %w[id index_payment_methods_on_id],
    fare_matrix:     %w[line_name index_fare_matrix_on_line_name]
  }.freeze

  def up
    TABLES.each do |table, (column, index_name)|
      next if primary_key(table.to_s).present?

      if index_name_exists?(table, index_name)
        execute <<~SQL
          ALTER TABLE #{table}
          ADD CONSTRAINT #{table}_pkey PRIMARY KEY USING INDEX #{index_name}
        SQL
      else
        # Index missing (hand-edited database) — let Postgres build its own.
        execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_pkey PRIMARY KEY (#{column})"
      end
    end
  end

  def down
    TABLES.each do |table, (column, index_name)|
      next if primary_key(table.to_s).blank?

      execute "ALTER TABLE #{table} DROP CONSTRAINT #{table}_pkey"
      add_index table, column.to_sym, unique: true, name: index_name
    end
  end
end
