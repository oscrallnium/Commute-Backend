class AddServiceShapeToTransportModes < ActiveRecord::Migration[7.1]
  def up
    add_column :transport_modes, :service_shape, :string, null: false, default: "path"
    add_check_constraint :transport_modes, "service_shape IN ('path', 'area')",
                         name: "transport_modes_service_shape_check"
    execute "UPDATE transport_modes SET service_shape = 'area' WHERE id = 'tricycle'"
  end

  def down
    remove_check_constraint :transport_modes, name: "transport_modes_service_shape_check"
    remove_column :transport_modes, :service_shape
  end
end
