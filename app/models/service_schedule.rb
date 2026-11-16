# A weekly service rule: days plus a window or fixed trip times for a line or one direction.
class ServiceSchedule < ApplicationRecord
  include ServiceTimes

  enum :kind, GraphService::SCHEDULE_KINDS.index_with(&:itself), validate: true

  belongs_to :line, primary_key: :id, inverse_of: :service_schedules

  validate :days_are_valid

  def as_graph_json
    times_graph_json.merge(days: days)
  end

  private

  def days_are_valid
    list = Array(days)
    return errors.add(:days, "must not be empty") if list.empty?

    errors.add(:days, "contains an unknown day") unless (list - GraphService::SERVICE_DAYS).empty?
    errors.add(:days, "must not repeat a day") if list.uniq.size != list.size
  end
end
