require "rails_helper"

RSpec.describe "GraphService#station_json boarding" do
  def station_json_for(boarding)
    station = Station.new(station_id: "BOARD_T", name: "T", line: "BOARD", type: "station",
                          lat: 14.0, lng: 121.0, boarding: boarding)
    GraphService.new.send(:station_json, station)
  end

  it "omits boarding when it is both" do
    expect(station_json_for("both")).not_to have_key(:boarding)
  end

  it "includes boarding when it is alight_only" do
    expect(station_json_for("alight_only")[:boarding]).to eq("alight_only")
  end
end
