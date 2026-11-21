require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module CommutebehApi
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.active_storage.service = :local

    config.active_job.queue_adapter = :sidekiq

    # config/routes.rb mounts Action Cable. Clients send a JWT, not a cookie, so the
    # Origin check adds no protection, and the macOS client sends no Origin header.
    config.action_cable.mount_path = nil
    config.action_cable.disable_request_forgery_protection = true

    config.middleware.use ActionDispatch::Flash

    # Default timezone: Manila
    config.time_zone = "Asia/Manila"
    config.active_record.default_timezone = :utc
  end
end
