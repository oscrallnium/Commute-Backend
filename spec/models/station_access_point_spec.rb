require "rails_helper"

RSpec.describe StationAccessPoint do
  before do
    Station.create!(station_id: "AP_STATION", name: "Station", line: "AP", type: "jeepney", lat: 14.0, lng: 121.0)
  end

  def build_access_point(direction)
    described_class.new(access_point_id: "AP_T", station_id: "AP_STATION", kind: "both",
                        direction: direction, lat: 14.0, lng: 121.0)
  end

  it "accepts every direction that GraphService accepts, and the database stores it" do
    GraphService::DIRECTION_TAGS.each_key do |direction|
      access_point = build_access_point(direction)
      expect(access_point).to be_valid
      expect { access_point.save! }.not_to raise_error
      access_point.destroy!
    end
  end

  it "accepts no direction" do
    expect(build_access_point(nil)).to be_valid
  end

  it "rejects an unknown direction" do
    expect(build_access_point("east")).not_to be_valid
  end
end
