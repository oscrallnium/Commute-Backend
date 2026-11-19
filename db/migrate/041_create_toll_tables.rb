class CreateTollTables < ActiveRecord::Migration[7.1]
  def change
    create_table :toll_plazas, id: :string do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :toll_fares do |t|
      t.string :entry_plaza_id, null: false
      t.string :exit_plaza_id, null: false
      t.decimal :amount, precision: 8, scale: 2, null: false
      t.timestamps
      t.index %i[entry_plaza_id exit_plaza_id], unique: true
      t.check_constraint "amount >= 0", name: "toll_fares_amount_check"
      t.check_constraint "entry_plaza_id <> exit_plaza_id", name: "toll_fares_distinct_plazas_check"
    end
    add_foreign_key :toll_fares, :toll_plazas, column: :entry_plaza_id
    add_foreign_key :toll_fares, :toll_plazas, column: :exit_plaza_id

    change_table :edges do |t|
      t.string :toll_entry_plaza_id
      t.string :toll_exit_plaza_id
      t.index :toll_entry_plaza_id
      t.index :toll_exit_plaza_id
    end
    add_foreign_key :edges, :toll_plazas, column: :toll_entry_plaza_id
    add_foreign_key :edges, :toll_plazas, column: :toll_exit_plaza_id

    add_column :lines, :toll_load_factor, :integer
    add_check_constraint :lines, "toll_load_factor > 0", name: "lines_toll_load_factor_check"
  end
end
