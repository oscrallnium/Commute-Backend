class AddTrgmSearchIndexes < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:stations)
    execute "CREATE INDEX IF NOT EXISTS idx_stations_name_trgm ON stations USING gin (name gin_trgm_ops)"
    execute "CREATE INDEX IF NOT EXISTS idx_stations_short_name_trgm ON stations USING gin (short_name gin_trgm_ops)"
    execute "CREATE INDEX IF NOT EXISTS idx_stations_line_trgm ON stations USING gin (line gin_trgm_ops)"
  end

  def down
    return unless table_exists?(:stations)
    execute "DROP INDEX IF EXISTS idx_stations_name_trgm"
    execute "DROP INDEX IF EXISTS idx_stations_short_name_trgm"
    execute "DROP INDEX IF EXISTS idx_stations_line_trgm"
  end
end
