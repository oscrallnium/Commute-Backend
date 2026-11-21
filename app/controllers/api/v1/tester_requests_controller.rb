module Api
  module V1
    # Receives the website tester form from the Cloudflare Pages Function. The answer never
    # tells the caller whether the email is already on the list.
    class TesterRequestsController < BaseController
      FORM_KEY_HEADER = "X-Gora-Form-Key".freeze
      PERMITTED = %i[name age location email consent_at source].freeze

      skip_before_action :authenticate_user!
      before_action :require_form_key!

      # POST /api/v1/tester_requests
      def create
        tester_request = TesterRequest.submit(tester_request_params)
        if tester_request.errors.any?
          render json: { error: "Invalid request", errors: field_errors(tester_request) },
                 status: :unprocessable_content
        else
          render json: { status: "received" }, status: :accepted
        end
      end

      private

      # An unset TESTER_FORM_KEY refuses every request.
      def require_form_key!
        expected = ENV["TESTER_FORM_KEY"].to_s
        provided = request.headers[FORM_KEY_HEADER].to_s
        return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def tester_request_params
        attributes = params.permit(*PERMITTED, :consentAt).to_h.symbolize_keys
        camel_consent_at = attributes.delete(:consentAt)
        attributes[:consent_at] ||= camel_consent_at
        attributes.delete(:source) if attributes[:source].blank?
        attributes
      end

      def field_errors(record)
        record.errors.to_hash.transform_keys { |key| key.to_s.camelize(:lower) }
      end
    end
  end
end
