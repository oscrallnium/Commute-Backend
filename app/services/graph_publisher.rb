# Applies a list of draft changes as one graph version. All changes commit together or none do.
# The graph_meta row stays locked until commit, so two publishes cannot both pass the version check.
# See docs/ops-publish-api.md.
class GraphPublisher
  Result = Struct.new(:status, :body, keyword_init: true)
  class Conflict < StandardError
  end
  Rejected = Class.new(StandardError) do
    attr_reader :error

    def initialize(error)
      super(error.message)
      @error = error
    end
  end

  def self.publish(base_version:, changes:, user:)
    new(base_version: base_version, changes: changes, user: user).publish
  end

  def initialize(base_version:, changes:, user:)
    @base_version = base_version
    @changes      = changes
    @user         = user
  end

  def publish
    return invalid([base_version_error]) unless @base_version.is_a?(Integer)

    clean, errors = GraphChangeValidator.new(@changes).call
    return invalid(errors) if errors.any?

    record = ActiveRecord::Base.transaction { apply_all(clean) }
    Result.new(status: :created, body: { data: published_json(record) })
  rescue Conflict
    conflict
  rescue Rejected => e
    invalid([e.error])
  rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
    Result.new(status: :conflict, body: { error: "Graph busy", message: "Another write holds the graph. Try again." })
  end

  private

  def apply_all(clean)
    meta = GraphMeta.lock.first!
    raise Conflict unless meta.version == @base_version

    applier = GraphChangeApplier.new
    @created = clean.each_with_index.filter_map { |change, index| apply_one(applier, change, index) }
    GraphService.bump_version!
    meta.reload
    GraphVersion.create!(version: meta.version, published_at: meta.last_modified, published_by: @user,
                         change_list: clean, change_count: clean.length)
  end

  # Writes the created ID into the change, so the history row holds the exact ID.
  def apply_one(applier, change, index)
    created_id = applier.apply(change)
    return unless created_id

    change[created_id_field(change["type"])] = created_id
    { index: index, type: change["type"], id: created_id }
  rescue GraphChangeApplier::Rejected => e
    raise Rejected, GraphChangeValidator::Error.new(index: index, type: change["type"], field: e.field, message: e.message)
  end

  def created_id_field(type)
    type == "transfer_add" ? "edge_id" : "access_point_id"
  end

  def published_json(record)
    record.as_api_json.merge(created: @created)
  end

  def base_version_error
    GraphChangeValidator::Error.new(field: "base_version", message: "base_version must be an integer.")
  end

  def invalid(errors)
    Result.new(status: :unprocessable_content,
               body: { error: "Validation failed", errors: errors.map(&:to_h) })
  end

  def conflict
    Result.new(status: :conflict,
               body: { error: "Version conflict", base_version: @base_version,
                       current_version: GraphMeta.first!.version,
                       message: "The graph changed after this draft started. Reload the graph and publish again." })
  end
end
