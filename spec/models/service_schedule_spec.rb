require "rails_helper"

RSpec.describe ServiceSchedule do
  let!(:line) { Line.create!(id: "SSCH_LINE", display_name: "Ssch Line", mode: "bus") }
  let(:weekdays) { %w[mon tue wed thu fri] }

  def build_schedule(**attrs)
    described_class.new({ line: line, days: weekdays, kind: "departures",
                          departure_times: %w[05:00 13:00] }.merge(attrs))
  end

  def window(**attrs)
    build_schedule(kind: "window", start_time: "18:00", end_time: "22:00",
                   departure_times: [], **attrs)
  end

  it "accepts departures" do
    expect(build_schedule).to be_valid
  end

  it "accepts a window, also one that crosses midnight" do
    expect(window).to be_valid
    expect(window(start_time: "22:00", end_time: "02:00")).to be_valid
  end

  it "saves and reads back the arrays" do
    schedule = build_schedule(direction: "southbound")
    schedule.save!
    expect(schedule.reload).to have_attributes(days: weekdays, departure_times: %w[05:00 13:00])
  end

  it "needs a line" do
    expect(build_schedule(line: nil)).not_to be_valid
  end

  describe "kind" do
    it "rejects an unknown kind with an error, not an exception" do
      schedule = build_schedule(kind: "no_service")
      expect(schedule).not_to be_valid
      expect(schedule.errors[:kind]).to be_present
    end
  end

  describe "direction" do
    it "accepts nil" do
      expect(build_schedule(direction: nil)).to be_valid
    end

    it "accepts a known direction" do
      expect(build_schedule(direction: "northbound")).to be_valid
    end

    it "rejects an unknown direction" do
      expect(build_schedule(direction: "upward")).not_to be_valid
    end
  end

  describe "days" do
    it "rejects an empty list" do
      expect(build_schedule(days: [])).not_to be_valid
    end

    it "rejects an unknown day" do
      expect(build_schedule(days: %w[mon funday])).not_to be_valid
    end

    it "rejects a repeated day" do
      expect(build_schedule(days: %w[mon mon])).not_to be_valid
    end
  end

  describe "window" do
    it "needs start_time and end_time" do
      expect(window(start_time: nil)).not_to be_valid
      expect(window(end_time: nil)).not_to be_valid
    end

    it "rejects equal start and end" do
      expect(window(end_time: "18:00")).not_to be_valid
    end

    it "rejects a bad time format" do
      expect(window(start_time: "6pm")).not_to be_valid
      expect(window(end_time: "24:00")).not_to be_valid
    end

    it "rejects departure times" do
      expect(window(departure_times: %w[18:00])).not_to be_valid
    end
  end

  describe "departures" do
    it "needs departure times" do
      expect(build_schedule(departure_times: [])).not_to be_valid
    end

    it "rejects a bad time format" do
      expect(build_schedule(departure_times: %w[05:00 5pm])).not_to be_valid
    end

    it "rejects unsorted times" do
      expect(build_schedule(departure_times: %w[13:00 05:00])).not_to be_valid
    end

    it "rejects a repeated time" do
      expect(build_schedule(departure_times: %w[05:00 05:00])).not_to be_valid
    end

    it "rejects start_time and end_time" do
      expect(build_schedule(start_time: "05:00")).not_to be_valid
      expect(build_schedule(end_time: "13:00")).not_to be_valid
    end
  end

  it "is deleted with its line" do
    build_schedule.save!
    expect { line.destroy! }.to change(described_class, :count).by(-1)
  end
end
