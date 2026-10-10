require "rails_helper"
require Rails.root.join("db/migrate/022_rename_line_ids")

RSpec.describe RenameLineIds do
  let(:migration) { described_class.new }
  let(:pairs) do
    {
      "MRT-3" => "MRT3", "LRT-1" => "LRT1", "LRT-2" => "LRT2", "EDSA_BUS" => "EDSA_CAROUSEL",
      "GUADALUPE_LRT.BUENDIA" => "GUADALUPE_BUENDIA", "STACRUZ.LRT_BUENDI" => "STA_CRUZ_BUENDIA"
    }
  end

  def seed_line(id, name: id)
    Line.create!(id: id, display_name: name, mode: "bus", last_stop_number: 7)
    Station.create!(station_id: "#{id}_A", name: "A", line: id, type: "bus", lat: 14.5, lng: 121.0)
    Station.create!(station_id: "#{id}_B", name: "B", line: id, type: "bus", lat: 14.6, lng: 121.0)
    Edge.create!(edge_id: "#{id}_A__#{id}_B", from_station: "#{id}_A", to_station: "#{id}_B",
                 line: id, mode: "bus", travel_time_minutes: 5, distance_km: 1)
  end

  def ids_in(table, column) = ActiveRecord::Base.connection.select_values("SELECT #{column} FROM #{table}")

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  before do
    GraphMeta.first || GraphMeta.create!
    pairs.each_key { |id| seed_line(id) }
    Line.create!(id: "GUADALUPE_BUENDIA", display_name: "Empty")
    Line.create!(id: "STACRUZ.LRT_BUENDIA", display_name: "Untouched")
    FareMatrix.create!(line_name: "EDSA_BUS", type: "flat", data: { "fare" => 15 })
    Incident.insert_all([{ line_id: "MRT-3", category: 4, created_at: Time.current, updated_at: Time.current }])
    TransportMode.create!(id: "bus", display_name: "Bus", lines: %w[EDSA_BUS OTHER])
  end

  it "renames every line id and restores it on down" do
    version = GraphMeta.first.version
    station_ids = Station.order(:station_id).pluck(:station_id)
    edge_ids = Edge.order(:edge_id).pluck(:edge_id)

    migration.up

    expect(Line.where(id: pairs.keys)).to be_empty
    expect(Line.where(id: pairs.values).count).to eq(6)
    expect(Line.find("EDSA_CAROUSEL")).to have_attributes(display_name: "EDSA Carousel", last_stop_number: 7)
    expect(Line.find("STA_CRUZ_BUENDIA").display_name).to eq("Sta. Cruz–LRT Buendia")
    expect(Line.find("GUADALUPE_BUENDIA").display_name).to eq("Guadalupe–LRT Buendia")
    expect(Line.find("STACRUZ.LRT_BUENDIA").display_name).to eq("Untouched")
    expect(Station.where(line: pairs.values).count).to eq(12)
    expect(Edge.where(line: pairs.values).count).to eq(6)
    expect(Station.where(line: pairs.keys)).to be_empty
    expect(Edge.where(line: pairs.keys)).to be_empty
    expect(FareMatrix.pluck(:line_name)).to eq(["EDSA_CAROUSEL"])
    expect(ids_in("incidents", "line_id")).to eq(["MRT3"])
    expect(TransportMode.find("bus").lines).to eq(%w[EDSA_CAROUSEL OTHER])
    expect(Station.order(:station_id).pluck(:station_id)).to eq(station_ids)
    expect(Edge.order(:edge_id).pluck(:edge_id)).to eq(edge_ids)
    expect(GraphMeta.first.version).to eq(version + 1)

    migration.down

    expect(Line.where(id: pairs.values)).to be_empty
    expect(Line.where(id: pairs.keys).count).to eq(6)
    expect(Line.find("EDSA_BUS").display_name).to eq("EDSA Bus")
    expect(Line.find("STACRUZ.LRT_BUENDI").display_name).to eq("Sta. Cruz-LRT Buendia")
    expect(Line.find("GUADALUPE_LRT.BUENDIA").display_name).to eq("Guadalupe–LRT Buendia")
    expect(Station.where(line: pairs.keys).count).to eq(12)
    expect(Edge.where(line: pairs.keys).count).to eq(6)
    expect(FareMatrix.pluck(:line_name)).to eq(["EDSA_BUS"])
    expect(ids_in("incidents", "line_id")).to eq(["MRT-3"])
    expect(TransportMode.find("bus").lines).to eq(%w[EDSA_BUS OTHER])
    expect(Line.exists?("GUADALUPE_BUENDIA")).to be(false)
    expect(GraphMeta.first.version).to eq(version + 2)
  end

  it "raises and changes nothing when the target line has stations" do
    Station.create!(station_id: "X1", name: "X", line: "LRT1", type: "train", lat: 14.5, lng: 121.0)

    expect { migration.up }.to raise_error(/LRT1 already has stations or edges/)
  end

  it "skips a pair whose old id is absent" do
    Station.where(line: "LRT-2").delete_all
    Edge.where(line: "LRT-2").delete_all
    Line.where(id: "LRT-2").delete_all

    expect { migration.up }.not_to raise_error
    expect(Line.exists?("LRT2")).to be(false)
  end
end
