if Rails.env.production?
  begin
    ActiveRecord::Migration.check_all_pending!
  rescue ActiveRecord::PendingMigrationError
    Rails.logger.info "[auto_migrate] Pending migrations found — running db:migrate"
    ActiveRecord::MigrationContext.new(
      ActiveRecord::Migrator.migrations_paths,
      ActiveRecord::SchemaMigration
    ).migrate
    Rails.logger.info "[auto_migrate] Migrations complete"
  end
end
