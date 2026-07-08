class EnsureEnforceOperatingHours < ActiveRecord::Migration[7.1]
  def up
    # Migration 010 adds this column, but if it failed silently on Render
    # (e.g. connection pool crash during startup) it may not have been applied.
    # This guard makes the column idempotent across deployments.
    unless column_exists?(:graph_meta, :enforce_operating_hours)
      add_column :graph_meta, :enforce_operating_hours, :boolean, null: false, default: true
    end
  end

  def down; end
end
