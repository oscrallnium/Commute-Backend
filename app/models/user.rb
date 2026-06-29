class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable, :registerable,
         :recoverable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  enum :role, { commuter: 0, admin: 1 }, default: :commuter

  belongs_to :home_station, class_name: "Station", optional: true, primary_key: :station_id
  has_many :saved_routes, dependent: :destroy
  has_many :ar_world_maps, dependent: :nullify

  validates :display_name, presence: true, length: { maximum: 60 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  def admin?
    role == "admin"
  end
end
