class UserIdentity < ApplicationRecord
  belongs_to :user

  enum :provider, { apple: 0, google: 1 }, validate: true

  encrypts :apple_refresh_token

  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :provider, uniqueness: { scope: :user_id }
end
