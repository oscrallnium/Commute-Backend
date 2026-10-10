require "rails_helper"

RSpec.describe "GraphService line color" do
  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }
  end

  before { GraphMeta.first || GraphMeta.create! }

  after { GraphService.delete_route("CLRT") }

  def payload(extra = {})
    {
      "displayName" => "Color Test", "lineID" => "CLRT", "mode" => "jeepney",
      "openTime" => "05:00", "closeTime" => "22:00",
      "baseFare" => 13.0, "farePerKm" => 1.8, "acceptedPayments" => ["cash"],
      "isAirConditioned" => false, "crowdFactor" => 0.7, "reliability" => 0.65,
      "passes" => [{ "stops" => [{ "name" => "A", "lat" => 14.20, "lng" => 121.0 },
                                 { "name" => "B", "lat" => 14.21, "lng" => 121.0 }] }]
    }.merge(extra)
  end

  def graph_line = GraphService.new.assemble_graph[:lines]["CLRT"]

  it "stores colorHex from add_route and exposes it in the graph" do
    result = GraphService.add_route(payload("colorHex" => "#a1b2c3"))

    expect(result.success?).to be(true)
    expect(Line.find("CLRT").color_hex).to eq("#A1B2C3")
    expect(graph_line[:colorHex]).to eq("#A1B2C3")
  end

  it "omits the colorHex key when the line has no color" do
    expect(GraphService.add_route(payload).success?).to be(true)

    expect(Line.find("CLRT").color_hex).to be_nil
    expect(graph_line).not_to have_key(:colorHex)
  end

  it "rejects an invalid colorHex and writes nothing" do
    result = GraphService.add_route(payload("colorHex" => "red"))

    expect(result.success?).to be(false)
    expect(result.errors.map { |e| e[:field] }).to include("colorHex")
    expect(Line.exists?("CLRT")).to be(false)
  end
end
