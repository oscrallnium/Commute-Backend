require "rails_helper"

RSpec.describe Line do
  def build_line(color) = Line.new(id: "COLOR_T", display_name: "T", mode: "bus", color_hex: color)

  it "accepts a nil color" do
    expect(build_line(nil)).to be_valid
  end

  it "accepts #RRGGBB" do
    expect(build_line("#A1B2C3")).to be_valid
  end

  it "normalizes lowercase to uppercase" do
    line = build_line("#a1b2c3")
    line.valid?
    expect(line.color_hex).to eq("#A1B2C3")
  end

  %w[A1B2C3 #A1B2C #A1B2C3D #GGGGGG red].each do |bad|
    it "rejects #{bad.inspect}" do
      expect(build_line(bad)).not_to be_valid
    end
  end
end
