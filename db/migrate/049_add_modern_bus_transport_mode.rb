class AddModernBusTransportMode < ActiveRecord::Migration[7.1]
  MODE_ID = "modern_bus".freeze
  PAYMENT_IDS = %w[cash beep_card].freeze

  def up
    insert_mode unless select_value("SELECT 1 FROM transport_modes WHERE id = #{quote(MODE_ID)}").present?

    execute <<~SQL.squish
      UPDATE payment_methods
      SET accepted_by_modes = array_append(accepted_by_modes, #{quote(MODE_ID)})
      WHERE id IN (#{quoted_payment_ids}) AND NOT (#{quote(MODE_ID)} = ANY(accepted_by_modes))
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE payment_methods
      SET accepted_by_modes = array_remove(accepted_by_modes, #{quote(MODE_ID)})
      WHERE id IN (#{quoted_payment_ids})
    SQL
    execute "DELETE FROM transport_modes WHERE id = #{quote(MODE_ID)}"
  end

  private

  def quoted_payment_ids
    PAYMENT_IDS.map { |id| quote(id) }.join(", ")
  end

  def insert_mode
    execute <<~SQL.squish
      INSERT INTO transport_modes
        (id, display_name, plural_name, sf_symbol, color_hex, map_line_width_pt, map_line_dash,
         mk_directions_type, is_user_selectable, is_always_allowed, lines,
         default_accepted_payments, notes, position, extra)
      VALUES
        (#{quote(MODE_ID)}, 'Modern Bus', 'Modern Buses', 'bus.fill', '#1D9E5E', 4.0, '[]',
         'transit', TRUE, FALSE, '{}', '{beep_card,cash}', '',
         (SELECT COALESCE(MAX(position), 0) + 1 FROM transport_modes), '{}')
    SQL
  end
end
