class AddCustomPathToEdges < ActiveRecord::Migration[7.1]
  # custom_path is true when staff drew the transfer polyline, so the iOS app draws it without Apple Maps.
  def change
    add_column :edges, :custom_path, :boolean, default: false, null: false
  end
end
