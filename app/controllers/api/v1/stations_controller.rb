module Api
  module V1
    class StationsController < BaseController
      skip_before_action :authenticate_user!

      # GET /api/v1/stations
      # Supports: ?line=MRT-3 &type=train &search=north &interchange=true
      def index
        stations = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
          scope = Station.all
          scope = scope.where(line: params[:line])         if params[:line].present?
          scope = scope.where(type: params[:type])         if params[:type].present?
          scope = scope.where(is_interchange: true)        if params[:interchange] == "true"
          scope = scope.search(params[:search])            if params[:search].present?
          scope.order(:line, :name).map(&:as_api_json)
        end
        json_response(stations, meta: { count: stations.size })
      end

      # GET /api/v1/stations/:id
      def show
        station = Station.find(params[:id])
        json_response(station.as_api_json)
      end

      private

      def cache_key
        parts = ["stations", params[:line], params[:type], params[:interchange], params[:search]]
        parts.compact.join("/")
      end
    end
  end
end
