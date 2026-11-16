# Writes weekly service schedules and date exceptions. Every method runs inside the publish
# transaction and raises GraphChangeApplier::Rejected, with a field, when a rule refuses the change.
class ServiceScheduleWriter
  TIME_COLUMNS = { "start" => "start_time", "end" => "end_time", "departures" => "departure_times" }.freeze
  EXCEPTION_FIELDS = %w[direction start_date end_date kind note].freeze

  # Replaces the rows of the line, or the rows of one direction, with the given schedules.
  def set(change)
    line = schedulable_line!(change["line_id"])
    direction = known_direction!(line, change["direction"])
    refuse_direction_rows_beside_null_rows!(line, direction)
    rows_of(line, direction).delete_all
    change["schedules"].each { |item| ServiceSchedule.create!(schedule_attrs(line, direction, item)) }
    nil
  end

  def clear(change)
    line = schedulable_line!(change["line_id"])
    rows_of(line, known_direction!(line, change["direction"])).delete_all
    nil
  end

  # Returns the ID of the new exception.
  def add_exception(change)
    line = schedulable_line!(change["line_id"])
    known_direction!(line, change["direction"])
    ServiceScheduleException.create!(exception_attrs(change).merge(line_id: line.id)).id
  end

  def update_exception(change)
    exception = exception_for(change)
    known_direction!(exception.line, change["direction"])
    exception.update!(kind_reset(change).merge(exception_attrs(change)))
    nil
  end

  def delete_exception(change)
    exception_for(change).delete
    nil
  end

  private

  def schedulable_line!(line_id)
    line = Line.find_by(id: line_id)
    raise reject("Line '#{line_id}' was not found.", "line_id") unless line
    raise reject("INTERCHANGE is a reserved line. It has no schedule.", "line_id") if line.id == Line::INTERCHANGE_ID
    raise reject("Line '#{line.id}' is a service area. It has no schedule.", "line_id") if line.service_area

    line
  end

  # Returns the direction after it checks that an edge of the line uses it. Nil passes.
  def known_direction!(line, direction)
    return direction if direction.nil? || Edge.exists?(line: line.id, direction: direction)

    raise reject("No edge of line '#{line.id}' runs #{direction}.", "direction")
  end

  def refuse_direction_rows_beside_null_rows!(line, direction)
    return if direction.nil? || !ServiceSchedule.exists?(line_id: line.id, direction: nil)

    raise reject("Line '#{line.id}' has rows for every direction. Send set without a direction, or clear first.",
                 "direction")
  end

  def rows_of(line, direction)
    rows = ServiceSchedule.where(line_id: line.id)
    direction ? rows.where(direction: direction) : rows
  end

  def schedule_attrs(line, direction, item)
    { line_id: line.id, direction: direction, days: item["days"], kind: item["kind"], note: item["note"],
      departure_times: [], **time_attrs(item) }
  end

  def exception_for(change)
    ServiceScheduleException.find_by(id: change["exception_id"]) ||
      raise(reject("Exception '#{change["exception_id"]}' was not found.", "exception_id"))
  end

  def exception_attrs(change)
    change.slice(*EXCEPTION_FIELDS).symbolize_keys.merge(time_attrs(change))
  end

  # A kind change clears the stored times, so the change carries the times that the new kind needs.
  def kind_reset(change)
    change.key?("kind") ? { start_time: nil, end_time: nil, departure_times: [] } : {}
  end

  def time_attrs(source)
    source.slice(*TIME_COLUMNS.keys).to_h { |key, value| [TIME_COLUMNS.fetch(key).to_sym, value] }
  end

  def reject(message, field)
    GraphChangeApplier::Rejected.new(message, field: field)
  end
end
