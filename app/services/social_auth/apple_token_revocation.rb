module SocialAuth
  # Revokes the Apple refresh token of a user. A failure never blocks the caller.
  class AppleTokenRevocation
    def initialize(apple_token_client: AppleTokenClient.new)
      @apple_token_client = apple_token_client
    end

    def call(user)
      identity = user.user_identities.apple.first
      refresh_token = identity&.apple_refresh_token
      @apple_token_client.revoke(refresh_token) if refresh_token.present?
    rescue AppleTokenClient::Error, ActiveRecord::Encryption::Errors::Base => e
      Rails.logger.warn("[apple_revocation] Revoke skipped: #{e.class}")
    end
  end
end
