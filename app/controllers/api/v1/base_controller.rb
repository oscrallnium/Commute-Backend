module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_user!

      respond_to :json

      private

      def current_user
        @current_user ||= super
      end

      def require_admin!
        return if current_user&.admin?

        render json: { error: "Forbidden", message: "Admin access required" }, status: :forbidden
      end

      def json_response(data, status: :ok, meta: {})
        payload = { data: data }
        payload[:meta] = meta if meta.present?
        render json: payload, status: status
      end

      def error_response(message, status: :unprocessable_entity, errors: [])
        payload = { error: message }
        payload[:errors] = errors if errors.present?
        render json: payload, status: status
      end

      # Cache invalidation is best-effort — never let a Redis blip (e.g. REDIS_URL
      # unset/unreachable in production) turn an already-successful database write
      # into a failed response for the client. This was discovered as a live bug:
      # every admin write endpoint called Rails.cache.delete directly, unprotected,
      # *after* the DB transaction had already committed — so a cache-store hiccup
      # surfaced as a raw 500 to the client even though the write had actually
      # succeeded. Worst case with this rescue in place: the next graph poll serves
      # briefly stale cache until the existing TTL (5 min full_graph / 30s
      # graph_version) expires naturally — much better than a false failure.
      def bust_graph_cache!(extra_pattern: nil)
        Rails.cache.delete_matched(extra_pattern) if extra_pattern
        Rails.cache.delete("full_graph")
        Rails.cache.delete("graph_version")
      rescue => e
        Rails.logger.error("[cache] bust_graph_cache! failed: #{e.class}: #{e.message}")
      end
    end
  end
end
