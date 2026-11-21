class CreateTesterRequests < ActiveRecord::Migration[7.1]
  STATUSES = %w[pending inviting invited failed declined].freeze

  def up
    enable_extension "citext" unless extension_enabled?("citext")

    create_table :tester_requests, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :name
      t.integer  :age, null: false
      t.string   :location, null: false
      t.citext   :email, null: false
      t.string   :status, null: false, default: "pending"
      t.datetime :consent_at, null: false
      t.string   :source, null: false, default: "website"
      t.string   :asc_beta_tester_id
      t.datetime :invited_at
      t.uuid     :invited_by_id
      t.text     :last_error
      t.timestamps
    end

    add_index :tester_requests, :email, unique: true
    add_index :tester_requests, %i[status created_at]
    add_check_constraint :tester_requests, "age >= 16", name: "tester_requests_age_check"
    add_check_constraint :tester_requests, "status IN (#{STATUSES.map { |s| "'#{s}'" }.join(", ")})",
                         name: "tester_requests_status_check"
  end

  # Leaves the citext extension in place, because other tables can use it.
  def down
    drop_table :tester_requests
  end
end
