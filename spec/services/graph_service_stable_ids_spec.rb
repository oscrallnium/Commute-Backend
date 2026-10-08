require "rails_helper"

# Stop ids never change. Order lives in `stations.sequence`, and a line edge id is
# `<from station>__<to station>`.
RSpec.describe "GraphService stable ids and stop sequence" do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }
  end

  let(:stops) do
    (1..4).map { |i| { "name" => "S#{i}", "lat" => 14.20 + i * 0.01, "lng" => 121.0 } }
  end

  def payload(line_id, pass)
    {
      "displayName" => "Test", "lineID" => line_id, "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [pass]
    }
  end

  def create_route(line_id, pass)
    result = GraphService.add_route(payload(line_id, pass))
    raise "fixture failed: #{result.errors.inspect}" unless result.success?
  end

  def order_of(line_id) = Station.where(line: line_id).order(:sequence).pluck(:station_id)

  after { %w[STBL STBLOOP STBLEG STBLRM OLD.STBL_LINE].each { |l| GraphService.delete_route(l) } }

  describe "add_route" do
    it "creates _S<n> stations with sequence and <from>__<to> edges for a directional pass" do
      create_route("STBL", { "direction" => "northbound", "stops" => stops })

      expect(order_of("STBL")).to eq(%w[STBL_NB_S1 STBL_NB_S2 STBL_NB_S3 STBL_NB_S4])
      expect(Station.where(line: "STBL").order(:sequence).pluck(:sequence)).to eq([1, 2, 3, 4])
      expect(Edge.where(line: "STBL").pluck(:edge_id)).to match_array(
        %w[STBL_NB_S1__STBL_NB_S2 STBL_NB_S2__STBL_NB_S3 STBL_NB_S3__STBL_NB_S4]
      )
    end

    it "names the closing edge of a loop <last>__<first>" do
      create_route("STBLOOP", { "bidirectional" => false, "closesLoop" => true, "stops" => stops })

      expect(order_of("STBLOOP")).to eq(%w[STBLOOP_S1 STBLOOP_S2 STBLOOP_S3 STBLOOP_S4])
      expect(Edge.where(line: "STBLOOP").pluck(:edge_id)).to include("STBLOOP_S4__STBLOOP_S1")
      expect(Edge.where(line: "STBLOOP").count).to eq(4)
    end
  end

  describe "the per-line stop counter" do
    it "gives the chains of one line different numbers" do
      create_route("STBL", { "direction" => "northbound", "stops" => stops })
      create_route("STBL", { "direction" => "southbound", "stops" => stops })
      result = GraphService.insert_stop("referenceStationId" => "STBL_SB_S5", "position" => "after",
                                        "name" => "New", "lat" => 14.215, "lng" => 121.0)

      expect(order_of("STBL").map { |id| id[/\d+\z/].to_i }.sort).to eq((1..9).to_a)
      expect(result.data[:station_id]).to eq("STBL_SB_S9")
      expect(Line.find("STBL").last_stop_number).to eq(9)
    end
  end

  describe "insert_stop" do
    before { create_route("STBL", { "bidirectional" => false, "stops" => stops }) }

    it "keeps every id except the split edge and orders the chain" do
      stations_before = Station.where(line: "STBL").pluck(:station_id)
      edges_before = Edge.where(line: "STBL").pluck(:edge_id)

      result = GraphService.insert_stop("referenceStationId" => "STBL_S2", "position" => "after",
                                        "name" => "New", "lat" => 14.235, "lng" => 121.0)

      expect(result.data[:station_id]).to eq("STBL_S5")
      expect(order_of("STBL")).to eq(%w[STBL_S1 STBL_S2 STBL_S5 STBL_S3 STBL_S4])
      expect(Station.where(line: "STBL").order(:sequence).pluck(:sequence)).to eq([1, 2, 3, 4, 5])
      expect(Station.where(line: "STBL").pluck(:station_id)).to include(*stations_before)
      expect(Edge.where(line: "STBL").pluck(:edge_id)).to match_array(
        (edges_before - ["STBL_S2__STBL_S3"]) + %w[STBL_S2__STBL_S5 STBL_S5__STBL_S3]
      )
    end

    it "marks only the first and last stop as terminals after a head insert" do
      GraphService.insert_stop("referenceStationId" => "STBL_S1", "position" => "before",
                               "name" => "Head", "lat" => 14.205, "lng" => 121.0)

      expect(order_of("STBL").first).to eq("STBL_S5")
      expect(Station.where(line: "STBL", is_terminal: true).pluck(:station_id)).to match_array(%w[STBL_S5 STBL_S4])
    end

    it "creates <chain>_S1 in a legacy _STOP<n> chain" do
      Station.where(line: "STBL").each { |s| s.update!(station_id: s.station_id.sub("_S", "_STOP")) }
      Edge.where(line: "STBL").destroy_all
      Line.find("STBL").update!(last_stop_number: 0)
      (1..3).each do |i|
        Edge.create!(edge_id: "STBL_SEG#{i}", from_station: "STBL_STOP#{i}", to_station: "STBL_STOP#{i + 1}",
                     mode: "jeepney", line: "STBL", travel_time_minutes: 2, distance_km: 1, bidirectional: false)
      end

      result = GraphService.insert_stop("referenceStationId" => "STBL_STOP2", "position" => "after",
                                        "name" => "New", "lat" => 14.235, "lng" => 121.0)

      expect(result.data[:station_id]).to eq("STBL_S1")
      expect(order_of("STBL")).to eq(%w[STBL_STOP1 STBL_STOP2 STBL_S1 STBL_STOP3 STBL_STOP4])
      expect(Station.find("STBL_S1").sequence).to eq(3)
      expect(Edge.where(line: "STBL").pluck(:edge_id)).to match_array(
        %w[STBL_SEG1 STBL_SEG3 STBL_STOP2__STBL_S1 STBL_S1__STBL_STOP3]
      )
    end
  end

  describe "remove_stop" do
    before { create_route("STBLRM", { "bidirectional" => false, "stops" => stops }) }

    it "keeps every other id, merges the edges, and closes the sequence gap" do
      result = GraphService.remove_stop("STBLRM_S2")

      expect(result.success?).to be true
      expect(order_of("STBLRM")).to eq(%w[STBLRM_S1 STBLRM_S3 STBLRM_S4])
      expect(Station.where(line: "STBLRM").order(:sequence).pluck(:sequence)).to eq([1, 2, 3])
      expect(Edge.where(line: "STBLRM").pluck(:edge_id)).to match_array(
        %w[STBLRM_S1__STBLRM_S3 STBLRM_S3__STBLRM_S4]
      )
    end

    it "deletes an interchange edge that points at the removed stop" do
      Edge.create!(edge_id: "X__STBLRM_S2__ELSEWHERE", from_station: "STBLRM_S2", to_station: "ELSEWHERE",
                   mode: "jeepney", line: "INTERCHANGE", travel_time_minutes: 5, distance_km: 0.1)

      GraphService.remove_stop("STBLRM_S2")

      expect(Edge.exists?("X__STBLRM_S2__ELSEWHERE")).to be false
    end

    it "never reuses a number: inserting after the highest stop is removed gives a new one" do
      GraphService.remove_stop("STBLRM_S4")
      result = GraphService.insert_stop("referenceStationId" => "STBLRM_S3", "position" => "after",
                                        "name" => "New", "lat" => 14.255, "lng" => 121.0)

      expect(result.data[:station_id]).to eq("STBLRM_S5")
      expect(Line.find("STBLRM").last_stop_number).to eq(5)
    end
  end

  describe "line id validation" do
    it "rejects a new line id with a hyphen or a dot" do
      %w[BAD-LINE BAD.LINE].each do |line_id|
        result = GraphService.add_route(payload(line_id, { "stops" => stops }))
        expect(result.success?).to be false
        expect(result.errors.map { |e| e[:field] }).to include("lineID")
      end
    end

    it "rejects a new line id that starts with a digit or has a double underscore" do
      %w[3LINE BAD__LINE].each do |line_id|
        expect(GraphService.add_route(payload(line_id, { "stops" => stops })).success?).to be false
      end
    end

    it "adds a direction to an existing legacy line id that has a dot" do
      Station.create!(station_id: "OLD.STBL_LINE_NB_STOP1", name: "Old", line: "OLD.STBL_LINE", type: "jeepney",
                      lat: 14.2, lng: 121.0)
      Edge.create!(edge_id: "OLD.STBL_LINE_NB_SEG1", from_station: "OLD.STBL_LINE_NB_STOP1",
                   to_station: "OLD.STBL_LINE_NB_STOP2", mode: "jeepney", line: "OLD.STBL_LINE",
                   travel_time_minutes: 2, distance_km: 1, bidirectional: false, direction: "northbound")

      result = GraphService.add_route(payload("OLD.STBL_LINE", { "direction" => "southbound", "stops" => stops }))

      expect(result.success?).to be true
      expect(Station.exists?("OLD.STBL_LINE_SB_S1")).to be true
    end
  end

  describe "graph JSON" do
    around do |example|
      created = GraphMeta.none? ? GraphMeta.create! : nil
      example.run
    ensure
      created&.destroy
    end

    it "carries sequence on a station that has one and omits it otherwise" do
      create_route("STBLEG", { "bidirectional" => false, "stops" => stops })
      Station.create!(station_id: "STBLEG_NAMED", name: "Named", line: "STBLEG", type: "jeepney", lat: 14.2, lng: 121.0)

      graph = GraphService.assemble_graph
      by_id = graph[:stations].to_h { |s| [s[:id], s] }

      expect(by_id["STBLEG_S3"][:sequence]).to eq(3)
      expect(by_id["STBLEG_NAMED"]).not_to have_key(:sequence)
      expect(Station.find("STBLEG_S3").as_api_json[:sequence]).to eq(3)
      expect(Station.find("STBLEG_NAMED").as_api_json).not_to have_key(:sequence)
    end
  end
end
