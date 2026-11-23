module Api
  module V1
    module Auth
      class AppleNotificationsController < BaseController
        skip_before_action :authenticate_user!

        # POST /api/v1/auth/apple/notifications
        # The Apple signature on the payload is the only authentication.
        def create
          payload = params.require(:payload)
          raise SocialAuth::InvalidTokenError, "Payload is not a string" unless payload.is_a?(String)

          SocialAuth::AppleNotificationHandler.new.call(payload)
          render json: {}, status: :ok
        rescue SocialAuth::InvalidTokenError, ActionController::ParameterMissing
          render json: { error: "Invalid payload" }, status: :bad_request
        end
      end
    end
  end
end
