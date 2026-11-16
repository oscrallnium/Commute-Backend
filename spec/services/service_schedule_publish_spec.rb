require "rails_helper"

RSpec.describe "Service schedule publish changes" do
  before do
    build_ops_graph!
    add_direction_edges!
  end

  def publish(*changes, base: graph_version_now)
    GraphPublisher.publish(base_version: base, changes: changes.map(&:deep_stringify_keys), user: admin_user)
  end

  def expect_created(result)
    expect(result.status).to eq(:created), result.body.inspect
  end

  def expect_rejected(result, field:, message: nil)
    expect(result.status).to eq(:unprocessable_content), result.body.inspect
    error = result.body[:errors].first
    expect(error[:field]).to eq(field)
    expect(error[:message]).to include(message) if message
  end

  # OPST_ROAD gets one northbound and one southbound edge. OPST_RAIL keeps null-direction edges.
  def add_direction_edges!
    Edge.where(line: "OPST_ROAD").first.update!(direction: "northbound", bidirectional: false)
    Edge.where(line: "OPST_ROAD").second.update!(direction: "southbound", bidirectional: false)
  end

  def weekday_departures(times = %w[09:00 18:00])
    { days: %w[mon tue wed thu fri], kind: "departures", departures: times }
  end

  def set_schedule(schedules, **extra)
    { type: "service_schedule_set", line_id: "OPST_ROAD", schedules: schedules }.merge(extra)
  end

  def add_exception(**overrides)
    { type: "service_exception_add", line_id: "OPST_ROAD", start_date: "2026-12-24", end_date: "2027-01-03",
      kind: "no_service" }.merge(overrides)
  end

  describe "service_schedule_set" do
    it "inserts the rows and raises the version once" do
      version = graph_version_now
      result = publish(set_schedule([weekday_departures(%w[18:00 09:00]),
                                     { days: %w[sat], kind: "departures", departures: %w[05:00] }],
                                    direction: "southbound"))

      expect_created(result)
      expect(graph_version_now).to eq(version + 1)
      expect(result.body[:data][:created]).to eq([])
      rows = ServiceSchedule.where(line_id: "OPST_ROAD").order(:days)
      expect(rows.map(&:direction)).to all(eq("southbound"))
      expect(rows.map(&:departure_times)).to contain_exactly(%w[09:00 18:00], %w[05:00])
    end

    it "stores a window with a note" do
      expect_created(publish(set_schedule([{ days: %w[mon sun], kind: "window", start: "18:00", end: "22:00",
                                             note: " Evening " }])))

      expect(ServiceSchedule.find_by(line_id: "OPST_ROAD")).to have_attributes(
        direction: nil, days: %w[mon sun], kind: "window", start_time: "18:00", end_time: "22:00",
        departure_times: [], note: "Evening"
      )
    end

    it "replaces every row of the line when it has no direction" do
      expect_created(publish(set_schedule([weekday_departures], direction: "northbound")))
      expect_created(publish(set_schedule([{ days: %w[sat], kind: "window", start: "05:00", end: "09:00" }])))

      expect(ServiceSchedule.where(line_id: "OPST_ROAD").pluck(:direction, :kind)).to eq([[nil, "window"]])
    end

    it "replaces only the rows of its direction" do
      expect_created(publish(set_schedule([weekday_departures], direction: "northbound")))
      expect_created(publish(set_schedule([weekday_departures], direction: "southbound")))
      expect_created(publish(set_schedule([{ days: %w[sat], kind: "departures", departures: %w[05:00] }],
                                          direction: "southbound")))

      expect(ServiceSchedule.where(line_id: "OPST_ROAD", direction: "northbound").count).to eq(1)
      expect(ServiceSchedule.where(line_id: "OPST_ROAD", direction: "southbound").map(&:days)).to eq([%w[sat]])
    end

    it "refuses a direction set while rows for every direction exist" do
      expect_created(publish(set_schedule([weekday_departures])))

      expect_rejected(publish(set_schedule([weekday_departures], direction: "northbound")), field: "direction",
                                                                                            message: "every direction")
      expect(ServiceSchedule.where(line_id: "OPST_ROAD").pluck(:direction)).to eq([nil])
    end

    it "refuses an unknown line, INTERCHANGE, and a service area line" do
      expect_rejected(publish(set_schedule([weekday_departures], line_id: "NOPE")), field: "line_id",
                                                                                    message: "was not found")
      expect_rejected(publish(set_schedule([weekday_departures], line_id: "INTERCHANGE")), field: "line_id",
                                                                                           message: "INTERCHANGE")
      build_area_mode!
      expect_created(publish(service_area_change))
      expect_rejected(publish(set_schedule([weekday_departures], line_id: "SAPB_ZONE")), field: "line_id",
                                                                                         message: "service area")
      expect_rejected(publish(add_exception(line_id: "SAPB_ZONE")), field: "line_id", message: "service area")
    end

    it "refuses a direction that no edge of the line uses" do
      expect_rejected(publish(set_schedule([weekday_departures], direction: "eastbound")), field: "direction",
                                                                                           message: "eastbound")
      expect_rejected(publish(set_schedule([weekday_departures], line_id: "OPST_RAIL", direction: "northbound")),
                      field: "direction")
    end

    it "rolls back every change when a later change is refused" do
      result = publish(set_schedule([weekday_departures]), set_schedule([weekday_departures], line_id: "NOPE"))

      expect(result.body[:errors].first[:index]).to eq(1)
      expect(ServiceSchedule.count).to eq(0)
    end
  end

  describe "service_schedule_clear" do
    before do
      expect_created(publish(set_schedule([weekday_departures], direction: "northbound")))
      expect_created(publish(set_schedule([weekday_departures], direction: "southbound")))
    end

    it "removes the rows of one direction" do
      expect_created(publish({ type: "service_schedule_clear", line_id: "OPST_ROAD", direction: "northbound" }))

      expect(ServiceSchedule.pluck(:direction)).to eq(["southbound"])
    end

    it "removes every row of the line when it has no direction" do
      version = graph_version_now
      expect_created(publish({ type: "service_schedule_clear", line_id: "OPST_ROAD" }))

      expect(ServiceSchedule.count).to eq(0)
      expect(graph_version_now).to eq(version + 1)
    end

    it "refuses an unknown line and an unused direction" do
      expect_rejected(publish({ type: "service_schedule_clear", line_id: "NOPE" }), field: "line_id")
      expect_rejected(publish({ type: "service_schedule_clear", line_id: "OPST_ROAD", direction: "westbound" }),
                      field: "direction")
    end
  end

  describe "service_exception_add" do
    it "creates the row and reports its ID as exception_id" do
      version = graph_version_now
      result = publish(add_exception(note: " Holiday break "))

      expect_created(result)
      expect(graph_version_now).to eq(version + 1)
      exception = ServiceScheduleException.find_by!(line_id: "OPST_ROAD")
      expect(result.body[:data][:created]).to eq([{ index: 0, type: "service_exception_add", id: exception.id }])
      expect(exception).to have_attributes(kind: "no_service", direction: nil, note: "Holiday break",
                                           start_date: Date.new(2026, 12, 24), end_date: Date.new(2027, 1, 3))
      expect(GraphVersion.order(:version).last.change_list.first["exception_id"]).to eq(exception.id)
    end

    it "creates a departures exception for one direction" do
      expect_created(publish(add_exception(kind: "departures", direction: "northbound", departures: %w[05:00],
                                           start_date: "2026-11-30", end_date: "2026-11-30")))

      expect(ServiceScheduleException.first).to have_attributes(direction: "northbound", departure_times: %w[05:00])
    end

    it "accepts an exception on a line that has no regular schedule" do
      expect_created(publish(add_exception(line_id: "OPST_RAIL", kind: "window", start: "05:00", end: "09:00")))
    end

    it "refuses an unknown line, INTERCHANGE, and an unused direction" do
      expect_rejected(publish(add_exception(line_id: "NOPE")), field: "line_id")
      expect_rejected(publish(add_exception(line_id: "INTERCHANGE")), field: "line_id")
      expect_rejected(publish(add_exception(direction: "eastbound")), field: "direction")
    end

    it "refuses an exception that overlaps another one" do
      expect_created(publish(add_exception(direction: "northbound")))

      expect_rejected(publish(add_exception(start_date: "2027-01-03", end_date: "2027-01-05")), field: nil,
                                                                                                message: "overlaps")
      expect_rejected(publish(add_exception(direction: "northbound", start_date: "2026-12-25",
                                            end_date: "2026-12-25")), field: nil, message: "overlaps")
      expect_created(publish(add_exception(direction: "southbound", start_date: "2026-12-25",
                                           end_date: "2026-12-25")))
      expect_created(publish(add_exception(direction: "northbound", start_date: "2027-01-04",
                                           end_date: "2027-01-04")))
    end
  end

  describe "service_exception_update" do
    let(:exception) do
      expect_created(publish(add_exception(note: "Holiday")))
      ServiceScheduleException.find_by!(line_id: "OPST_ROAD")
    end

    it "changes only the fields that the change sends" do
      expect_created(publish({ type: "service_exception_update", exception_id: exception.id,
                               end_date: "2027-01-05", direction: "southbound" }))

      expect(exception.reload).to have_attributes(end_date: Date.new(2027, 1, 5), direction: "southbound",
                                                  start_date: Date.new(2026, 12, 24), note: "Holiday")
    end

    it "changes the kind with its times" do
      expect_created(publish({ type: "service_exception_update", exception_id: exception.id, kind: "window",
                               start: "05:00", end: "09:00" }))

      expect(exception.reload).to have_attributes(kind: "window", start_time: "05:00", end_time: "09:00")
    end

    it "refuses an unknown exception, an unused direction, and an overlap" do
      other = ServiceScheduleException.create!(line_id: "OPST_ROAD", start_date: "2027-02-01",
                                               end_date: "2027-02-02", kind: "no_service")
      expect_rejected(publish({ type: "service_exception_update", exception_id: SecureRandom.uuid, note: "x" }),
                      field: "exception_id", message: "was not found")
      expect_rejected(publish({ type: "service_exception_update", exception_id: "not-a-uuid", note: "x" }),
                      field: "exception_id")
      expect_rejected(publish({ type: "service_exception_update", exception_id: exception.id,
                                direction: "eastbound" }), field: "direction")
      expect_rejected(publish({ type: "service_exception_update", exception_id: other.id,
                                start_date: "2027-01-01", end_date: "2027-02-02" }), field: nil, message: "overlaps")
    end

    it "refuses a kind change that does not carry the times of the new kind" do
      expect_rejected(publish({ type: "service_exception_update", exception_id: exception.id, kind: "window" }),
                      field: "start")
    end

    it "changes departures to no_service and clears the times" do
      exception.update!(kind: "departures", departure_times: %w[05:00])
      expect_created(publish({ type: "service_exception_update", exception_id: exception.id, kind: "no_service" }))

      expect(exception.reload).to have_attributes(kind: "no_service", departure_times: [], start_time: nil)
    end

    it "changes departures to window and window to departures" do
      exception.update!(kind: "departures", departure_times: %w[05:00])
      expect_created(publish({ type: "service_exception_update", exception_id: exception.id, kind: "window",
                               start: "05:00", end: "09:00" }))
      expect(exception.reload).to have_attributes(kind: "window", start_time: "05:00", departure_times: [])

      expect_created(publish({ type: "service_exception_update", exception_id: exception.id, kind: "departures",
                               departures: %w[06:00] }))
      expect(exception.reload).to have_attributes(kind: "departures", start_time: nil, end_time: nil,
                                                  departure_times: %w[06:00])
    end
  end

  describe "service_exception_delete" do
    it "deletes the row and raises the version once" do
      expect_created(publish(add_exception))
      exception = ServiceScheduleException.first
      version = graph_version_now

      expect_created(publish({ type: "service_exception_delete", exception_id: exception.id }))

      expect(ServiceScheduleException.count).to eq(0)
      expect(graph_version_now).to eq(version + 1)
    end

    it "refuses an unknown exception" do
      expect_rejected(publish({ type: "service_exception_delete", exception_id: SecureRandom.uuid }),
                      field: "exception_id", message: "was not found")
    end
  end

  describe "validator refusals" do
    it "refuses an unknown direction word, an empty days list, an unknown day, and a repeated day" do
      expect_rejected(publish(set_schedule([weekday_departures], direction: "up")), field: "direction")
      expect_rejected(publish(set_schedule([weekday_departures.merge(days: [])])), field: "schedules", message: "days")
      expect_rejected(publish(set_schedule([weekday_departures.merge(days: %w[mon xyz])])), field: "schedules",
                                                                                            message: "days")
      expect_rejected(publish(set_schedule([weekday_departures.merge(days: %w[mon mon])])), field: "schedules",
                                                                                            message: "twice")
    end

    it "refuses a time that is not HH:mm" do
      %w[24:00 9:00 12:60 noon].each do |time|
        expect_rejected(publish(set_schedule([weekday_departures([time])])), field: "schedules", message: "HH:mm")
      end
      expect_rejected(publish(add_exception(kind: "window", start: "25:00", end: "26:00")), field: "start")
    end

    it "refuses a window without both times or with equal times" do
      window = { days: %w[mon], kind: "window" }
      expect_rejected(publish(set_schedule([window])), field: "schedules", message: "start and end")
      expect_rejected(publish(set_schedule([window.merge(start: "05:00")])), field: "schedules")
      expect_rejected(publish(set_schedule([window.merge(start: "05:00", end: "05:00")])), field: "schedules",
                                                                                           message: "differ")
      expect_rejected(publish(add_exception(kind: "window", start: "05:00", end: "05:00")), field: "end")
    end

    it "refuses a departures row with an empty or repeated list" do
      expect_rejected(publish(set_schedule([weekday_departures([])])), field: "schedules")
      expect_rejected(publish(set_schedule([weekday_departures(%w[05:00 05:00])])), field: "schedules",
                                                                                    message: "twice")
      expect_rejected(publish(set_schedule([{ days: %w[mon], kind: "departures" }])), field: "schedules")
    end

    it "refuses an empty schedules list and a list with two kinds" do
      expect_rejected(publish(set_schedule([])), field: "schedules", message: "service_schedule_clear")
      expect_rejected(publish(set_schedule([weekday_departures,
                                            { days: %w[sat], kind: "window", start: "05:00", end: "09:00" }])),
                      field: "schedules", message: "one kind")
    end

    it "refuses a schedule kind of no_service and an unknown item field" do
      expect_rejected(publish(set_schedule([{ days: %w[mon], kind: "no_service" }])), field: "schedules")
      expect_rejected(publish(set_schedule([weekday_departures.merge(color: "red")])), field: "schedules",
                                                                                       message: "color")
    end

    it "refuses a date that is not a real YYYY-MM-DD date and an end date before the start date" do
      ["2026-13-01", "2026-02-30", "12/24/2026", "2026-1-5"].each do |date|
        expect_rejected(publish(add_exception(start_date: date)), field: "start_date")
      end
      expect_rejected(publish(add_exception(start_date: "2027-01-03", end_date: "2026-12-24")), field: "end_date",
                                                                                                message: "before")
      expect_rejected(publish({ type: "service_exception_update", exception_id: "x", start_date: "2027-01-03",
                                end_date: "2026-12-24" }), field: "end_date")
    end

    it "refuses an exception of kind window or departures that has no times" do
      expect_rejected(publish(add_exception(kind: "window")), field: "start")
      expect_rejected(publish(add_exception(kind: "departures")), field: "departures")
      expect_rejected(publish(add_exception(kind: "no_service", start: "05:00", end: "09:00")), field: "kind")
      expect_rejected(publish(add_exception(kind: "holiday")), field: "kind")
    end

    it "refuses an update with no field to change" do
      expect_rejected(publish({ type: "service_exception_update", exception_id: "x" }), field: nil,
                                                                                        message: "at least one")
    end
  end

  describe "line deletion" do
    it "deletes the schedule rows and the exception rows with the line" do
      expect_created(publish(set_schedule([weekday_departures]).merge(line_id: "OPST_EMPTY")))
      expect_created(publish(add_exception(line_id: "OPST_EMPTY")))

      expect_created(publish({ type: "line_delete", line_id: "OPST_EMPTY" }))

      expect(ServiceSchedule.where(line_id: "OPST_EMPTY")).to be_empty
      expect(ServiceScheduleException.where(line_id: "OPST_EMPTY")).to be_empty
    end
  end
end
