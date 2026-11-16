# Shared direction and time rules of a service schedule row and a date exception row.
# The including model has the columns direction, kind, start_time, end_time, departure_times.
module ServiceTimes
  extend ActiveSupport::Concern

  included do
    validate :direction_is_known
    validate :times_match_kind
  end

  # The direction, time and note fields that the graph JSON shares between both models.
  def times_graph_json
    json = {}
    json[:direction] = direction if direction.present?
    json[:kind] = kind
    json.merge!(start: start_time, end: end_time) if kind == "window"
    json[:departures] = departure_times if kind == "departures"
    json[:note] = note if note.present?
    json
  end

  private

  def direction_is_known
    return if direction.nil? || GraphService::DIRECTION_TAGS.key?(direction)

    errors.add(:direction, "is not a known direction")
  end

  def times_match_kind
    case kind
    when "window" then validate_window_times
    when "departures" then validate_departure_times
    when "no_service" then validate_no_times
    end
  end

  def validate_window_times
    errors.add(:departure_times, "must be empty for a window") if departure_times.present?
    %i[start_time end_time].each { |field| validate_window_time(field) }
    return unless start_time.present? && start_time == end_time

    errors.add(:end_time, "must differ from start_time")
  end

  def validate_window_time(field)
    value = self[field]
    return errors.add(field, "can't be blank") if value.blank?

    errors.add(field, "must be HH:mm (24-hour)") unless time_valid?(value)
  end

  def validate_departure_times
    errors.add(:start_time, "must be empty for departures") if start_time.present?
    errors.add(:end_time, "must be empty for departures") if end_time.present?
    times = Array(departure_times)
    return errors.add(:departure_times, "must not be empty") if times.empty?
    return errors.add(:departure_times, "must be HH:mm (24-hour)") unless times.all? { |time| time_valid?(time) }

    errors.add(:departure_times, "must not repeat a time") if times.uniq.size != times.size
    errors.add(:departure_times, "must be sorted") if times != times.sort
  end

  def validate_no_times
    %i[start_time end_time departure_times].each do |field|
      errors.add(field, "must be empty for no_service") if self[field].present?
    end
  end

  def time_valid?(value)
    value.is_a?(String) && value.match?(GraphService::TIME_RE)
  end
end
