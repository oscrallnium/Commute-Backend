class AddModernJeepneyTransportMode < ActiveRecord::Migration[7.1]
  MODE_ID = "modern_jeepney".freeze

  def up
    insert_mode unless select_value("SELECT 1 FROM transport_modes WHERE id = #{quote(MODE_ID)}").present?

    execute <<~SQL.squish
      UPDATE payment_methods
      SET accepted_by_modes = array_append(accepted_by_modes, #{quote(MODE_ID)})
      WHERE id = 'cash' AND NOT (#{quote(MODE_ID)} = ANY(accepted_by_modes))
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE payment_methods
      SET accepted_by_modes = array_remove(accepted_by_modes, #{quote(MODE_ID)})
      WHERE id = 'cash'
    SQL
    execute "DELETE FROM transport_modes WHERE id = #{quote(MODE_ID)}"
  end

  private

  def insert_mode
    execute <<~SQL.squish
      INSERT INTO transport_modes
        (id, display_name, plural_name, sf_symbol, color_hex, map_line_width_pt, map_line_dash,
         mk_directions_type, is_user_selectable, is_always_allowed, lines,
         default_accepted_payments, notes, position, extra)
      VALUES
        (#{quote(MODE_ID)}, 'Modern Jeepney', 'Modern Jeepneys', 'bus', '#14A3A3', 4.0, '[]',
         'automobile', TRUE, FALSE, '{}', '{cash}', '',
         (SELECT COALESCE(MAX(position), 0) + 1 FROM transport_modes), '{}')
    SQL
  end
end
