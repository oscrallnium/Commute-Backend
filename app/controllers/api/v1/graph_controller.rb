module Api
  module V1
    class GraphController < BaseController
      skip_before_action :authenticate_user!

      # GET /api/v1/graph/version
      # Lightweight poll — iOS checks this before fetching the full graph.
      def version
        data = Rails.cache.fetch("graph_version", expires_in: 30.seconds) do
          GraphService.graph_version
        end
        json_response(data)
      rescue => e
        render json: { error: "Graph unavailable", message: e.message }, status: :service_unavailable
      end

      # GET /api/v1/graph
      # Full transit graph JSON — same shape as transit_graph_v3.json.
      # iOS should poll /graph/version first and only fetch this when version changes.
      def show
        graph = Rails.cache.fetch("full_graph", expires_in: 5.minutes) do
          GraphService.assemble_graph
        end
        json_response(graph)
      rescue => e
        render json: { error: "Graph unavailable", message: e.message }, status: :service_unavailable
      end
    end
  end
end
