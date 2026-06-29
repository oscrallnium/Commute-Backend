class RoutePlanEvent < ApplicationRecord
  belongs_to :user, optional: true
  validates :occurred_at, presence: true
end
