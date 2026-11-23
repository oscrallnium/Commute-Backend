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
    # The iOS app refreshes the token on each cold launch, so an active user stays signed in.
    jwt.expiration_time = 90.days.to_i
  end
end
