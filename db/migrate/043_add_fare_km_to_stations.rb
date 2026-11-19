class AddFareKmToStations < ActiveRecord::Migration[7.1]
  # The cache clear must run after the commit, so DDL runs in an explicit transaction.
  disable_ddl_transaction!

  def up
    transaction do
      add_column :stations, :fare_km, :decimal, precision: 7, scale: 2
      add_check_constraint :stations, "fare_km IS NULL OR fare_km >= 0", name: "stations_fare_km_check"
      bump_graph_version!
    end
    clear_graph_cache!
  end

  def down
    transaction do
      remove_check_constraint :stations, name: "stations_fare_km_check"
      remove_column :stations, :fare_km
      bump_graph_version!
    end
    clear_graph_cache!
  end

  private

  def bump_graph_version!
    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # A cache error does not fail the migration, because each entry also expires on its own.
  def clear_graph_cache!
    %w[full_graph graph_version routes_index].each { |key| Rails.cache.delete(key) }
    Rails.cache.delete_matched("stations*")
  rescue StandardError => e
    say "Graph cache not cleared: #{e.class}: #{e.message}"
  end
end
