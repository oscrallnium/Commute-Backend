require "rails_helper"

# A bus line with two directions on one `lines` row and service schedules keeps its
# directions, sequences, terminals, and schedule rows when an admin adds or removes a stop.
RSpec.describe "GraphService stop editing on a scheduled line" do
  let(:line_id) { "ZZ_SCHED_BUS" }
  let(:sb_ids) { %w[ZZ_SCHED_BUS_SB_S1 ZZ_SCHED_BUS_SB_S2] }
  let(:nb_ids) { %w[ZZ_SCHED_BUS_NB_S3 ZZ_SCHED_BUS_NB_S4] }
  let(:today) { Time.find_zone("Asia/Manila").today }

  before do
    GraphMeta.first || GraphMeta.create!
    TransportMode.find_or_create_by!(id: "bus") do |m|
      m.display_name = "Bus"
      m.mk_directions_type = "automobile"
    end
    Line.create!(id: line_id, display_name: "Scheduled Bus", mode: "bus", direction: "both", last_stop_number: 4)
    build_chain(sb_ids, "southbound", lat_start: 14.70, lat_step: -0.10)
    build_chain(nb_ids, "northbound", lat_start: 14.60, lat_step: 0.10)
    ServiceSchedule.create!(line_id: line_id, direction: "southbound", days: %w[mon tue], kind: "departures",
                            departure_times: %w[05:00 13:00])
    ServiceSchedule.create!(line_id: line_id, direction: "northbound", days: %w[sat], kind: "window",
                            start_time: "18:00", end_time: "22:00")
    ServiceScheduleException.create!(line_id: line_id, start_date: today + 1, end_date: today + 3,
                                     kind: "no_service", note: "Holiday")
  end

  def build_chain(ids, direction, lat_start:, lat_step:)
    ids.each_with_index do |id, i|
      Station.create!(station_id: id, name: id, line: line_id, type: "bus", sequence: i + 1, is_terminal: true,
                      lat: lat_start + (i * lat_step), lng: 121.0)
    end
    Edge.create!(edge_id: "#{ids[0]}__#{ids[1]}", from_station: ids[0], to_station: ids[1], mode: "bus",
                 line: line_id, travel_time_minutes: 10, distance_km: 5, bidirectional: false,
                 direction: direction, polyline_coordinates: [])
  end

  def insert(ref, position, lat)
    GraphService.insert_stop("referenceStationId" => ref, "position" => position,
                             "name" => "New #{ref} #{position}", "lat" => lat, "lng" => 121.0)
  end

  def chain(prefix)
    Station.where(line: line_id).where("station_id LIKE ?", "#{prefix}%").order(:sequence)
  end

  def version = GraphMeta.first.version

  def schedule_snapshot
    [ServiceSchedule.order(:id).map(&:attributes), ServiceScheduleException.order(:id).map(&:attributes)]
  end

  def edges_from(direction)
    Edge.where(line: line_id, direction: direction)
  end

  def expect_untouched_northbound
    expect(chain("ZZ_SCHED_BUS_NB").map { |s| [s.station_id, s.sequence, s.is_terminal] })
      .to eq([["ZZ_SCHED_BUS_NB_S3", 1, true], ["ZZ_SCHED_BUS_NB_S4", 2, true]])
    expect(edges_from("northbound").map(&:edge_id)).to eq(["ZZ_SCHED_BUS_NB_S3__ZZ_SCHED_BUS_NB_S4"])
  end

  def expect_one_way_southbound_edges
    edges = edges_from("southbound")
    expect(edges.map(&:bidirectional)).to all(be false)
    expect(Edge.where(line: line_id).count).to eq(edges.count + 1)
  end

  it "inserts a middle stop on the southbound chain" do
    before_schedules = schedule_snapshot
    before_version = version

    result = insert("ZZ_SCHED_BUS_SB_S1", "after", 14.65)

    expect(result.success?).to be true
    expect(result.data[:station_id]).to eq("ZZ_SCHED_BUS_SB_S5")
    expect(Line.find(line_id).last_stop_number).to eq(5)
    expect(chain("ZZ_SCHED_BUS_SB").map { |s| [s.station_id, s.sequence, s.is_terminal] }).to eq(
      [["ZZ_SCHED_BUS_SB_S1", 1, true], ["ZZ_SCHED_BUS_SB_S5", 2, false], ["ZZ_SCHED_BUS_SB_S2", 3, true]]
    )
    expect(edges_from("southbound").map(&:edge_id)).to contain_exactly(
      "ZZ_SCHED_BUS_SB_S1__ZZ_SCHED_BUS_SB_S5", "ZZ_SCHED_BUS_SB_S5__ZZ_SCHED_BUS_SB_S2"
    )
    expect_one_way_southbound_edges
    expect_untouched_northbound
    expect(schedule_snapshot).to eq(before_schedules)
    expect(version).to be > before_version
  end

  it "inserts a tail stop and a head stop on the southbound chain" do
    before_schedules = schedule_snapshot
    v0 = version

    expect(insert("ZZ_SCHED_BUS_SB_S2", "after", 14.55).success?).to be true
    v1 = version
    expect(chain("ZZ_SCHED_BUS_SB").map { |s| [s.station_id, s.sequence, s.is_terminal] }).to eq(
      [["ZZ_SCHED_BUS_SB_S1", 1, true], ["ZZ_SCHED_BUS_SB_S2", 2, false], ["ZZ_SCHED_BUS_SB_S5", 3, true]]
    )
    expect(edges_from("southbound").count).to eq(2)
    expect_one_way_southbound_edges
    expect_untouched_northbound

    expect(insert("ZZ_SCHED_BUS_SB_S1", "before", 14.75).success?).to be true
    expect(chain("ZZ_SCHED_BUS_SB").map { |s| [s.station_id, s.sequence, s.is_terminal] }).to eq(
      [["ZZ_SCHED_BUS_SB_S6", 1, true], ["ZZ_SCHED_BUS_SB_S1", 2, false],
       ["ZZ_SCHED_BUS_SB_S2", 3, false], ["ZZ_SCHED_BUS_SB_S5", 4, true]]
    )
    expect(edges_from("southbound").count).to eq(3)
    expect_one_way_southbound_edges
    expect_untouched_northbound
    expect(Line.find(line_id).last_stop_number).to eq(6)
    expect(schedule_snapshot).to eq(before_schedules)
    expect(v1).to be > v0
    expect(version).to be > v1
  end

  it "restores one southbound edge when the inserted stop leaves" do
    before_schedules = schedule_snapshot
    inserted = insert("ZZ_SCHED_BUS_SB_S1", "after", 14.65).data[:station_id]
    before_removal = version

    expect(GraphService.remove_stop(inserted).success?).to be true

    expect(version).to be > before_removal
    edges = edges_from("southbound")
    expect(edges.map(&:edge_id)).to eq(["ZZ_SCHED_BUS_SB_S1__ZZ_SCHED_BUS_SB_S2"])
    expect(edges.first.bidirectional).to be false
    expect(chain("ZZ_SCHED_BUS_SB").map { |s| [s.station_id, s.sequence, s.is_terminal] }).to eq(
      [["ZZ_SCHED_BUS_SB_S1", 1, true], ["ZZ_SCHED_BUS_SB_S2", 2, true]]
    )
    expect_untouched_northbound
    expect(schedule_snapshot).to eq(before_schedules)
  end

  it "still lists the schedules and exceptions in the public graph after inserts" do
    insert("ZZ_SCHED_BUS_SB_S1", "after", 14.65)
    insert("ZZ_SCHED_BUS_NB_S4", "after", 14.95)

    graph = GraphService.assemble_graph.deep_stringify_keys

    expect(graph["serviceSchedules"][line_id].map { |row| row["direction"] })
      .to contain_exactly("southbound", "northbound")
    expect(graph["serviceScheduleExceptions"][line_id].map { |row| row["kind"] }).to eq(["no_service"])
  end
end
