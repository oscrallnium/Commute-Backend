module Api
  module V1
    module Admin
      class AnalyticsController < BaseController
        before_action :require_admin!

        # GET /api/v1/admin/analytics/summary
        def summary
          today = Date.current
          render json: {
            data: {
              dau: RoutePlanEvent.where(occurred_at: today.beginning_of_day..).select(:user_id).distinct.count,
              wau: RoutePlanEvent.where(occurred_at: 7.days.ago..).select(:user_id).distinct.count,
              total_users: User.count,
              route_plans_today: RoutePlanEvent.where(occurred_at: today.beginning_of_day..).count,
              top_origins: top_stations(:origin_station_id),
              top_destinations: top_stations(:destination_station_id),
              mode_share: mode_share
            }
          }
        end

        # GET /api/v1/admin/analytics/hotspots
        def hotspots
          hotspots = RoutePlanEvent.where(occurred_at: 30.days.ago..)
                                   .group(:origin_station_id)
                                   .order(count_all: :desc)
                                   .limit(20)
                                   .count
          render json: { data: hotspots.map { |id, count| { station_id: id, count: count } } }
        end

        private

        def top_stations(col)
          RoutePlanEvent.where(occurred_at: 7.days.ago..)
                        .group(col)
                        .order(count_all: :desc)
                        .limit(5)
                        .count
                        .map { |id, count| { station_id: id, count: count } }
        end

        def mode_share
          RoutePlanEvent.where(occurred_at: 7.days.ago..)
                        .pluck(:modes_used)
                        .flatten
                        .tally
                        .sort_by { |_, v| -v }
                        .to_h
        end
      end
    end
  end
end
