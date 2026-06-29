require "devise/orm/active_record"

Devise.setup do |config|
  config.mailer_sender = "noreply@commutebeh.ph"
  config.navigational_formats = []

  config.jwt do |jwt|
    jwt.secret = ENV.fetch("DEVISE_JWT_SECRET_KEY")
    jwt.dispatch_requests = [
      ["POST", %r{^/auth/sign_in$}],
      ["POST", %r{^/auth/register$}]
    ]
    jwt.revocation_requests = [
      ["DELETE", %r{^/auth/sign_out$}]
    ]
    jwt.expiration_time = 24.hours.to_i
  end
end
