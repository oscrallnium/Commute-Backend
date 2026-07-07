class AddEnforceOperatingHoursToGraphMeta < ActiveRecord::Migration[7.1]
  def change
    add_column :graph_meta, :enforce_operating_hours, :boolean, null: false, default: true
  end
end
