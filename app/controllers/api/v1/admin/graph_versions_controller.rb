module Api
  module V1
    module Admin
      class GraphVersionsController < BaseController
        before_action :require_admin!

        DEFAULT_PER_PAGE = 20
        MAX_PER_PAGE     = 100

        # GET /api/v1/admin/graph/versions?page=1&per_page=20
        # Newest first. Each row leaves out the change list. A page past the end is empty.
        def index
          per_page = params.fetch(:per_page, DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
          page     = [params.fetch(:page, 1).to_i, 1].max
          total    = GraphVersion.count
          rows     = GraphVersion.includes(:published_by).order(version: :desc)
                                 .offset((page - 1) * per_page).limit(per_page)
          json_response(rows.map(&:as_api_json),
                        meta: { current_page: page, total_pages: (total.to_f / per_page).ceil,
                                total_count: total, per_page: per_page })
        end

        # GET /api/v1/admin/graph/versions/:version
        def show
          row = GraphVersion.includes(:published_by).find_by(version: params[:version])
          return render json: { error: "Version not found" }, status: :not_found unless row

          json_response(row.as_api_json(include_changes: true))
        end
      end
    end
  end
end
