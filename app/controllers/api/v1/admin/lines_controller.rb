module Api
  module V1
    module Admin
      class LinesController < BaseController
        before_action :require_admin!
        before_action :set_line

        # PATCH /api/v1/admin/lines/:id
        # Updates only color_hex. A null value clears it, so clients fall back to the mode color.
        def update
          color = params.require(:line)
          unless color.key?(:color_hex)
            return render json: { error: "Nothing to update", errors: ["Send color_hex."] },
                          status: :unprocessable_content
          end

          if @line.update(color_hex: color[:color_hex].presence)
            GraphService.bump_version!
            bust_graph_cache!
            render json: { data: line_json }, status: :ok
          else
            render json: { error: "Update failed", errors: @line.errors.full_messages },
                   status: :unprocessable_entity
          end
        end

        private

        def set_line
          @line = Line.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Line not found" }, status: :not_found
        end

        def line_json
          { id: @line.id, displayName: @line.display_name, mode: @line.mode,
            colorHex: @line.color_hex }
        end
      end
    end
  end
end
