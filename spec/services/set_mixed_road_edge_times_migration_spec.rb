require "rails_helper"
require Rails.root.join("db/migrate/024_set_mixed_road_edge_times")

RSpec.describe SetMixedRoadEdgeTimes do
  let(:migration) { described_class.new }

  let(:seeds) do
    {
      "STACRUZ.LRT_BUENDI_NB_SEG1" => { distance_km: 26.45, fixed: 52.9 },
      "UPLB_KANAN_SEG2" => { distance_km: 10.71, fixed: 25.7 },
      "STACRUZ.LRT_BUENDI_NB_SEG3" => { distance_km: 53.70, fixed: 78.3 },
      "AYALA_ALABANG_SB_S10__AYALA_ALABANG_SB_S11" => { distance_km: 8.59, fixed: 14.2 }
    }
  end

  def seed_edge(id, distance_km:, time:, mode: "bus", line: "MIXED")
    Station.find_or_create_by!(station_id: "#{id}_A") do |s|
      s.assign_attributes(name: "A", line: line, type: mode, lat: 14.5, lng: 121.0)
    end
    Station.find_or_create_by!(station_id: "#{id}_B") do |s|
      s.assign_attributes(name: "B", line: line, type: mode, lat: 14.6, lng: 121.0)
    end
    Edge.create!(edge_id: id, from_station: "#{id}_A", to_station: "#{id}_B", line: line,
                 mode: mode, travel_time_minutes: time, distance_km: distance_km)
  end

  def time_of(id) = Edge.find(id).travel_time_minutes.to_f

  def seed_all_at_rule_values
    seeds.each do |id, seed|
      seed_edge(id, distance_km: seed[:distance_km], time: seed[:distance_km] / 0.75)
    end
  end

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  before { GraphMeta.first || GraphMeta.create! }

  it "sets the fixed times and bumps the graph version" do
    seed_all_at_rule_values
    version = GraphMeta.first.version

    migration.up

    seeds.each { |id, seed| expect(time_of(id)).to be_within(0.001).of(seed[:fixed]) }
    expect(GraphMeta.first.version).to eq(version + 1)
  end

  it "keeps a hand-set edge" do
    seed_all_at_rule_values
    Edge.find("UPLB_KANAN_SEG2").update!(travel_time_minutes: 20.0)

    migration.up

    expect(time_of("UPLB_KANAN_SEG2")).to eq(20.0)
    expect(time_of("STACRUZ.LRT_BUENDI_NB_SEG1")).to be_within(0.001).of(52.9)
  end

  it "skips a missing edge" do
    seed_all_at_rule_values
    Edge.find("STACRUZ.LRT_BUENDI_NB_SEG3").destroy!

    expect { migration.up }.not_to raise_error

    expect(Edge.exists?("STACRUZ.LRT_BUENDI_NB_SEG3")).to be(false)
    expect(time_of("UPLB_KANAN_SEG2")).to be_within(0.001).of(25.7)
  end

  it "restores the rule values on down" do
    seed_all_at_rule_values
    migration.up
    migration.down

    seeds.each { |id, seed| expect(time_of(id)).to be_within(0.01).of(seed[:distance_km] / 0.75) }
  end

  it "keeps a hand-set edge on down" do
    seed_all_at_rule_values
    migration.up
    Edge.find("UPLB_KANAN_SEG2").update!(travel_time_minutes: 20.0)

    migration.down

    expect(time_of("UPLB_KANAN_SEG2")).to eq(20.0)
    expect(time_of("STACRUZ.LRT_BUENDI_NB_SEG1")).to be_within(0.01).of(26.45 / 0.75)
  end
end
