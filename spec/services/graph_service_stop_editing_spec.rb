require "rails_helper"

# Inserting or removing a stop used to rebuild the affected edges with a hardcoded
# `bidirectional: true, direction: nil`, so editing a one-way route silently made part of
# it two-way — and on a directional chain dropped the direction label. The client
# synthesises a reverse edge for anything bidirectional, so that stretch could then be
# routed backwards, sending a rider to a stop that only serves the other direction.
RSpec.describe "GraphService stop editing preserves directionality" do
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

  def create_route(line_id, pass)
    result = GraphService.add_route({
      "displayName" => "Test", "lineID" => line_id, "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [pass]
    })
    raise "fixture failed: #{result.errors.inspect}" unless result.success?
  end

  def edges_for(prefix)
    Edge.where("edge_id LIKE ?", "#{prefix}\\_SEG%").order(:edge_id)
  end

  after { %w[ONEWAY DIRECTIONAL TWOWAY].each { |l| GraphService.delete_route(l) } }

  describe "a one-way, direction-less route" do
    before { create_route("ONEWAY", { "bidirectional" => false, "stops" => stops }) }

    it "stays one-way after inserting a stop mid-chain" do
      result = GraphService.insert_stop(
        "referenceStationId" => "ONEWAY_STOP2", "position" => "after",
        "name" => "New", "lat" => 14.235, "lng" => 121.0
      )
      expect(result.success?).to be true
      expect(edges_for("ONEWAY").map(&:bidirectional)).to all(be false)
    end

    it "stays one-way after inserting a stop at the head" do
      GraphService.insert_stop(
        "referenceStationId" => "ONEWAY_STOP1", "position" => "before",
        "name" => "New Head", "lat" => 14.205, "lng" => 121.0
      )
      expect(edges_for("ONEWAY").map(&:bidirectional)).to all(be false)
    end

    it "stays one-way after inserting a stop at the tail" do
      GraphService.insert_stop(
        "referenceStationId" => "ONEWAY_STOP4", "position" => "after",
        "name" => "New Tail", "lat" => 14.255, "lng" => 121.0
      )
      expect(edges_for("ONEWAY").map(&:bidirectional)).to all(be false)
    end

    it "stays one-way after removing a stop" do
      expect(GraphService.remove_stop("ONEWAY_STOP2").success?).to be true
      expect(edges_for("ONEWAY").map(&:bidirectional)).to all(be false)
    end
  end

  describe "a directional (northbound) chain" do
    before { create_route("DIRECTIONAL", { "direction" => "northbound", "stops" => stops }) }

    it "keeps every edge one-way and northbound after an insert" do
      result = GraphService.insert_stop(
        "referenceStationId" => "DIRECTIONAL_NB_STOP2", "position" => "after",
        "name" => "New", "lat" => 14.235, "lng" => 121.0
      )
      expect(result.success?).to be true

      edges = edges_for("DIRECTIONAL_NB")
      expect(edges.map(&:bidirectional)).to all(be false)
      expect(edges.map(&:direction)).to all(eq("northbound"))
    end

    it "keeps the direction after removing a stop" do
      GraphService.remove_stop("DIRECTIONAL_NB_STOP2")
      edges = edges_for("DIRECTIONAL_NB")
      expect(edges.map(&:bidirectional)).to all(be false)
      expect(edges.map(&:direction)).to all(eq("northbound"))
    end
  end

  describe "a two-way route" do
    before { create_route("TWOWAY", { "stops" => stops }) }

    it "stays two-way after an insert — inheritance, not a blanket one-way rule" do
      GraphService.insert_stop(
        "referenceStationId" => "TWOWAY_STOP2", "position" => "after",
        "name" => "New", "lat" => 14.235, "lng" => 121.0
      )
      expect(edges_for("TWOWAY").map(&:bidirectional)).to all(be true)
    end
  end
end
