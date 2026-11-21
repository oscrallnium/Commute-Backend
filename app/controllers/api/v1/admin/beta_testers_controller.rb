module Api
  module V1
    module Admin
      # Lists and removes the testers in the external TestFlight group (ASC_BETA_GROUP_ID).
      # App Store Connect holds this list. The server keeps no copy.
      class BetaTestersController < BaseController
        before_action :require_admin!

        rescue_from AppStoreConnect::Client::ConfigurationError do |e|
          render json: { error: "App Store Connect is not configured", message: e.message }, status: :service_unavailable
        end

        rescue_from AppStoreConnect::Client::TransientError do |e|
          render json: { error: "App Store Connect is unavailable", message: e.message }, status: :service_unavailable
        end

        rescue_from AppStoreConnect::Client::Error do |e|
          render json: { error: "App Store Connect refused the request", message: e.message }, status: :bad_gateway
        end

        # GET /api/v1/admin/beta_testers
        def index
          testers = client.list_group_testers
          json_response(testers.map { |tester| as_api_json(tester, request_ids(testers)) })
        end

        # DELETE /api/v1/admin/beta_testers/:id
        # Tester requests that point to this tester do not change.
        def destroy
          client.remove_tester_from_group(tester_id: params[:id])
          head :no_content
        end

        private

        def client
          AppStoreConnect::Client.new
        end

        # Maps an App Store Connect tester ID or a lowercase email to a tester request ID.
        def request_ids(testers)
          @request_ids ||= begin
            ids = testers.pluck(:id)
            emails = testers.filter_map { |tester| tester[:email]&.downcase }
            TesterRequest.where(asc_beta_tester_id: ids).or(TesterRequest.where(email: emails))
                         .pluck(:id, :asc_beta_tester_id, :email)
                         .each_with_object({}) do |(id, tester_id, email), map|
                           map[tester_id] = id if tester_id
                           map[email] ||= id
                         end
          end
        end

        def as_api_json(tester, ids)
          {
            id: tester[:id], email: tester[:email], firstName: tester[:first_name], lastName: tester[:last_name],
            inviteType: tester[:invite_type], state: tester[:state],
            testerRequestId: ids[tester[:id]] || ids[tester[:email]&.downcase]
          }
        end
      end
    end
  end
end
