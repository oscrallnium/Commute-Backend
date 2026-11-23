class CreateUserIdentities < ActiveRecord::Migration[7.1]
  def change
    create_table :user_identities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, index: false,
                          foreign_key: { on_delete: :cascade }
      t.integer :provider, null: false
      t.string  :uid, null: false
      t.string  :email
      t.text    :apple_refresh_token
      t.boolean :email_relay_enabled # rubocop:disable Rails/ThreeStateBooleanColumn
      t.timestamps
    end

    add_index :user_identities, %i[provider uid], unique: true
    add_index :user_identities, %i[user_id provider], unique: true
  end
end
