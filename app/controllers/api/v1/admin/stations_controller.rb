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
            Rails.cache.delete("full_graph")
            Rails.cache.delete("graph_version")
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
          raw = params.require(:station).permit(
            :lat, :lng, :latitude, :longitude,
            :name, :short_name, :open_time, :close_time
          )
          result = {}
          if raw[:latitude].present? || raw[:lat].present?
            result[:lat] = (raw[:latitude] || raw[:lat]).to_f
            result[:lng] = (raw[:longitude] || raw[:lng]).to_f
          end
          result[:name]       = raw[:name].strip       if raw[:name].present?
          result[:short_name] = raw[:short_name].strip if raw[:short_name].present?
          result[:open_time]  = raw[:open_time].strip  if raw[:open_time].present?
          result[:close_time] = raw[:close_time].strip if raw[:close_time].present?
          result
        end
      end
    end
  end
end
