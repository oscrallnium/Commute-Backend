module Api
  module V1
    module Auth
      class SessionsController < Devise::SessionsController
        respond_to :json

        # POST /auth/sign_in
        def create
          super
        end

        # DELETE /auth/sign_out
        def destroy
          super
        end

        # POST /api/v1/auth/refresh
        # Returns a new token while revoking the current JTI.
        def refresh
          current_user = warden.authenticate(scope: :user)
          return render json: { error: "Unauthorized" }, status: :unauthorized unless current_user

          # Rotate JTI — invalidates old token
          current_user.update_column(:jti, SecureRandom.uuid)
          token = Warden::JWTAuth::UserEncoder.new.call(current_user, :user, nil).first

          render json: {
            data: {
              token: token,
              user: user_payload(current_user)
            }
          }, status: :ok
        end

        private

        def respond_with(resource, _opts = {})
          if resource.persisted?
            token  = request.env["warden-jwt_auth.token"]
            render json: {
              data: {
                token: token,
                user: user_payload(resource)
              }
            }, status: :ok
          else
            render json: {
              error: "Invalid email or password"
            }, status: :unauthorized
          end
        end

        def respond_to_on_destroy
          if current_user
            render json: { message: "Signed out successfully" }, status: :ok
          else
            render json: { error: "Unauthorized" }, status: :unauthorized
          end
        end

        def user_payload(user)
          {
            id: user.id,
            email: user.email,
            display_name: user.display_name,
            role: user.role
          }
        end
      end
    end
  end
end
