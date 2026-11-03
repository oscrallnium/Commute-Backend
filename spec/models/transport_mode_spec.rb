require "rails_helper"

RSpec.describe TransportMode do
  def build_mode(shape) = TransportMode.new(id: "SAST_MODE", display_name: "Test", service_shape: shape)

  it "defaults to the path shape" do
    expect(TransportMode.new.service_shape).to eq("path")
  end

  it "maps the enum to the stored text" do
    expect(TransportMode.service_shapes).to eq("path" => "path", "area" => "area")
    expect(build_mode("area")).to be_area_service_shape
  end

  it "accepts each valid shape" do
    expect(build_mode("path")).to be_valid
    expect(build_mode("area")).to be_valid
  end

  it "fails validation for an unknown shape without raising" do
    mode = build_mode("blob")
    expect(mode).not_to be_valid
    expect(mode.errors[:service_shape]).to be_present
  end
end
