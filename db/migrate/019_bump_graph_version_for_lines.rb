class BumpGraphVersionForLines < ActiveRecord::Migration[7.1]
  # Migration 018 added the `lines` table and backfilled it, but touched nothing
  # GraphMeta-related — so every client's version check (GraphService.swift#syncIfNeeded
  # on iOS) still sees the same version number it already has cached and skips
  # re-downloading, even on a fresh app launch. `lines` being live on the server was
  # never enough on its own; the version has to move for anyone to notice.
  #
  # Same increment GraphService#bump_graph_version! uses everywhere else, so this reads
  # to any client exactly like an ordinary route edit — no separate case to handle.
  def up
    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # Deliberately no `down`: a client that already picked up the higher version and
  # cached the `lines` data has no way to be told to forget it, so decrementing the
  # counter back here would not actually undo anything visible — it would just make a
  # later, real change collide with a version number some clients already believe they
  # have seen.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
