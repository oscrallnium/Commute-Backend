module ApplicationCable
  # Accepts only an admin whose devise-jwt token arrives as the `token` query parameter.
  # The decoder checks the signature, the expiry, and the `users.jti` revocation.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_admin || reject_unauthorized_connection
    end

    private

    def find_admin
      token = request.params[:token].presence
      return unless token

      user = Warden::JWTAuth::UserDecoder.new.call(token, :user, nil)
      user if user&.admin?
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      nil
    end
  end
end
