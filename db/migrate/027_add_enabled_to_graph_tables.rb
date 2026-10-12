class AddEnabledToGraphTables < ActiveRecord::Migration[7.1]
  # A constant default adds the column without a table rewrite on PostgreSQL 11 and later.
  def change
    %i[lines stations edges].each do |table|
      add_column table, :enabled, :boolean, default: true, null: false
      add_column table, :disabled_reason, :string
    end
  end
end
