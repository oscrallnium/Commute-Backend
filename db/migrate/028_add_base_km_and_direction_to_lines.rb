class AddBaseKmAndDirectionToLines < ActiveRecord::Migration[7.1]
  def up
    add_column :lines, :base_km, :decimal, precision: 6, scale: 2, default: 0, null: false
    add_column :lines, :direction, :string, default: "both", null: false
    add_check_constraint :lines, "base_km >= 0", name: "lines_base_km_check"
    add_check_constraint :lines, "direction IN ('both', 'one_way')", name: "lines_direction_check"

    # A line with any one-way edge runs one way.
    execute <<~SQL
      UPDATE lines SET direction = 'one_way'
      WHERE EXISTS (SELECT 1 FROM edges WHERE edges.line = lines.id AND edges.bidirectional = false)
    SQL
  end

  def down
    remove_check_constraint :lines, name: "lines_direction_check"
    remove_check_constraint :lines, name: "lines_base_km_check"
    remove_column :lines, :direction
    remove_column :lines, :base_km
  end
end
