module Api
  module V1
    module Auth
      class RegistrationsController < Devise::RegistrationsController
        respond_to :json

        before_action :authenticate_user!, only: [:destroy]

        # POST /auth/register
        def create
          build_resource(sign_up_params)
          resource.save
          if resource.persisted?
            token = Warden::JWTAuth::UserEncoder.new.call(resource, :user, nil).first
            render json: {
              data: {
                token: token,
                user: {
                  id: resource.id,
                  email: resource.email,
                  display_name: resource.display_name,
                  role: resource.role
                }
              }
            }, status: :created
          else
            render json: {
              error: "Registration failed",
              errors: resource.errors.full_messages
            }, status: :unprocessable_content
          end
        end

        # DELETE /api/v1/auth/account  — App Store compliance
        def destroy
          current_user.destroy!
          render json: { message: "Account deleted successfully" }, status: :ok
        rescue => e
          render json: { error: "Could not delete account", message: e.message },
                 status: :internal_server_error
        end

        private

        def sign_up_params
          params.require(:user).permit(:email, :password, :password_confirmation, :display_name)
        end
      end
    end
  end
end
