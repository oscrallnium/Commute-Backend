class DeferStationAccessPointsFk < ActiveRecord::Migration[7.1]
  # GraphService#insert_stop/#remove_stop renumber "<prefix>_STOPn" stations by rewriting
  # their primary key in place, chaining renames (STOP4 -> STOP5, STOP3 -> STOP4, ...) inside
  # one transaction. With the FK left at its default NOT DEFERRABLE, Postgres checks it right
  # after each UPDATE — so a chained rename always passes through an invalid intermediate
  # state, whichever table (stations or station_access_points) is renamed first in a given
  # step. DEFERRABLE INITIALLY DEFERRED pushes the check to COMMIT, once every id in the
  # chain is consistent again. ON DELETE CASCADE fires as a row action on delete and is
  # unaffected by this — only the timing of the referential check changes.
  def up
    remove_foreign_key :station_access_points, :stations
    add_foreign_key :station_access_points, :stations,
                     column: :station_id, primary_key: "station_id",
                     on_delete: :cascade, deferrable: :deferred
  end

  def down
    remove_foreign_key :station_access_points, :stations
    add_foreign_key :station_access_points, :stations,
                     column: :station_id, primary_key: "station_id",
                     on_delete: :cascade
  end
end
