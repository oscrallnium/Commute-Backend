class AddIsRoadSnappedToEdges < ActiveRecord::Migration[7.1]
  def change
    # Lets Explore trust a saved polyline directly instead of re-computing it via
    # MKDirections on every load. Never set anywhere until now (checked the seed
    # JSON and db/seeds.rb — zero occurrences), so every edge from the live
    # database has always decoded as isRoadSnapped == nil on iOS, meaning every
    # non-train edge's recorded polyline (Loop Creator recordings, admin polyline
    # edits, insert/remove-stop split/merge geometry) has always been silently
    # discarded and replaced by a fresh MKDirections guess.
    add_column :edges, :is_road_snapped, :boolean, null: false, default: false
  end
end
