module Api
  module V1
    module Admin
      class TesterRequestsController < BaseController
        before_action :require_admin!
        before_action :set_tester_request, except: :index

        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE     = 100

        rescue_from TesterRequest::TransitionError do |e|
          render json: { error: "Conflict", message: e.message }, status: :conflict
        end

        # GET /api/v1/admin/tester_requests?status=&page=&per_page=
        # Newest first. A page past the end is empty.
        def index
          scope = TesterRequest.all
          if params[:status].present?
            unless TesterRequest.statuses.key?(params[:status])
              return render json: { error: "Invalid status", errors: { status: ["is not a known status"] } },
                            status: :unprocessable_content
            end

            scope = scope.where(status: params[:status])
          end
          per_page = params.fetch(:per_page, DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
          page     = [params.fetch(:page, 1).to_i, 1].max
          rows     = scope.order(created_at: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page)
          json_response(rows.map(&:as_api_json), meta: { page: page, perPage: per_page, total: scope.count })
        end

        # POST /api/v1/admin/tester_requests/:id/invite
        def invite
          @tester_request.start_invite!(current_user)
          TesterInviteJob.perform_later(@tester_request.id, "invite")
          json_response(@tester_request.as_api_json, status: :accepted)
        end

        # POST /api/v1/admin/tester_requests/:id/resend
        def resend
          @tester_request.start_resend!(current_user)
          TesterInviteJob.perform_later(@tester_request.id, "resend")
          json_response(@tester_request.as_api_json, status: :accepted)
        end

        # POST /api/v1/admin/tester_requests/:id/decline
        def decline
          @tester_request.decline!
          json_response(@tester_request.as_api_json)
        end

        # DELETE /api/v1/admin/tester_requests/:id
        def destroy
          @tester_request.destroy!
          head :no_content
        end

        private

        def set_tester_request
          @tester_request = TesterRequest.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Tester request not found" }, status: :not_found
        end
      end
    end
  end
end
