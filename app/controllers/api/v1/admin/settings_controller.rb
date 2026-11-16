module Api
  module V1
    module Admin
      class SettingsController < BaseController
        MAX_WAIT_RANGE = (1..600)

        before_action :require_admin!

        # GET /api/v1/admin/settings
        def show
          meta = graph_meta
          render json: { data: settings_json(meta) }
        end

        # PATCH /api/v1/admin/settings
        def update
          meta = graph_meta
          errors = setting_errors
          return render_validation_errors(errors) if errors.any?

          meta.assign_attributes(setting_changes)
          if meta.changed?
            meta.save!
            GraphService.bump_version!
            bust_graph_cache!
          end

          render json: { data: settings_json(meta.reload) }
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
          { enforce_operating_hours: meta.enforce_operating_hours,
            scheduled_max_wait_minutes: meta.scheduled_max_wait_minutes }
        end

        def setting_changes
          changes = {}
          if params.key?(:enforce_operating_hours)
            changes[:enforce_operating_hours] = ActiveModel::Type::Boolean.new.cast(params[:enforce_operating_hours])
          end
          if params.key?(:scheduled_max_wait_minutes)
            changes[:scheduled_max_wait_minutes] = Integer(params[:scheduled_max_wait_minutes].to_s, 10)
          end
          changes
        end

        def setting_errors
          return [] unless params.key?(:scheduled_max_wait_minutes)

          value = Integer(params[:scheduled_max_wait_minutes].to_s, 10, exception: false)
          return [] if value&.between?(MAX_WAIT_RANGE.begin, MAX_WAIT_RANGE.end)

          [{ field: "scheduled_max_wait_minutes", message: "must be a whole number from 1 to 600" }]
        end

        def render_validation_errors(errors)
          render json: { error: "Validation failed", errors: errors }, status: :unprocessable_content
        end
      end
    end
  end
end
