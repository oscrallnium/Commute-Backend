module Api
  module V1
    module Admin
      class SettingsController < BaseController
        before_action :require_admin!

        # GET /api/v1/admin/settings
        def show
          meta = GraphMeta.first!
          render json: { data: settings_json(meta) }
        end

        # PATCH /api/v1/admin/settings
        def update
          meta = GraphMeta.first!

          if params.key?(:enforce_operating_hours)
            meta.update!(enforce_operating_hours: params[:enforce_operating_hours])
            Rails.cache.delete("full_graph")
            Rails.cache.delete("graph_version")
          end

          render json: { data: settings_json(meta) }
        end

        private

        def settings_json(meta)
          { enforce_operating_hours: meta.enforce_operating_hours }
        end
      end
    end
  end
end
