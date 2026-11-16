# A date range that replaces the regular service of a line or one direction.
class ServiceScheduleException < ApplicationRecord
  include ServiceTimes

  enum :kind, GraphService::EXCEPTION_KINDS.index_with(&:itself), validate: true

  belongs_to :line, primary_key: :id, inverse_of: :service_schedule_exceptions

  validates :start_date, :end_date, presence: true
  validate :end_date_not_before_start_date
  validate :dates_do_not_overlap

  def as_graph_json
    times_graph_json.merge(id: id, from: start_date.iso8601, to: end_date.iso8601)
  end

  private

  def end_date_not_before_start_date
    return unless start_date && end_date && end_date < start_date

    errors.add(:end_date, "must not be before start_date")
  end

  # Two exceptions clash when their dates overlap and their directions are equal or one is nil.
  def dates_do_not_overlap
    return unless line_id && start_date && end_date
    return unless overlapping_exceptions.exists?

    errors.add(:base, "overlaps another exception of this line")
  end

  def overlapping_exceptions
    scope = self.class.where(line_id: line_id).where.not(id: id)
                .where("start_date <= ? AND end_date >= ?", end_date, start_date)
    return scope if direction.nil?

    scope.where(direction: [direction, nil])
  end
end
