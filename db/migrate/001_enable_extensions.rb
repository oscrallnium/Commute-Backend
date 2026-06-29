class EnableExtensions < ActiveRecord::Migration[7.1]
  def change
    enable_extension "pgcrypto"
    enable_extension "pg_trgm"
    enable_extension "unaccent"
  end
end
