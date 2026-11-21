require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "connects an admin with a valid token" do
    token, = Warden::JWTAuth::UserEncoder.new.call(admin_user, :user, nil)
    connect "/cable?token=#{token}"
    expect(connection.current_user).to eq(admin_user)
  end

  it "rejects a connection with no token" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects a bad token" do
    expect { connect "/cable?token=not-a-jwt" }.to have_rejected_connection
  end

  it "rejects a commuter" do
    token, = Warden::JWTAuth::UserEncoder.new.call(rider_user, :user, nil)
    expect { connect "/cable?token=#{token}" }.to have_rejected_connection
  end

  it "rejects a revoked token" do
    token, = Warden::JWTAuth::UserEncoder.new.call(admin_user, :user, nil)
    admin_user.update_column(:jti, SecureRandom.uuid)
    expect { connect "/cable?token=#{token}" }.to have_rejected_connection
  end
end
