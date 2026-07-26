module Api
  module V1
    module Admin
      class EdgesController < BaseController
        before_action :require_admin!
        before_action :set_edge

        # PATCH /api/v1/admin/edges/:id
        def update
          attrs = edge_params
          # Trust the server's own math over whatever the client computed, same as
          # everywhere else in GraphService. Never touches travel_time_minutes — the
          # generic AVG_SPEED_KMH=24 road-traffic constant would badly misstate a
          # train's real (scheduled, dwell-time-inclusive) travel time.
          if attrs[:polyline_coordinates]
            recomputed = GraphService.polyline_distance_km(attrs[:polyline_coordinates])
            attrs[:distance_km] = recomputed if recomputed
          end

          if @edge.update(attrs)
            GraphService.bump_version!
            Rails.cache.delete("full_graph")
            Rails.cache.delete("graph_version")
            render json: { data: @edge.as_api_json }, status: :ok
          else
            render json: { error: "Update failed", errors: @edge.errors.full_messages },
                   status: :unprocessable_entity
          end
        end

        private

        def set_edge
          @edge = Edge.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Edge not found" }, status: :not_found
        end

        def edge_params
          permitted = params.require(:edge).permit(polyline_coordinates: [:lat, :lng])
          return {} unless permitted[:polyline_coordinates].present?
          {
            polyline_coordinates: permitted[:polyline_coordinates].map do |c|
              { "lat" => c[:lat].to_f, "lng" => c[:lng].to_f }
            end
          }
        end
      end
    end
  end
end
