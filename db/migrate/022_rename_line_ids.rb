class RenameLineIds < ActiveRecord::Migration[7.1]
  # Each entry renames one line. `previous_name` is nil when `down` keeps the current name.
  RENAMES = [
    { old_id: "MRT-3", new_id: "MRT3", name: "MRT-3", previous_name: "MRT-3" },
    { old_id: "LRT-1", new_id: "LRT1", name: "LRT-1", previous_name: "LRT-1" },
    { old_id: "LRT-2", new_id: "LRT2", name: "LRT-2", previous_name: "LRT-2" },
    { old_id: "EDSA_BUS", new_id: "EDSA_CAROUSEL", name: "EDSA Carousel", previous_name: "EDSA Bus" },
    { old_id: "GUADALUPE_LRT.BUENDIA", new_id: "GUADALUPE_BUENDIA",
      name: "Guadalupe–LRT Buendia", previous_name: nil },
    { old_id: "STACRUZ.LRT_BUENDI", new_id: "STA_CRUZ_BUENDIA",
      name: "Sta. Cruz–LRT Buendia", previous_name: "Sta. Cruz-LRT Buendia" }
  ].freeze

  # Station ids and edge ids stay the same. Only the line columns change.
  def up
    transaction do
      RENAMES.each { |r| rename_line!(from: r[:old_id], to: r[:new_id], display_name: r[:name]) }
      bump_graph_version!
    end
    clear_graph_cache!
  end

  # Restores the old ids. A deleted empty target row is not recreated.
  def down
    transaction do
      RENAMES.each do |r|
        rename_line!(from: r[:new_id], to: r[:old_id], display_name: r[:previous_name])
      end
      bump_graph_version!
    end
    clear_graph_cache!
  end

  private

  # Skips a line that has no `lines` row. Raises when the target id already has stations or edges.
  def rename_line!(from:, to:, display_name:)
    return unless line_exists?(from)

    clear_empty_target!(to)
    copy_line_row!(from: from, to: to, display_name: display_name)
    update_line_references!(from: from, to: to)
    execute "DELETE FROM lines WHERE id = #{quote(from)}"
  end

  def line_exists?(id)
    select_value("SELECT 1 FROM lines WHERE id = #{quote(id)}").present?
  end

  def clear_empty_target!(id)
    used = select_value(<<~SQL.squish)
      SELECT (SELECT COUNT(*) FROM stations WHERE line = #{quote(id)})
           + (SELECT COUNT(*) FROM edges WHERE line = #{quote(id)})
    SQL
    raise "Line #{id} already has stations or edges" if used.to_i.positive?

    execute "DELETE FROM lines WHERE id = #{quote(id)}"
  end

  # Inserts the new row before the children move, so the old primary key is never updated.
  def copy_line_row!(from:, to:, display_name:)
    columns = connection.columns(:lines).map(&:name)
    selected = columns.map do |column|
      case column
      when "id" then quote(to)
      when "display_name" then display_name ? quote(display_name) : column
      else column
      end
    end
    execute <<~SQL.squish
      INSERT INTO lines (#{columns.join(', ')})
      SELECT #{selected.join(', ')} FROM lines WHERE id = #{quote(from)}
    SQL
  end

  # Updates every column that stores a line id. Add a new such column here.
  def update_line_references!(from:, to:)
    old_id = quote(from)
    new_id = quote(to)
    execute "UPDATE stations SET line = #{new_id} WHERE line = #{old_id}"
    execute "UPDATE edges SET line = #{new_id} WHERE line = #{old_id}"
    execute "UPDATE fare_matrix SET line_name = #{new_id} WHERE line_name = #{old_id}"
    execute "UPDATE incidents SET line_id = #{new_id} WHERE line_id = #{old_id}"
    execute "UPDATE transport_modes SET lines = array_replace(lines, #{old_id}, #{new_id}) " \
            "WHERE #{old_id} = ANY(lines)"
  end

  def bump_graph_version!
    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # Runs after the commit, so no request can cache the old line IDs again. A cache error does
  # not fail the migration, because each entry also expires on its own.
  def clear_graph_cache!
    %w[full_graph graph_version routes_index].each { |key| Rails.cache.delete(key) }
    Rails.cache.delete_matched("stations*")
  rescue StandardError => e
    say "Graph cache not cleared: #{e.class}: #{e.message}"
  end

  def quote(value) = connection.quote(value)

  def select_value(sql) = connection.select_value(sql)
end
