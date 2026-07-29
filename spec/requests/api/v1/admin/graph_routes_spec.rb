require "rails_helper"

# Verifies the payload the iOS Loop Creator will send once it declares one-wayness
# explicitly, exercised over HTTP so it goes through the controller's
# ActionController::Parameters → to_unsafe_h conversion rather than the plain
# Ruby hashes a service-level test would use. That conversion is the part worth
# proving: `bidirectional: false` must survive it as a real `false` and not be
# flattened into "absent", which would silently restore the legacy
# `bidirectional: direction.nil?` default and hand back two-way edges.
RSpec.describe "POST /api/v1/admin/graph/routes", type: :request do
  let(:admin) do
    User.create!(
      email: "admin_#{SecureRandom.hex(4)}@test.com",
      password: "Password1!",
      display_name: "Admin",
      role: :admin
    )
  end

  before do
    TransportMode.find_or_create_by!(id: "jeepney") do |m|
      m.display_name = "Jeepney"
      m.mk_directions_type = "automobile"
    end
    PaymentMethod.find_or_create_by!(id: "cash") { |p| p.display_name = "Cash" }
  end

  # An out-and-back circuit: out along a corridor, around a block, back down the
  # same corridor stopping on the other side. The UPLB Kaliwa/Kanan shape.
  def circuit_stops
    [
      { name: "Terminal",              lat: 14.2100, lng: 121.1650 },
      { name: "Junction (outbound)",   lat: 14.2130, lng: 121.1680 },
      { name: "Gate (entering)",       lat: 14.2160, lng: 121.1700 },
      { name: "Campus Stop",           lat: 14.2180, lng: 121.1720 },
      { name: "Gate (leaving)",        lat: 14.2161, lng: 121.1701 },
      { name: "Junction (inbound)",    lat: 14.2131, lng: 121.1681 },
      { name: "Terminal",              lat: 14.2100, lng: 121.1650 }
    ]
  end

  def post_route(line_id:, pass:)
    post "/api/v1/admin/graph/routes",
         params: {
           displayName: "Test #{line_id}", lineID: line_id, mode: "jeepney",
           openTime: "05:00", closeTime: "22:00",
           baseFare: 13.0, farePerKm: 1.8, acceptedPayments: ["cash"],
           isAirConditioned: false, crowdFactor: 0.7, reliability: 0.65,
           passes: [pass]
         }.to_json,
         headers: auth_headers_for(admin).merge("Content-Type" => "application/json")
  end

  after do
    %w[IOS_ONEWAY IOS_LEGACY IOS_TWOWAY IOS_BAD IOS_DIR].each { |l| GraphService.delete_route(l) }
  end

  context "the new iOS payload: direction-less and explicitly one-way" do
    before do
      post_route(line_id: "IOS_ONEWAY",
                 pass: { direction: nil, bidirectional: false,
                         isRoadSnapped: false, closesLoop: false, stops: circuit_stops })
    end

    it "is accepted" do
      expect(response).to have_http_status(:created)
    end

    it "writes one-way edges — `false` survived the params round-trip" do
      edges = Edge.where(line: "IOS_ONEWAY")
      expect(edges).to be_present
      expect(edges.map(&:bidirectional)).to all(be false)
    end

    it "leaves the direction unset rather than inventing one to get one-wayness" do
      expect(Edge.where(line: "IOS_ONEWAY").map(&:direction)).to all(be_nil)
    end

    it "keeps station ids unnamespaced and in travel order" do
      ids = Station.where(line: "IOS_ONEWAY").map(&:station_id).sort_by { |i| i[/\d+\z/].to_i }
      expect(ids).to eq((1..7).map { |n| "IOS_ONEWAY_STOP#{n}" })
    end

    it "keeps the chain open — n stops gives n-1 edges" do
      expect(Edge.where(line: "IOS_ONEWAY").count).to eq(circuit_stops.length - 1)
    end

    it "stores the outbound and return stops as distinct rows at distinct coordinates" do
      outbound = Station.find_by(station_id: "IOS_ONEWAY_STOP2")
      inbound  = Station.find_by(station_id: "IOS_ONEWAY_STOP6")
      expect(outbound.name).to eq("Junction (outbound)")
      expect(inbound.name).to eq("Junction (inbound)")
      expect(inbound.lat).not_to eq(outbound.lat)
    end
  end

  context "the current iOS payload: no bidirectional key at all" do
    it "still defaults to two-way, so existing clients are unaffected" do
      post_route(line_id: "IOS_LEGACY",
                 pass: { isRoadSnapped: false, stops: circuit_stops })
      expect(response).to have_http_status(:created)
      expect(Edge.where(line: "IOS_LEGACY").map(&:bidirectional)).to all(be true)
    end
  end

  context "explicit bidirectional: true" do
    it "is honoured for a direction-less pass" do
      post_route(line_id: "IOS_TWOWAY",
                 pass: { bidirectional: true, isRoadSnapped: false, stops: circuit_stops })
      expect(response).to have_http_status(:created)
      expect(Edge.where(line: "IOS_TWOWAY").map(&:bidirectional)).to all(be true)
    end
  end

  context "a directional pass" do
    it "stays one-way and namespaced" do
      post_route(line_id: "IOS_DIR",
                 pass: { direction: "northbound", isRoadSnapped: false, stops: circuit_stops })
      expect(response).to have_http_status(:created)
      edges = Edge.where(line: "IOS_DIR")
      expect(edges.map(&:bidirectional)).to all(be false)
      expect(edges.first.edge_id).to start_with("IOS_DIR_NB_SEG")
    end

    it "is rejected when also marked bidirectional, writing nothing" do
      post_route(line_id: "IOS_BAD",
                 pass: { direction: "northbound", bidirectional: true,
                         isRoadSnapped: false, stops: circuit_stops })
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"])
        .to include(a_string_matching(/can't be bidirectional/))
      expect(Station.where(line: "IOS_BAD")).to be_empty
    end
  end
end
