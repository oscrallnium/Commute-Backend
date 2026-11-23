module Api
  module V1
    module Auth
      class SocialSessionsController < BaseController
        SIGN_IN_KEYS = %i[provider id_token nonce authorization_code full_name].freeze

        skip_before_action :authenticate_user!

        # POST /api/v1/auth/social
        def create
          user = SocialSignInService.new.call(**sign_in_params)
          json_response(token: issue_token(user), user: user_payload(user))
        rescue SocialAuth::InvalidTokenError
          render json: { error: "Invalid token" }, status: :unauthorized
        rescue SocialSignInService::UnsupportedProviderError => e
          render_sign_in_failed([e.message])
        rescue ActiveRecord::RecordInvalid => e
          render_sign_in_failed(e.record.errors.full_messages)
        end

        private

        # Every key is present and each value is a String or nil, so a missing or
        # non-string param fails the token check instead of raising.
        def sign_in_params
          SIGN_IN_KEYS.index_with { |key| params[key].is_a?(String) ? params[key] : nil }
        end

        def issue_token(user)
          Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
        end

        def user_payload(user)
          { id: user.id, email: user.email, display_name: user.display_name, role: user.role }
        end

        def render_sign_in_failed(messages)
          render json: { error: "Sign-in failed", errors: messages }, status: :unprocessable_content
        end
      end
    end
  end
end
