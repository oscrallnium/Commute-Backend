module Api
  module V1
    module Admin
      class GraphController < BaseController
        before_action :require_admin!

        # GET /api/v1/admin/graph
        # Every line, stop, and edge, including the ones hidden from riders. Never cached.
        def show
          json_response(GraphService.assemble_admin_graph)
        end

        # POST /api/v1/admin/graph/publish
        # The raw body keeps null cells in the rail fare rows. Rails params can drop them.
        def publish
          body = JSON.parse(request.raw_post.presence || "{}")
          unless body.is_a?(Hash)
            return render json: { error: "Bad request", message: "Send a JSON object." }, status: :bad_request
          end

          result = GraphPublisher.publish(base_version: body["base_version"], changes: body["changes"], user: current_user)
          bust_graph_cache!(extra_pattern: "stations*") if result.status == :created
          render json: result.body, status: result.status
        rescue JSON::ParserError
          render json: { error: "Bad request", message: "The body is not valid JSON." }, status: :bad_request
        end

        # POST /api/v1/admin/graph/routes
        # Adds a new route to the transit graph.
        # Body matches the Hono RoutePayload shape exactly — web admin needs no changes.
        def create_route
          # NOTE: `request.parsed_body` is NOT a real ActionDispatch::Request method in a
          # live controller — it only exists on Rails' test-harness request/response
          # classes (action_controller/test_case.rb etc.), used for asserting on a test
          # *response* body. Calling it here always raised NoMethodError, on every single
          # request, regardless of payload — `params` already has the parsed JSON body.
          result = GraphService.add_route(params.to_unsafe_h)

          if result.success?
            # Bust graph cache so next iOS poll gets fresh data
            bust_graph_cache!
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
            bust_graph_cache!
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
