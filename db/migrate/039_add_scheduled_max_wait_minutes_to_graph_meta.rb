class AddScheduledMaxWaitMinutesToGraphMeta < ActiveRecord::Migration[7.1]
  # The longest wait, in minutes, that the app accepts for a scheduled trip.
  def change
    add_column :graph_meta, :scheduled_max_wait_minutes, :integer, null: false, default: 60
    add_check_constraint :graph_meta, "scheduled_max_wait_minutes >= 1 AND scheduled_max_wait_minutes <= 600",
                         name: "graph_meta_scheduled_max_wait_minutes_check"
  end
end
