class SetModernBusSymbol < ActiveRecord::Migration[7.1]
  MODE_ID = "modern_bus".freeze

  # "modern.bus" is a custom symbol. Each client draws it from its own asset catalog.
  def up
    execute "UPDATE transport_modes SET sf_symbol = 'modern.bus' WHERE id = #{quote(MODE_ID)}"
  end

  def down
    execute "UPDATE transport_modes SET sf_symbol = 'bus.fill' WHERE id = #{quote(MODE_ID)}"
  end
end
