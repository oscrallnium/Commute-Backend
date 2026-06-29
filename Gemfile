source "https://rubygems.org"
ruby "3.4.1"

gem "rails", "~> 7.1"
gem "pg", "~> 1.1"
gem "puma", "~> 6.0"
gem "rack-cors"

# Auth
gem "devise"
gem "devise-jwt"
gem "bcrypt", "~> 3.1.7"

# Serialization
gem "jsonapi-serializer"

# File uploads (Active Storage → Supabase S3-compat)
gem "aws-sdk-s3", require: false
gem "active_storage_validations"

# Pagination
gem "pagy", "~> 6.0"

# Background jobs
gem "sidekiq", "~> 7.0"

# Rate limiting
gem "rack-attack"

# Env
gem "dotenv-rails", groups: %i[development test]

group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "rubocop-rails", require: false
end

group :production do
  gem "rails_12factor" rescue nil  # Railway log streaming
end
