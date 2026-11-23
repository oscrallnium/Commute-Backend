# Development and test use fixed placeholder keys. Other environments read ENV only.
# A missing key stays unset so that the app boots; encrypted columns then raise on use.
placeholder = Rails.env.local?

Rails.application.configure do
  encryption = config.active_record.encryption
  encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") do
    "dev-only-primary-key-not-secret" if placeholder
  end
  encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") do
    "dev-only-deterministic-key-not-secret" if placeholder
  end
  encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") do
    "dev-only-key-derivation-salt-not-secret" if placeholder
  end
end
