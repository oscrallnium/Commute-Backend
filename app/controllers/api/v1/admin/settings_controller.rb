module Api
  module V1
    module Admin
      class SettingsController < BaseController
        before_action :require_admin!

        # GET /api/v1/admin/settings
        def show
          meta = graph_meta
          render json: { data: settings_json(meta) }
        end

        # PATCH /api/v1/admin/settings
        def update
          meta = graph_meta

          if params.key?(:enforce_operating_hours)
            value = ActiveModel::Type::Boolean.new.cast(params[:enforce_operating_hours])
            meta.update!(enforce_operating_hours: value)
            bust_graph_cache
          end

          render json: { data: settings_json(meta) }
        end

        private

        def graph_meta
          GraphMeta.first_or_create!(
            version: 1,
            last_modified: Time.current,
            schema_version: "3.0.0",
            region: "Metro Manila, Philippines",
            currency: "PHP",
            enforce_operating_hours: true
          )
        end

        def settings_json(meta)
          { enforce_operating_hours: meta.enforce_operating_hours }
        end

        def bust_graph_cache
          Rails.cache.delete("full_graph")
          Rails.cache.delete("graph_version")
        rescue => e
          Rails.logger.warn("[settings] Cache bust failed: #{e.message}")
        end
      end
    end
  end
end
