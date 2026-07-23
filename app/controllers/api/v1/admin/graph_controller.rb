module Api
  module V1
    module Admin
      class GraphController < BaseController
        before_action :require_admin!

        # POST /api/v1/admin/graph/routes
        # Adds a new route to the transit graph.
        # Body matches the Hono RoutePayload shape exactly — web admin needs no changes.
        def create_route
          result = GraphService.add_route(request.parsed_body || params.to_unsafe_h)

          if result.success?
            # Bust graph cache so next iOS poll gets fresh data
            Rails.cache.delete("full_graph")
            Rails.cache.delete("graph_version")
            render json: { data: result.data }, status: :created
          else
            # Flatten {field:, message:} structs to plain strings — every other endpoint's
            # `errors` array is `model.errors.full_messages` (an array of strings), and the
            # client's ErrorResponse decoder expects that shape.
            render json: { error: "Validation failed", errors: result.errors.map { |e| e[:message] } },
                   status: :unprocessable_content
          end
        end

        # DELETE /api/v1/admin/graph/routes/:line_id
        # Removes a route and all its stations/edges from the graph.
        def delete_route
          result = GraphService.delete_route(params[:line_id])

          if result.success?
            Rails.cache.delete("full_graph")
            Rails.cache.delete("graph_version")
            render json: { data: result.data }, status: :ok
          else
            render json: { error: "Delete failed", errors: result.errors.map { |e| e[:message] } },
                   status: :unprocessable_content
          end
        end
      end
    end
  end
end
