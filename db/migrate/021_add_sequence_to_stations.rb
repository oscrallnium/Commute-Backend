class AddSequenceToStations < ActiveRecord::Migration[7.1]
  # `stations.sequence` holds the travel order of a stop inside its chain, so stop ids never
  # change when a stop is inserted or removed. Legacy "<chain>_STOP<n>" stations take n.
  # `lines.last_stop_number` is the per-line counter for generated stop ids. It starts at the
  # highest `_S<n>` of the line. The version bump makes clients download the new fields.
  def up
    add_column :stations, :sequence, :integer
    add_index :stations, %i[line sequence]

    execute <<~SQL.squish
      UPDATE stations
      SET sequence = substring(station_id FROM '_STOP([0-9]+)$')::integer
      WHERE station_id ~ '^.+_STOP[0-9]+$'
    SQL

    add_column :lines, :last_stop_number, :integer, null: false, default: 0
    execute <<~SQL.squish
      UPDATE lines
      SET last_stop_number = COALESCE((
        SELECT MAX(substring(stations.station_id FROM '_S([0-9]+)$')::integer)
        FROM stations
        WHERE stations.line = lines.id AND stations.station_id ~ '_S[0-9]+$'
      ), 0)
    SQL

    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # The version bump stays: a client that cached the higher version must not see it reused.
  def down
    remove_column :lines, :last_stop_number
    remove_index :stations, %i[line sequence]
    remove_column :stations, :sequence
  end
end
