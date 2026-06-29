module Api
  module V1
    class BaseController < ApplicationController
      include Devise::JWT::RevocationStrategies::JTIMatcher

      before_action :authenticate_user!

      respond_to :json

      private

      def current_user
        @current_user ||= super
      end

      def require_admin!
        return if current_user&.admin?

        render json: { error: "Forbidden", message: "Admin access required" }, status: :forbidden
      end

      def json_response(data, status: :ok, meta: {})
        payload = { data: data }
        payload[:meta] = meta if meta.present?
        render json: payload, status: status
      end

      def error_response(message, status: :unprocessable_entity, errors: [])
        payload = { error: message }
        payload[:errors] = errors if errors.present?
        render json: payload, status: status
      end
    end
  end
end
