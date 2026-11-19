class ImportTollMatrix < ActiveRecord::Migration[7.1]
  # The cache clear must run after the commit, so DDL runs in an explicit transaction.
  disable_ddl_transaction!

  MATRIX_PATH = Rails.root.join("data/toll_matrix.json")
  PLAZA_IDS = {
    "Magallanes" => "MAGALLANES", "Buendia" => "BUENDIA", "C-5" => "C5", "Amorsolo" => "AMORSOLO",
    "Bicutan" => "BICUTAN", "Magallanes (Skyway)" => "MAGALLANES_SKYWAY", "NAIAX" => "NAIAX",
    "Sucat" => "SUCAT", "Alabang" => "ALABANG", "Filinvest" => "FILINVEST", "MCX" => "MCX",
    "Susana Heights" => "SUSANA_HEIGHTS", "San Pedro" => "SAN_PEDRO", "Southwoods" => "SOUTHWOODS",
    "Carmona" => "CARMONA", "Mamplasan" => "MAMPLASAN", "Sta. Rosa" => "STA_ROSA",
    "ABI/Greenfield" => "ABI_GREENFIELD", "Cabuyao" => "CABUYAO", "Silangan" => "SILANGAN",
    "Calamba" => "CALAMBA", "Merville" => "MERVILLE", "Don Bosco" => "DON_BOSCO"
  }.freeze

  class MigrationPlaza < ActiveRecord::Base
    self.table_name = "toll_plazas"
  end

  class MigrationFare < ActiveRecord::Base
    self.table_name = "toll_fares"
  end

  def up
    transaction do
      PLAZA_IDS.each { |name, id| MigrationPlaza.find_or_create_by!(id: id) { |plaza| plaza.name = name } }
      each_fare do |entry, exit_id, amount|
        MigrationFare.find_or_create_by!(entry_plaza_id: entry, exit_plaza_id: exit_id) { |fare| fare.amount = amount }
      end
      bump_graph_version!
    end
    clear_graph_cache!
  end

  def down
    transaction do
      MigrationFare.delete_all
      MigrationPlaza.delete_all
      bump_graph_version!
    end
    clear_graph_cache!
  end

  private

  def each_fare
    JSON.parse(File.read(MATRIX_PATH)).each do |entry_name, row|
      row.each { |exit_name, amount| yield plaza_id!(entry_name), plaza_id!(exit_name), amount unless amount.nil? }
    end
  end

  def plaza_id!(name)
    PLAZA_IDS.fetch(name) { raise "Toll plaza '#{name}' is not in PLAZA_IDS." }
  end

  def bump_graph_version!
    GraphMeta.update_all("version = version + 1, last_modified = NOW()")
  end

  # A cache error does not fail the migration, because each entry also expires on its own.
  def clear_graph_cache!
    %w[full_graph graph_version routes_index].each { |key| Rails.cache.delete(key) }
    Rails.cache.delete_matched("stations*")
  rescue StandardError => e
    say "Graph cache not cleared: #{e.class}: #{e.message}"
  end
end
