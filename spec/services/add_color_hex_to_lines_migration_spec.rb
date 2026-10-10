require "rails_helper"
require Rails.root.join("db/migrate/025_add_color_hex_to_lines")

RSpec.describe AddColorHexToLines do
  let(:migration) { described_class.new }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  before { GraphMeta.first || GraphMeta.create! }

  # The spec rolls the column back, so each example starts without it and `up` adds it.
  def run_up
    migration.down if Line.column_names.include?("color_hex")
    Line.reset_column_information
    migration.up
    Line.reset_column_information
  end

  after { Line.reset_column_information }

  it "adds a nullable column, sets the listed colors, and bumps the graph version" do
    Line.where(id: %w[MRT3 TRICYCLE_MANILA]).delete_all
    Line.create!(id: "MRT3", display_name: "MRT-3", mode: "train")
    Line.create!(id: "TRICYCLE_MANILA", display_name: "Manila Tricycle", mode: "tricycle")
    Line.create!(id: "UNLISTED_LINE", display_name: "Unlisted", mode: "bus")
    version = GraphMeta.first.version

    run_up

    column = Line.columns_hash["color_hex"]
    expect(column.null).to be(true)
    expect(column.default).to be_nil
    expect(Line.find("MRT3").color_hex).to eq("#F2C230")
    expect(Line.find("TRICYCLE_MANILA").color_hex).to eq("#00AD7A")
    expect(Line.find("UNLISTED_LINE").color_hex).to be_nil
    expect(GraphMeta.first.version).to eq(version + 2)
  end

  it "skips a missing line" do
    Line.where(id: "LRT1").delete_all

    expect { run_up }.not_to raise_error
    expect(Line.exists?("LRT1")).to be(false)
  end

  it "removes the column on down" do
    run_up
    migration.down
    Line.reset_column_information

    expect(Line.column_names).not_to include("color_hex")
    migration.up
  end
end
