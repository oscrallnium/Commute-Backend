class BootstrapAdminAndGraphMeta < ActiveRecord::Migration[7.1]
  def up
    # ── Ensure GraphMeta has exactly one row ─────────────────────────────────
    unless GraphMeta.exists?
      GraphMeta.create!(
        version: 1,
        last_modified: Time.current,
        schema_version: "3.0.0",
        region: "Metro Manila, Philippines",
        currency: "PHP",
        enforce_operating_hours: true
      )
      Rails.logger.info "[bootstrap] GraphMeta row created."
    end

    # ── Ensure app admin exists ───────────────────────────────────────────────
    unless User.exists?(email: "admin@commutebeh.ph")
      User.create!(
        email: "admin@commutebeh.ph",
        password: "Admin1234!",
        password_confirmation: "Admin1234!",
        display_name: "Gora Admin",
        role: 1
      )
      Rails.logger.info "[bootstrap] admin@commutebeh.ph created."
    else
      User.where(email: "admin@commutebeh.ph").update_all(role: 1)
      Rails.logger.info "[bootstrap] admin@commutebeh.ph role ensured."
    end

    # ── Fix the developer account ─────────────────────────────────────────────
    # Delete any commuter record for the dev email so it can be re-registered
    # with the correct admin role and password.
    oscar = User.find_by(email: "oscar@agiledigital.com.ph")
    if oscar
      oscar.destroy! if oscar.role == "commuter"
      oscar = User.find_by(email: "oscar@agiledigital.com.ph") # reload
    end

    unless oscar
      User.create!(
        email: "oscar@agiledigital.com.ph",
        password: "Gora2026!",
        password_confirmation: "Gora2026!",
        display_name: "Oscar Allen Brioso",
        role: 1
      )
      Rails.logger.info "[bootstrap] oscar@agiledigital.com.ph admin created."
    else
      oscar.update_column(:role, 1)
      Rails.logger.info "[bootstrap] oscar@agiledigital.com.ph promoted to admin."
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
