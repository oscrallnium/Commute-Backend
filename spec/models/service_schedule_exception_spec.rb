require "rails_helper"

RSpec.describe ServiceScheduleException do
  let!(:line) { Line.create!(id: "SSEX_LINE", display_name: "Ssex Line", mode: "bus") }
  let!(:other_line) { Line.create!(id: "SSEX_OTHER", display_name: "Ssex Other", mode: "bus") }

  def build_exception(**attrs)
    described_class.new({ line: line, start_date: Date.new(2026, 12, 24), end_date: Date.new(2027, 1, 3),
                          kind: "no_service" }.merge(attrs))
  end

  it "accepts no_service" do
    expect(build_exception).to be_valid
  end

  it "accepts a window" do
    expect(build_exception(kind: "window", start_time: "05:00", end_time: "09:00")).to be_valid
  end

  it "accepts departures" do
    expect(build_exception(kind: "departures", departure_times: %w[05:00])).to be_valid
  end

  it "rejects an unknown kind" do
    expect(build_exception(kind: "holiday")).not_to be_valid
  end

  it "needs both dates" do
    expect(build_exception(start_date: nil)).not_to be_valid
    expect(build_exception(end_date: nil)).not_to be_valid
  end

  it "accepts one day" do
    expect(build_exception(end_date: Date.new(2026, 12, 24))).to be_valid
  end

  it "rejects an end date before the start date" do
    expect(build_exception(end_date: Date.new(2026, 12, 23))).not_to be_valid
  end

  it "rejects an unknown direction" do
    expect(build_exception(direction: "upward")).not_to be_valid
  end

  describe "times" do
    it "rejects times on no_service" do
      expect(build_exception(start_time: "05:00")).not_to be_valid
      expect(build_exception(departure_times: %w[05:00])).not_to be_valid
    end

    it "rejects a window without times" do
      expect(build_exception(kind: "window")).not_to be_valid
    end

    it "rejects a window with equal times" do
      expect(build_exception(kind: "window", start_time: "05:00", end_time: "05:00")).not_to be_valid
    end

    it "rejects departures with no times, unsorted times, or a window" do
      expect(build_exception(kind: "departures")).not_to be_valid
      expect(build_exception(kind: "departures", departure_times: %w[13:00 05:00])).not_to be_valid
      expect(build_exception(kind: "departures", departure_times: %w[05:00], start_time: "05:00")).not_to be_valid
    end
  end

  describe "overlap" do
    before { build_exception(direction: "northbound").save! }

    it "rejects the same direction with overlapping dates" do
      overlapping = build_exception(direction: "northbound", start_date: Date.new(2027, 1, 3),
                                    end_date: Date.new(2027, 1, 5))
      expect(overlapping).not_to be_valid
    end

    it "rejects a nil direction against a set direction" do
      expect(build_exception(direction: nil)).not_to be_valid
    end

    it "rejects a set direction against a nil direction" do
      described_class.delete_all
      build_exception(direction: nil).save!
      expect(build_exception(direction: "southbound")).not_to be_valid
    end

    it "accepts a different direction" do
      expect(build_exception(direction: "southbound")).to be_valid
    end

    it "accepts dates that do not overlap" do
      expect(build_exception(direction: "northbound", start_date: Date.new(2027, 1, 4),
                             end_date: Date.new(2027, 1, 5))).to be_valid
    end

    it "accepts another line" do
      expect(build_exception(line: other_line, direction: "northbound")).to be_valid
    end

    it "does not clash with itself on update" do
      saved = described_class.find_by!(line_id: line.id)
      saved.note = "Holiday break"
      expect(saved).to be_valid
    end
  end

  it "is deleted with its line" do
    build_exception.save!
    expect { line.destroy! }.to change(described_class, :count).by(-1)
  end
end
