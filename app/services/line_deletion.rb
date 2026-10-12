# Deletes a line that no stop and no edge uses, with its fare rows and its transport mode entry.
class LineDeletion
  class Error < StandardError
  end

  # Runs inside the caller's transaction and does not raise the graph version.
  def self.delete!(line_id)
    new(line_id).delete!
  end

  # One transaction and one version raise. Used by DELETE /api/v1/admin/lines/:id.
  def self.call(line_id)
    ActiveRecord::Base.transaction do
      delete!(line_id)
      GraphService.bump_version!
    end
    GraphService::Result.new(success?: true, data: { line_id: line_id, version: GraphMeta.first!.version })
  rescue Error => e
    GraphService::Result.new(success?: false, errors: [{ field: "line_id", message: e.message }])
  end

  def initialize(line_id)
    @line_id = line_id.to_s
  end

  def delete!
    line = Line.lock.find_by(id: @line_id)
    raise Error, "Line '#{@line_id}' was not found." unless line
    raise Error, "INTERCHANGE is a reserved line and cannot be deleted." if line.id == Line::INTERCHANGE_ID

    refuse_when_in_use!
    TransportMode.where("? = ANY(lines)", line.id).update_all(["lines = array_remove(lines, ?)", line.id])
    FareMatrix.where(line_name: line.id).delete_all
    RailFareTable.where(line_id: line.id).delete_all
    line.destroy!
  end

  private

  def refuse_when_in_use!
    stations = Station.where(line: @line_id).count
    edges    = Edge.where(line: @line_id).count
    return if stations.zero? && edges.zero?

    raise Error, "Line '#{@line_id}' still has #{stations} stops and #{edges} edges. " \
                 "Delete the route first."
  end
end
