module AuthHelpers
  def auth_token_for(user)
    token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    token
  end

  def auth_headers_for(user)
    { "Authorization" => "Bearer #{auth_token_for(user)}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
