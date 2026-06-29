class CreateIncidents < ActiveRecord::Migration[7.1]
  def change
    create_table :incidents, id: :uuid, default: "gen_random_uuid()" do |t|
      t.string   :station_id   # nullable — some incidents are line-wide
      t.string   :line_id
      t.integer  :category,    null: false, default: 4  # 'other'
      t.text     :description
      t.uuid     :reported_by  # user.id — not a FK so deletion doesn't cascade
      t.datetime :expires_at   # nil = open-ended
      t.timestamps
    end

    add_index :incidents, :station_id
    add_index :incidents, :line_id
    add_index :incidents, :expires_at
  end
end
