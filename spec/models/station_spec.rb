require "rails_helper"

RSpec.describe Station do
  def build_station(boarding = nil)
    attrs = { station_id: "BOARD_T", name: "T", line: "BOARD", type: "station", lat: 14.0, lng: 121.0 }
    attrs[:boarding] = boarding if boarding
    Station.new(attrs)
  end

  it "defaults boarding to both" do
    expect(build_station.boarding).to eq("both")
  end

  %w[both alight_only].each do |value|
    it "accepts #{value}" do
      expect(build_station(value)).to be_valid
    end
  end

  ["board_only", "", nil].each do |bad|
    it "rejects #{bad.inspect}" do
      station = build_station
      station.boarding = bad
      expect(station).not_to be_valid
    end
  end

  it "includes boarding in as_api_json" do
    expect(build_station("alight_only").as_api_json[:boarding]).to eq("alight_only")
  end
end
