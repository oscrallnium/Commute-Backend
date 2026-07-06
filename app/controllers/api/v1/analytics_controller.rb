module Api
  module V1
    class AnalyticsController < BaseController
      # POST /api/v1/analytics/route_plan
      # iOS body: { event: { origin_station_id, destination_station_id, line_ids, duration_seconds } }
      def route_plan
        ev = params[:event] || {}
        duration_secs = ev[:duration_seconds].to_i
        RoutePlanEvent.create!(
          user_id: current_user.id,
          origin_station_id: ev[:origin_station_id],
          destination_station_id: ev[:destination_station_id],
          legs: [],
          total_time_minutes: duration_secs > 0 ? (duration_secs / 60.0).ceil : nil,
          modes_used: Array(ev[:line_ids]),
          occurred_at: Time.current
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
