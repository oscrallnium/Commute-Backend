source "https://rubygems.org"
ruby "~> 3.4"

gem "pg", "~> 1.1"
gem "puma", "~> 6.0"
gem "rack-cors"
gem "rails", "~> 7.1"

# Auth
gem "bcrypt", "~> 3.1.7"
gem "devise"
gem "devise-jwt"

# Serialization
gem "jsonapi-serializer"

# File uploads (Active Storage → Supabase S3-compat)
gem "active_storage_validations"
gem "aws-sdk-s3", require: false

# Pagination
gem "pagy", "~> 6.0"

# Background jobs + cache
gem "sidekiq", "~> 7.0"
gem "redis", "~> 5.0"
gem "connection_pool", "< 3.0"

# Rate limiting
gem "rack-attack"

# Env
gem "dotenv-rails", groups: %i[development test]

group :development, :test do
  gem "factory_bot_rails"
  gem "faker"
  gem "rspec-rails"
  gem "rubocop-rails", require: false
end

group :production do
  gem "rails_12factor" rescue nil # rubocop:disable Style/RescueModifier
end
