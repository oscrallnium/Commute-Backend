module Api
  module V1
    class UsersController < BaseController
      # GET /api/v1/me
      def me
        json_response({
          id:           current_user.id,
          email:        current_user.email,
          display_name: current_user.display_name,
          role:         current_user.role,
          home_station_id: current_user.home_station_id,
          created_at:   current_user.created_at
        })
      end

      # PATCH /api/v1/me
      def update
        if current_user.update(user_update_params)
          json_response({
            id:           current_user.id,
            email:        current_user.email,
            display_name: current_user.display_name,
            home_station_id: current_user.home_station_id
          })
        else
          error_response("Update failed", errors: current_user.errors.full_messages)
        end
      end

      private

      def user_update_params
        params.require(:user).permit(:display_name, :home_station_id)
      end
    end
  end
end
