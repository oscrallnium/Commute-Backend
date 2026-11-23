module SocialAuth
  # Applies a verified Apple server notification to the matching Apple identity.
  class AppleNotificationHandler
    ACTIONS = {
      "consent-revoked" => :revoke_consent,
      "account-delete" => :delete_account,
      "email-disabled" => :disable_email_relay,
      "email-enabled" => :enable_email_relay
    }.freeze

    def initialize(verifier: AppleTokenVerifier.new)
      @verifier = verifier
    end

    def call(payload)
      event = @verifier.verify_notification(payload)
      action = ACTIONS[event["type"]]
      identity = UserIdentity.apple.find_by(uid: event["sub"].to_s)
      return if action.nil? || identity.nil?

      send(action, identity)
    end

    private

    def revoke_consent(identity)
      identity.update!(apple_refresh_token: nil)
      identity.user.update_column(:jti, SecureRandom.uuid)
    end

    # The row lock on the user makes a repeated event wait, then find nothing to delete.
    def delete_account(identity)
      user = identity.user
      user.with_lock do
        current = user.user_identities.apple.find_by(id: identity.id)
        next if current.nil?

        apple_only_sign_in?(user) ? user.destroy! : current.destroy!
      end
    end

    def apple_only_sign_in?(user)
      !user.password_set? && !user.user_identities.where.not(provider: :apple).exists?
    end

    def disable_email_relay(identity)
      identity.update!(email_relay_enabled: false)
    end

    def enable_email_relay(identity)
      identity.update!(email_relay_enabled: true)
    end
  end
end
