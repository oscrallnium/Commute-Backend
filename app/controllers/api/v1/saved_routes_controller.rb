module Api
  module V1
    class SavedRoutesController < BaseController
      before_action :set_saved_route, only: [:destroy]

      # GET /api/v1/saved_routes
      def index
        saved = current_user.saved_routes.order(created_at: :desc)
        json_response(saved.map(&:as_api_json))
      end

      # POST /api/v1/saved_routes
      # Body: { saved_route: { name, origin_station_id, destination_station_id, legs } }
      def create
        saved = current_user.saved_routes.build(saved_route_params)
        if saved.save
          json_response(saved.as_api_json, status: :created)
        else
          error_response("Could not save route", errors: saved.errors.full_messages)
        end
      end

      # DELETE /api/v1/saved_routes/:id
      def destroy
        @saved_route.destroy!
        render json: { message: "Saved route deleted" }, status: :ok
      end

      private

      def set_saved_route
        @saved_route = current_user.saved_routes.find(params[:id])
      end

      def saved_route_params
        params.require(:saved_route).permit(
          :name, :origin_station_id, :destination_station_id,
          legs: %i[line_id mode from_station to_station travel_time_minutes]
        )
      end
    end
  end
end
