class AddAccessPointsToEdges < ActiveRecord::Migration[7.1]
  # A transfer edge can name the access point at each end. Both columns stay null for every
  # other edge. The foreign keys are deferred so that one transaction can add an access point
  # and a transfer in any order. Deleting an access point deletes the transfers that use it.
  def up
    add_column :edges, :from_access_point_id, :string
    add_column :edges, :to_access_point_id, :string
    add_index :edges, :from_access_point_id
    add_index :edges, :to_access_point_id
    add_foreign_key :edges, :station_access_points,
                    column: :from_access_point_id, primary_key: "access_point_id",
                    on_delete: :cascade, deferrable: :deferred
    add_foreign_key :edges, :station_access_points,
                    column: :to_access_point_id, primary_key: "access_point_id",
                    on_delete: :cascade, deferrable: :deferred
  end

  def down
    remove_foreign_key :edges, column: :to_access_point_id
    remove_foreign_key :edges, column: :from_access_point_id
    remove_index :edges, :to_access_point_id
    remove_index :edges, :from_access_point_id
    remove_column :edges, :to_access_point_id
    remove_column :edges, :from_access_point_id
  end
end
