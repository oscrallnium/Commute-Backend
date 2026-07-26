module Api
  module V1
    module Admin
      class StationsController < BaseController
        before_action :require_admin!
        before_action :set_station, only: %i[update destroy]

        # POST /api/v1/admin/stations
        # Inserts a new stop immediately before/after an existing station on the
        # same line. See GraphService#insert_stop for the supported scope.
        def create
          result = GraphService.insert_stop(request.parsed_body || params.to_unsafe_h)
          if result.success?
            bust_graph_cache!(extra_pattern: "stations*")
            render json: { data: result.data }, status: :created
          else
            render json: { error: "Validation failed", errors: result.errors.map { |e| e[:message] } },
                   status: :unprocessable_content
          end
        end

        # PATCH /api/v1/admin/stations/:id
        def update
          if @station.update(station_params)
            bust_graph_cache!(extra_pattern: "stations*")
            render json: { data: @station.as_api_json }, status: :ok
          else
            render json: { error: "Update failed", errors: @station.errors.full_messages },
                   status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/admin/stations/:id
        # Removes a stop, merging its two adjacent edges (or dropping the one
        # adjacent edge if it was a terminal). See GraphService#remove_stop.
        def destroy
          result = GraphService.remove_stop(@station.station_id)
          if result.success?
            bust_graph_cache!(extra_pattern: "stations*")
            render json: { data: result.data }, status: :ok
          else
            render json: { error: "Delete failed", errors: result.errors.map { |e| e[:message] } },
                   status: :unprocessable_content
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
