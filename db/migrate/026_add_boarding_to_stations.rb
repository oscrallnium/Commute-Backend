class AddBoardingToStations < ActiveRecord::Migration[7.1]
  # The cache clear must run after the commit, so DDL runs in an explicit transaction.
  disable_ddl_transaction!

  def up
    transaction do
      add_column :stations, :boarding, :string, default: "both", null: false
      bump_graph_version!
    end
    clear_graph_cache!
  end

  def down
    transaction do
      remove_column :stations, :boarding
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
