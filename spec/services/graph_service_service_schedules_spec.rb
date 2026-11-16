require "rails_helper"

RSpec.describe "GraphService service schedules" do
  let(:today) { Time.find_zone("Asia/Manila").today }

  before do
    GraphMeta.first || GraphMeta.create!
    TransportMode.find_or_create_by!(id: "bus") do |m|
      m.display_name = "Bus"
      m.mk_directions_type = "automobile"
    end
    %w[SCHG_BUS SCHG_HIDDEN SCHG_EMPTY].each do |id|
      Line.create!(id: id, display_name: id, mode: "bus")
    end
    Line.find("SCHG_HIDDEN").update!(enabled: false)
  end

  def schedule(line_id, **attrs)
    ServiceSchedule.create!({ line_id: line_id, days: %w[mon tue], kind: "departures",
                              departure_times: %w[05:00 13:00] }.merge(attrs))
  end

  def public_graph = GraphService.assemble_graph.deep_stringify_keys
  def admin_graph = GraphService.assemble_admin_graph.deep_stringify_keys

  it "sends an empty hash for each key and 60 minutes when nothing is set" do
    [public_graph, admin_graph].each do |graph|
      expect(graph).to include("scheduledMaxWaitMinutes" => 60, "serviceSchedules" => {},
                               "serviceScheduleExceptions" => {})
    end
  end

  it "sends the meta value for the maximum wait" do
    GraphMeta.first.update!(scheduled_max_wait_minutes: 90)

    expect(public_graph["scheduledMaxWaitMinutes"]).to eq(90)
  end

  it "groups rows by line and omits a line without rows" do
    schedule("SCHG_BUS", direction: "southbound")
    schedule("SCHG_BUS", direction: "northbound", note: "Express")

    rows = public_graph["serviceSchedules"]

    expect(rows.keys).to eq(["SCHG_BUS"])
    expect(rows["SCHG_BUS"].map { |row| row["direction"] }).to contain_exactly("southbound", "northbound")
    expect(rows["SCHG_BUS"].find { |row| row["direction"] == "northbound" }).to eq(
      "direction" => "northbound", "days" => %w[mon tue], "kind" => "departures",
      "departures" => %w[05:00 13:00], "note" => "Express"
    )
  end

  it "omits direction, note, and departures for a window row" do
    schedule("SCHG_BUS", kind: "window", start_time: "18:00", end_time: "22:00", departure_times: [], note: "")

    expect(public_graph["serviceSchedules"]["SCHG_BUS"]).to eq(
      [{ "days" => %w[mon tue], "kind" => "window", "start" => "18:00", "end" => "22:00" }]
    )
  end

  it "sends exceptions with id and ISO dates and omits start, end, and departures for no_service" do
    exception = ServiceScheduleException.create!(line_id: "SCHG_BUS", start_date: today + 1, end_date: today + 3,
                                                 kind: "no_service", note: "Holiday")

    expect(public_graph["serviceScheduleExceptions"]["SCHG_BUS"]).to eq(
      [{ "id" => exception.id, "from" => (today + 1).iso8601, "to" => (today + 3).iso8601,
         "kind" => "no_service", "note" => "Holiday" }]
    )
  end

  it "keeps an exception that ends today and leaves out a past exception" do
    ServiceScheduleException.create!(line_id: "SCHG_BUS", start_date: today - 5, end_date: today - 1,
                                     kind: "no_service")
    ServiceScheduleException.create!(line_id: "SCHG_BUS", start_date: today, end_date: today,
                                     kind: "departures", departure_times: %w[05:00], direction: "northbound")

    rows = public_graph["serviceScheduleExceptions"]["SCHG_BUS"]

    expect(rows.size).to eq(1)
    expect(rows.first).to include("kind" => "departures", "direction" => "northbound", "departures" => %w[05:00])
  end

  it "leaves a hidden line out of the public graph and keeps it in the admin graph" do
    schedule("SCHG_HIDDEN")
    ServiceScheduleException.create!(line_id: "SCHG_HIDDEN", start_date: today, end_date: today, kind: "no_service")

    expect(public_graph["serviceSchedules"]).to eq({})
    expect(public_graph["serviceScheduleExceptions"]).to eq({})
    expect(admin_graph["serviceSchedules"].keys).to eq(["SCHG_HIDDEN"])
    expect(admin_graph["serviceScheduleExceptions"].keys).to eq(["SCHG_HIDDEN"])
  end
end
