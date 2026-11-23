class NullifyRoutePlanEventsUserOnDelete < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :route_plan_events, :users
    add_foreign_key :route_plan_events, :users, on_delete: :nullify
  end

  def down
    remove_foreign_key :route_plan_events, :users
    add_foreign_key :route_plan_events, :users
  end
end
