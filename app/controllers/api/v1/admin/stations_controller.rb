module Api
  module V1
    module Admin
      class StationsController < BaseController
        before_action :require_admin!
        before_action :set_station

        # PATCH /api/v1/admin/stations/:id
        def update
          if @station.update(station_params)
            Rails.cache.delete_matched("stations*")
            render json: { data: @station.as_api_json }, status: :ok
          else
            render json: { error: "Update failed", errors: @station.errors.full_messages },
                   status: :unprocessable_entity
          end
        end

        private

        def set_station
          @station = Station.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Station not found" }, status: :not_found
        end

        def station_params
          params.require(:station).permit(:lat, :lng)
        end
      end
    end
  end
end
