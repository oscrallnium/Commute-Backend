class AllowAllEdgeDirections < ActiveRecord::Migration[7.1]
  CONSTRAINT = "station_access_points_direction_check".freeze
  ALL_DIRECTIONS = %w[northbound southbound eastbound westbound inbound outbound].freeze
  LEGACY_DIRECTIONS = %w[northbound southbound].freeze

  def up
    replace_constraint(ALL_DIRECTIONS)
  end

  # Fails when a row holds a direction that the old constraint rejects.
  def down
    replace_constraint(LEGACY_DIRECTIONS)
  end

  private

  def replace_constraint(directions)
    remove_check_constraint :station_access_points, name: CONSTRAINT
    list = directions.map { |direction| quote(direction) }.join(", ")
    add_check_constraint :station_access_points,
                         "direction IS NULL OR direction IN (#{list})",
                         name: CONSTRAINT
  end
end
