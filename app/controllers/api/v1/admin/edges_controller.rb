module Api
  module V1
    module Admin
      class EdgesController < BaseController
        before_action :require_admin!
        before_action :set_edge

        # PATCH /api/v1/admin/edges/:id
        def update
          attrs = edge_params

          if attrs.empty?
            return render json: { error: "Nothing to update",
                                  errors: ["Send polyline_coordinates, bidirectional, or direction."] },
                          status: :unprocessable_content
          end

          # Mirrors the rule add_route enforces on a pass: a bidirectional edge gets a
          # synthetic reverse on the client carrying the *flipped* direction label, so the
          # pair would claim this edge serves both directions of travel at once.
          effective_bidirectional = attrs.key?(:bidirectional) ? attrs[:bidirectional] : @edge.bidirectional
          effective_direction     = attrs.key?(:direction) ? attrs[:direction] : @edge.direction
          if effective_bidirectional && effective_direction.present?
            return render json: { error: "Update failed",
                                  errors: ["A direction-tagged edge can't be bidirectional."] },
                          status: :unprocessable_content
          end
          # Trust the server's own math over whatever the client computed, same as
          # everywhere else in GraphService. Never touches travel_time_minutes — the
          # generic AVG_SPEED_KMH=24 road-traffic constant would badly misstate a
          # train's real (scheduled, dwell-time-inclusive) travel time.
          if attrs[:polyline_coordinates]
            recomputed = GraphService.polyline_distance_km(attrs[:polyline_coordinates])
            attrs[:distance_km] = recomputed if recomputed
            # A hand-placed/GPS-corrected polyline via this precise map tool is
            # deliberate, trusted geometry — Explore should show it as-is rather
            # than silently discarding it for a fresh MKDirections guess.
            attrs[:is_road_snapped] = true
          end

          if @edge.update(attrs)
            GraphService.bump_version!
            bust_graph_cache!
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

        # Directionality is editable here because nothing else can change it after a route
        # is created. Insert/remove now inherit it correctly, but routes edited before that
        # fix still carry two-way segments in the middle of one-way chains, and a route
        # saved with the wrong setting had no remedy short of deleting and re-recording it.
        #
        # Each field is optional and applied independently — sending only `bidirectional`
        # leaves the polyline untouched, and vice versa.
        def edge_params
          permitted = params.require(:edge).permit(:bidirectional, :direction,
                                                   polyline_coordinates: [:lat, :lng])
          attrs = {}

          if permitted[:polyline_coordinates].present?
            attrs[:polyline_coordinates] = permitted[:polyline_coordinates].map do |c|
              { "lat" => c[:lat].to_f, "lng" => c[:lng].to_f }
            end
          end

          unless permitted[:bidirectional].nil?
            attrs[:bidirectional] = ActiveModel::Type::Boolean.new.cast(permitted[:bidirectional])
          end

          # `key?` rather than `present?`, so an explicit null can clear the label.
          attrs[:direction] = permitted[:direction].presence if permitted.key?(:direction)

          attrs
        end
      end
    end
  end
end
