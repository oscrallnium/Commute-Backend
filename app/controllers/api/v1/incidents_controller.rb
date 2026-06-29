module Api
  module V1
    class IncidentsController < BaseController
      # GET /api/v1/incidents
      def index
        incidents = Incident.active.includes(:station).order(created_at: :desc).limit(50)
        json_response(incidents.map(&:as_api_json))
      end

      # POST /api/v1/incidents
      def create
        incident = Incident.new(incident_params.merge(reported_by: current_user.id))
        if incident.save
          json_response(incident.as_api_json, status: :created)
        else
          error_response("Could not report incident", errors: incident.errors.full_messages)
        end
      end

      private

      def incident_params
        params.require(:incident).permit(:station_id, :line_id, :category, :description)
      end
    end
  end
end
