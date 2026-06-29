module Api
  module V1
    class RoutesController < BaseController
      skip_before_action :authenticate_user!

      # GET /api/v1/routes
      # Returns one entry per line with stop count and fare info
      def index
        routes = Rails.cache.fetch("routes_index", expires_in: 30.minutes) do
          Edge.select(:line, :mode, :base_fare, :accepted_payments, :is_air_conditioned,
                      :open_time, :close_time, :crowd_factor, :reliability)
              .group(:line, :mode, :base_fare, :accepted_payments, :is_air_conditioned,
                     :open_time, :close_time, :crowd_factor, :reliability)
              .map do |e|
            stop_count = Station.where(line: e.line).count
            {
              line_id: e.line,
              mode: e.mode,
              base_fare: e.base_fare,
              accepted_payments: e.accepted_payments,
              is_air_conditioned: e.is_air_conditioned,
              open_time: e.open_time,
              close_time: e.close_time,
              crowd_factor: e.crowd_factor,
              reliability: e.reliability,
              stop_count: stop_count
            }
          end
        end

        scope = routes
        scope = scope.select { |r| r[:mode] == params[:mode] } if params[:mode].present?
        scope = scope.select { |r| r[:line_id].include?(params[:search].upcase) } if params[:search].present?

        json_response(scope, meta: { count: scope.size })
      end

      # GET /api/v1/routes/:line_id
      def show
        line_id  = params[:line_id]
        stations = Station.where(line: line_id).order(:name)
        edges    = Edge.where(line: line_id).order(:id)

        return render json: { error: "Route not found" }, status: :not_found if stations.empty?

        first_edge = edges.first
        json_response({
                        line_id: line_id,
                        mode: first_edge&.mode,
                        base_fare: first_edge&.base_fare,
                        accepted_payments: first_edge&.accepted_payments,
                        is_air_conditioned: first_edge&.is_air_conditioned,
                        open_time: first_edge&.open_time,
                        close_time: first_edge&.close_time,
                        crowd_factor: first_edge&.crowd_factor,
                        reliability: first_edge&.reliability,
                        stations: stations.map(&:as_api_json),
                        edges: edges.map(&:as_api_json)
                      })
      end
    end
  end
end
