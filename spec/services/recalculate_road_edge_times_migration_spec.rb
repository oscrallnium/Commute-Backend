require "rails_helper"
require Rails.root.join("db/migrate/023_recalculate_road_edge_times")

RSpec.describe RecalculateRoadEdgeTimes do
  let(:migration) { described_class.new }

  def seed_edge(id, mode:, distance_km:, time:, line: "RETIME")
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

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  before do
    GraphMeta.first || GraphMeta.create!
    seed_edge("EXPRESS", mode: "bus", distance_km: 25.222, time: 63.055)
    seed_edge("SHORT_BUS", mode: "bus", distance_km: 0.59, time: 2.0)
    seed_edge("MID_BUS", mode: "bus", distance_km: 4.4, time: 11.0)
    seed_edge("JEEP", mode: "jeepney", distance_km: 4.0, time: 10.0)
    seed_edge("TRIKE", mode: "tricycle", distance_km: 3.0, time: 7.5)
    seed_edge("HAND_SET", mode: "bus", distance_km: 25.222, time: 40.0)
    seed_edge("TRAIN", mode: "train", distance_km: 3.0, time: 7.5)
    seed_edge("WALK_X", mode: "walk", distance_km: 3.0, time: 7.5)
    seed_edge("LINK", mode: "jeepney", distance_km: 3.0, time: 7.5, line: "INTERCHANGE")
  end

  it "recalculates only road edges that hold the old formula time" do
    version = GraphMeta.first.version

    migration.up

    expect(time_of("EXPRESS")).to be_within(0.01).of(33.63)
    expect(time_of("SHORT_BUS")).to eq(2.0)
    expect(time_of("MID_BUS")).to be_within(0.001).of(12.0)
    expect(time_of("JEEP")).to be_within(0.001).of(15.0)
    expect(time_of("TRIKE")).to be_within(0.001).of(12.0)
    expect(time_of("HAND_SET")).to eq(40.0)
    expect(time_of("TRAIN")).to eq(7.5)
    expect(time_of("WALK_X")).to eq(7.5)
    expect(time_of("LINK")).to eq(7.5)
    expect(GraphMeta.first.version).to eq(version + 1)
  end

  it "restores the old formula time on down" do
    migration.up
    migration.down

    expect(time_of("EXPRESS")).to be_within(0.001).of(63.055)
    expect(time_of("MID_BUS")).to be_within(0.001).of(11.0)
    expect(time_of("JEEP")).to be_within(0.001).of(10.0)
    expect(time_of("TRIKE")).to be_within(0.001).of(7.5)
    expect(time_of("HAND_SET")).to eq(40.0)
    expect(time_of("TRAIN")).to eq(7.5)
  end
end
