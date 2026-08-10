class BootstrapAdminAndGraphMeta < ActiveRecord::Migration[7.1]
  # Bootstrap passwords come from the environment, never from this file.
  #
  # These credentials previously sat in the source as string literals, in a public
  # repository, for accounts that exist in production with role: admin — which is
  # full graph-mutation access. Anyone who read the file had them.
  #
  # The fallback is deliberately a random value that is logged once and never
  # recoverable: a bootstrap that quietly falls back to a *known* default is the
  # same exposure with extra steps. If the env var is unset, the operator is
  # expected to read the log line and reset the password immediately.
  def bootstrap_password(env_key)
    ENV.fetch(env_key) do
      generated = SecureRandom.base58(24)
      Rails.logger.warn(
        "[bootstrap] #{env_key} not set — generated a random password. " \
        "Reset it now; it is not stored anywhere: #{generated}"
      )
      generated
    end
  end

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
      admin_password = bootstrap_password("BOOTSTRAP_ADMIN_PASSWORD")
      User.create!(
        email: "admin@commutebeh.ph",
        password: admin_password,
        password_confirmation: admin_password,
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
      dev_password = bootstrap_password("BOOTSTRAP_DEV_PASSWORD")
      User.create!(
        email: "oscar@agiledigital.com.ph",
        password: dev_password,
        password_confirmation: dev_password,
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
