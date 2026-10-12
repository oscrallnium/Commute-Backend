class CreateGraphVersions < ActiveRecord::Migration[7.1]
  # One row per publish. Versions from other admin writes have no row.
  def change
    create_table :graph_versions do |t|
      t.integer :version, null: false
      t.datetime :published_at, null: false
      t.references :published_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.jsonb :change_list, null: false, default: []
      t.integer :change_count, null: false
      t.index :version, unique: true
    end
  end
end
