require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module CommutebehApi
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.active_storage.service = :local

    config.active_job.queue_adapter = :sidekiq

    config.middleware.use ActionDispatch::Flash

    # Default timezone: Manila
    config.time_zone = "Asia/Manila"
    config.active_record.default_timezone = :utc
  end
end
