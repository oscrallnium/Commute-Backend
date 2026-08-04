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
          # NOTE: `request.parsed_body` is NOT a real ActionDispatch::Request method in a
          # live controller — see the identical note in GraphController#create_route.
          result = GraphService.insert_stop(params.to_unsafe_h)
          if result.success?
            bust_graph_cache!(extra_pattern: "stations*")
            render json: { data: result.data }, status: :created
          else
            render json: { error: "Validation failed", errors: result.errors.map { |e| e[:message] } },
                   status: :unprocessable_content
          end
        end

        # PATCH /api/v1/admin/stations/:id
        #
        # `access_points`, when present, replaces the station's whole set — the client
        # sends every door it wants to survive, and anything absent is deleted. Wholesale
        # rather than per-row because the admin editor works on the list as a unit: one
        # round trip, one transaction, and no way to leave the set half-applied. It also
        # means "remove a door" needs no separate endpoint.
        #
        # Omitting the key entirely leaves the doors untouched, so an ordinary rename or
        # a nudge to the centroid does not have to resend them.
        def update
          ok = ActiveRecord::Base.transaction do
            @station.update!(station_params)
            replace_access_points! if params[:station]&.key?(:access_points)
            true
          rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
            @error = e
            raise ActiveRecord::Rollback
          end

          if ok
            bust_graph_cache!(extra_pattern: "stations*")
            render json: { data: @station.reload.as_api_json }, status: :ok
          else
            messages = @station.errors.full_messages
            messages = [@error&.message].compact if messages.empty?
            render json: { error: "Update failed", errors: messages },
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

        # Replaces the station's doors with exactly what was sent.
        #
        # delete_all before insert, inside the caller's transaction: ids are client-chosen
        # and a door can be renamed or re-pointed, so diffing by id would still have to
        # handle every case this does in one step. The unique-id collision that a naive
        # "insert then delete" would hit cannot arise.
        def replace_access_points!
          incoming = params[:station][:access_points] || []
          @station.access_points.delete_all

          incoming.each_with_index do |raw, index|
            ap = raw.permit(:id, :access_point_id, :name, :kind, :direction,
                            :lat, :lng, :position, coordinates: %i[lat lng])
            coords = ap[:coordinates] || {}
            lat = ap[:lat] || coords[:lat]
            lng = ap[:lng] || coords[:lng]
            direction = ap[:direction].presence # "" from a form means "serves both"

            StationAccessPoint.create!(
              access_point_id: (ap[:access_point_id] || ap[:id]).presence ||
                               "#{@station.station_id}_AP_#{SecureRandom.hex(4).upcase}",
              station_id: @station.station_id,
              name: ap[:name].to_s.strip,
              kind: ap[:kind].presence || "both",
              direction: direction,
              lat: lat, lng: lng,
              position: ap[:position].presence || index
            )
          end
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
