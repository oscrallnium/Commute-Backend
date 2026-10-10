require "rails_helper"

RSpec.describe "GraphService#travel_time_minutes" do
  def minutes(dist_km, mode) = GraphService.new.send(:travel_time_minutes, dist_km, mode)

  it "uses 22 km/h for a bus under 5 km" do
    expect(minutes(4.4, "bus")).to be_within(0.001).of(12.0)
  end

  it "uses 16 km/h for a jeepney under 5 km" do
    expect(minutes(4.0, "jeepney")).to be_within(0.001).of(15.0)
  end

  it "uses 15 km/h for a tricycle under 5 km" do
    expect(minutes(3.0, "tricycle")).to be_within(0.001).of(12.0)
  end

  it "uses 30 km/h for a train at any distance" do
    expect(minutes(3.0, "train")).to be_within(0.001).of(6.0)
    expect(minutes(10.0, "train")).to be_within(0.001).of(20.0)
  end

  it "uses 22 km/h for any other mode" do
    expect(minutes(4.4, "walk")).to be_within(0.001).of(12.0)
    expect(minutes(4.4, nil)).to be_within(0.001).of(12.0)
  end

  it "uses 45 km/h for a road mode from 5 km" do
    %w[bus jeepney tricycle].each do |mode|
      expect(minutes(25.222, mode)).to be_within(0.01).of(33.63)
    end
  end

  it "switches to 45 km/h exactly at 5 km" do
    expect(minutes(5.0, "bus")).to be_within(0.001).of(6.667)
    expect(minutes(4.999, "bus")).to be_within(0.001).of(13.634)
  end

  it "keeps a train at 30 km/h above 5 km" do
    expect(minutes(6.0, "train")).to be_within(0.001).of(12.0)
  end

  it "keeps the 2 minute minimum" do
    expect(minutes(0.59, "bus")).to eq(2.0)
    expect(minutes(0.1, "train")).to eq(2.0)
  end
end
