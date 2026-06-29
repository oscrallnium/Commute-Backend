module Api
  module V1
    class ArWorldMapsController < BaseController
      MAX_UPLOAD_BYTES = 150.megabytes

      # GET /api/v1/ar_world_maps
      # Supports: ?station_id=MRT_NORTH_AVE &status=approved
      def index
        maps = ArWorldMap.includes(:user)
        maps = maps.where(station_id: params[:station_id]) if params[:station_id].present?
        maps = maps.where(status: params[:status])         if params[:status].present?
        maps = maps.approved unless current_user.admin?    # public sees approved only

        pagy, maps = pagy(maps.order(version: :desc))
        json_response(maps.map(&:as_api_json), meta: paginate_meta(pagy))
      end

      # GET /api/v1/ar_world_maps/:id
      def show
        map = ArWorldMap.find(params[:id])
        map = nil if !current_user.admin? && !map.approved?
        return render json: { error: "Not found" }, status: :not_found unless map

        json_response(map.as_api_json(include_url: true))
      end

      # POST /api/v1/ar_world_maps
      # multipart/form-data: station_id, map_file
      def create
        file = params[:map_file]
        if file.nil?
          return error_response("map_file is required", status: :bad_request)
        end
        if file.size > MAX_UPLOAD_BYTES
          return error_response("File too large (max 150 MB)", status: :payload_too_large)
        end

        map = ArWorldMap.new(
          user:       current_user,
          station_id: params[:station_id],
          status:     "pending",
          version:    next_version(params[:station_id]),
          metadata:   {}
        )
        map.map_file.attach(file)

        if map.save
          json_response(map.as_api_json, status: :created)
        else
          error_response("Upload failed", errors: map.errors.full_messages)
        end
      end

      # POST /api/v1/ar_world_maps/:id/relocalize
      # iOS posts a relocalization event with accuracy metrics
      def relocalize
        map = ArWorldMap.find(params[:id])
        event = {
          timestamp:  Time.current.iso8601,
          accuracy:   params[:accuracy],
          user_id:    current_user.id,
          device:     params[:device]
        }

        # Ring-buffer cap: keep last 100 events
        events = (map.metadata["relocalization_events"] || []).last(99)
        events << event
        map.update_column(:metadata, map.metadata.merge("relocalization_events" => events))

        render json: { message: "Logged", event_count: events.size }, status: :ok
      end

      private

      def next_version(station_id)
        ArWorldMap.where(station_id: station_id).maximum(:version).to_i + 1
      end
    end
  end
end
