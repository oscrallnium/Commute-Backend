class HealthController < ApplicationController
  def show
    db_ok = begin
      ActiveRecord::Base.connection.execute("SELECT 1").any?
    rescue
      false
    end
    render json: {
      status: db_ok ? "ok" : "degraded",
      db: db_ok ? "connected" : "error",
      env: Rails.env,
      timestamp: Time.current.iso8601
    }, status: db_ok ? :ok : :service_unavailable
  end
end
