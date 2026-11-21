# Keeps secrets and tester-form fields out of the logs. `token` also hides the admin JWT in
# the `/cable?token=` query string. The anchored patterns match only those exact keys.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp,
  /\Aname\z/, /\Aage\z/, /\Alocation\z/, /\Aconsent_?at\z/i
]
