# Each example starts with empty throttle counters. The memory store keeps the specs off Redis.
RSpec.configure do |config|
  config.before(:suite) { Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new }
  config.before { Rack::Attack.reset! }
end
