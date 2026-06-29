module Api
  module V1
    class AnalyticsController < BaseController
      # POST /api/v1/analytics/route_plan
      # iOS calls this after a successful A* run
      # Body: { origin_id, destination_id, legs, total_time_minutes, modes_used }
      def route_plan
        RoutePlanEvent.create!(
          user_id:             current_user.id,
          origin_station_id:   params[:origin_id],
          destination_station_id: params[:destination_id],
          legs:                params[:legs] || [],
          total_time_minutes:  params[:total_time_minutes],
          modes_used:          params[:modes_used] || [],
          occurred_at:         Time.current
        )
        render json: { message: "Logged" }, status: :created
      rescue => e
        # Never block the user's commute over an analytics failure
        Rails.logger.warn("[analytics] Failed to log route plan: #{e.message}")
        render json: { message: "Logged" }, status: :created
      end
    end
  end
end
