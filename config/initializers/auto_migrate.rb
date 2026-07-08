if Rails.env.production?
  begin
    ActiveRecord::Migration.check_all_pending!
  rescue ActiveRecord::PendingMigrationError
    Rails.logger.info "[auto_migrate] Pending migrations detected — running..."
    ActiveRecord::Tasks::DatabaseTasks.migrate
    ActiveRecord::Base.clear_cache!
    Rails.logger.info "[auto_migrate] Migrations complete"
  end
end
