class AddColorHexToLines < ActiveRecord::Migration[7.1]
  # The table stays local to the migration so a later change to the Line model does not
  # change it.
  class MigrationLine < ActiveRecord::Base
    self.table_name = "lines"
  end

  LINE_COLORS = {
    "MRT3" => "#F2C230",
    "LRT1" => "#2E8C57",
    "LRT2" => "#6B3D99",
    "EDSA_CAROUSEL" => "#F58017",
    "COMMONWEALTH_BUS" => "#A64D0D",
    "JEEPNEY_QUIAPO_CUBAO" => "#E61A1A",
    "JEEPNEY_MAKATI" => "#00B8CC",
    "EJEEPNEY_BGC" => "#472EE0",
    "TRICYCLE_MANILA" => "#00AD7A",
    "JEEPNEY_CARTIMAR_LRT" => "#F2591A"
  }.freeze

  # The cache clear must run after the commit, so DDL runs in an explicit transaction.
  disable_ddl_transaction!

  def up
    transaction do
      add_column :lines, :color_hex, :string
      MigrationLine.reset_column_information
      LINE_COLORS.each { |line_id, color| set_color!(line_id, color) }
      bump_graph_version!
    end
    clear_graph_cache!
  end

  def down
    transaction do
      remove_column :lines, :color_hex
      bump_graph_version!
    end
    clear_graph_cache!
  end

  private

  def set_color!(line_id, color)
    updated = MigrationLine.where(id: line_id).update_all(color_hex: color, updated_at: Time.current)
    say("Line not found, skipped: #{line_id}") if updated.zero?
  end

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
