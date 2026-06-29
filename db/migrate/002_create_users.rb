class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :uuid, default: "gen_random_uuid()" do |t|
      # Devise
      t.string   :email,              null: false, default: ""
      t.string   :encrypted_password, null: false, default: ""
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at

      # JWT
      t.string   :jti, null: false

      # App-specific
      t.string   :display_name,    null: false
      t.integer  :role,            null: false, default: 0   # 0=commuter, 1=admin
      t.string   :home_station_id  # FK to stations.station_id (TEXT PK)

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :jti,   unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :home_station_id
  end
end
