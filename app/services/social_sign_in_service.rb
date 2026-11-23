# Signs a user in with a Google or Apple ID token and returns the User.
# An unverified email never links an identity to an existing user.
class SocialSignInService
  class UnsupportedProviderError < StandardError; end

  MAX_DISPLAY_NAME_LENGTH = 60
  DEFAULT_DISPLAY_NAME = "Commuter".freeze

  def initialize(apple_verifier: SocialAuth::AppleTokenVerifier.new,
                 google_verifier: SocialAuth::GoogleTokenVerifier.new,
                 apple_token_client: SocialAuth::AppleTokenClient.new)
    @verifiers = { "apple" => apple_verifier, "google" => google_verifier }
    @apple_token_client = apple_token_client
  end

  def call(provider:, id_token:, nonce: nil, authorization_code: nil, full_name: nil)
    provider = provider.to_s
    claims = verify(provider, id_token, nonce)
    identity = resolve_identity(provider, claims, full_name)
    store_apple_refresh_token(identity, authorization_code) if identity.apple?
    identity.user
  end

  private

  def verify(provider, id_token, nonce)
    verifier = @verifiers[provider] || raise(UnsupportedProviderError, "Unsupported provider")
    provider == "apple" ? verifier.verify(id_token, nonce: nonce) : verifier.verify(id_token)
  end

  def resolve_identity(provider, claims, full_name)
    attempts = 0
    begin
      UserIdentity.transaction { find_or_create_identity(provider, claims, full_name) }
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts < 2
      raise
    end
  end

  def find_or_create_identity(provider, claims, full_name)
    identity = UserIdentity.find_by(provider: provider, uid: claims[:uid])
    return refresh_identity_email(identity, claims[:email]) if identity

    user = find_linkable_user(claims)
    return user.user_identities.create!(identity_attributes(provider, claims)) if user

    create_user_with_identity(provider, claims, full_name)
  end

  def refresh_identity_email(identity, email)
    identity.update!(email: email) if email.present? && email != identity.email
    identity
  end

  def find_linkable_user(claims)
    return unless claims[:email_verified] && claims[:email].present?

    User.find_by("lower(email) = ?", claims[:email].downcase)
  end

  def create_user_with_identity(provider, claims, full_name)
    user = User.new(email: claims[:email].presence, role: :commuter,
                    display_name: display_name_for(full_name, claims))
    identity = user.user_identities.build(identity_attributes(provider, claims))
    user.save!
    identity
  end

  def identity_attributes(provider, claims)
    { provider: provider, uid: claims[:uid], email: claims[:email].presence }
  end

  def display_name_for(full_name, claims)
    name = [full_name, claims[:name], claims[:email].to_s.split("@").first]
           .map { |candidate| candidate.to_s.strip }
           .find(&:present?)
    (name || DEFAULT_DISPLAY_NAME).first(MAX_DISPLAY_NAME_LENGTH)
  end

  # Runs after the transaction commits. A failure never blocks sign-in.
  def store_apple_refresh_token(identity, authorization_code)
    return if authorization_code.blank? || identity.apple_refresh_token.present?

    identity.update!(apple_refresh_token: @apple_token_client.exchange_code(authorization_code))
  rescue SocialAuth::AppleTokenClient::Error, ActiveRecord::Encryption::Errors::Base => e
    Rails.logger.warn("[social_sign_in] Apple token exchange skipped: #{e.class}")
  end
end
