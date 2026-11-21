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

  describe "fare_step_km" do
    before { Line.create!(id: "STEP_T", display_name: "T", mode: "bus") }

    it "stores null and a value of 0 or more" do
      expect(Line.find("STEP_T").fare_step_km).to be_nil
      expect { Line.where(id: "STEP_T").update_all(fare_step_km: 0) }.not_to raise_error
      expect { Line.where(id: "STEP_T").update_all(fare_step_km: 0.5) }.not_to raise_error
      expect(Line.find("STEP_T").fare_step_km).to eq(0.5)
    end

    it "has a check constraint that refuses a negative value" do
      expect { Line.where(id: "STEP_T").update_all(fare_step_km: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /lines_fare_step_km_check/)
    end

    it "refuses a negative value in validation" do
      expect(Line.new(id: "STEP_U", display_name: "U", mode: "bus", fare_step_km: -0.1)).not_to be_valid
    end
  end
end
