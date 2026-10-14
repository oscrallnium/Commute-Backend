class AddUvExpressTransportMode < ActiveRecord::Migration[7.1]
  MODE_ID = "uv_express".freeze

  def up
    return if select_value("SELECT 1 FROM transport_modes WHERE id = #{quote(MODE_ID)}").present?

    execute <<~SQL.squish
      INSERT INTO transport_modes
        (id, display_name, plural_name, sf_symbol, color_hex, map_line_width_pt, map_line_dash,
         mk_directions_type, is_user_selectable, is_always_allowed, lines,
         default_accepted_payments, notes, position, extra)
      VALUES
        (#{quote(MODE_ID)}, 'UV Express', 'UV Express', 'car.side.fill', '#8E5CF7', 4.0, '[]',
         'automobile', TRUE, FALSE, '{}', '{cash}', '',
         (SELECT COALESCE(MAX(position), 0) + 1 FROM transport_modes), '{}')
    SQL
  end

  def down
    execute "DELETE FROM transport_modes WHERE id = #{quote(MODE_ID)}"
  end
end
