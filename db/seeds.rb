require "json"

graph = JSON.parse(
  File.read(Rails.root.join("data/transit_graph_v3.json"))
)

# ── Admin user ────────────────────────────────────────────────────────────────
if User.find_by(email: "admin@commutebeh.ph").nil?
  User.create!(
    email: "admin@commutebeh.ph",
    password: "Admin1234!",
    password_confirmation: "Admin1234!",
    display_name: "CommuteBeh Admin",
    role: :admin
  )
  puts "Admin user created: admin@commutebeh.ph / Admin1234!"
else
  puts "Admin user already exists."
end

# ── Graph meta ────────────────────────────────────────────────────────────────
GraphMeta.delete_all
GraphMeta.create!(
  version: 1,
  last_modified: Time.current,
  schema_version: graph.dig("metadata", "schemaVersion") || "3.0.0",
  region: graph.dig("metadata", "region") || "Metro Manila, Philippines",
  currency: graph.dig("metadata", "currency") || "PHP"
)
puts "GraphMeta seeded."

# ── Transport modes ───────────────────────────────────────────────────────────
TransportMode.delete_all
graph["transportModes"].each_with_index do |(id, m), i|
  TransportMode.create!(
    id: id,
    display_name: m["displayName"],
    plural_name: m["pluralName"] || "",
    sf_symbol: m["sfSymbol"]               || "",
    color_hex: m["colorHex"]               || "#000000",
    map_line_width_pt: m["mapLineWidthPt"] || 4.0,
    map_line_dash: m["mapLineDash"] || [],
    mk_directions_type: m["mkDirectionsTransportType"] || "transit",
    is_user_selectable: m.fetch("isUserSelectable", true),
    is_always_allowed: m.fetch("isAlwaysAllowed", false),
    lines: m["lines"] || [],
    default_accepted_payments: m["defaultAcceptedPayments"] || [],
    notes: m["notes"] || "",
    position: i,
    extra: {}
  )
end
puts "TransportModes seeded: #{TransportMode.count}"

# ── Payment methods ───────────────────────────────────────────────────────────
PaymentMethod.delete_all
graph["paymentMethods"].each do |id, p|
  PaymentMethod.create!(
    id: id,
    display_name: p["displayName"],
    sf_symbol: p["sfSymbol"]    || "",
    color_hex: p["colorHex"]    || "#000000",
    is_default: p.fetch("isDefault", false),
    accepted_by_modes: p["acceptedByModes"] || [],
    notes: p["notes"] || ""
  )
end
puts "PaymentMethods seeded: #{PaymentMethod.count}"

# ── Peak hour config ──────────────────────────────────────────────────────────
PeakHourConfig.delete_all
PeakHourConfig.create!(data: graph["peakHourMultipliers"] || {})
puts "PeakHourConfig seeded."

# ── Fare matrix ───────────────────────────────────────────────────────────────
FareMatrix.delete_all
graph["fareMatrix"].each do |line_name, data|
  FareMatrix.create!(
    line_name: line_name,
    type: data["type"] || "flat",
    data: data
  )
end
puts "FareMatrix seeded: #{FareMatrix.count} lines"

# ── Stations ──────────────────────────────────────────────────────────────────
Station.delete_all
graph["stations"].each do |s|
  Station.create!(
    station_id: s["id"],
    name: s["name"],
    short_name: s["shortName"] || "",
    line: s["line"],
    type: s["type"],
    lat: s.dig("coordinates", "lat"),
    lng: s.dig("coordinates", "lng"),
    is_terminal: s.fetch("isTerminal", false),
    is_interchange: s.fetch("isInterchange", false),
    amenities: s["amenities"] || [],
    open_time: s.dig("operatingHours", "open") || "05:00",
    close_time: s.dig("operatingHours", "close") || "23:00"
  )
end
puts "Stations seeded: #{Station.count}"

# ── Edges ─────────────────────────────────────────────────────────────────────
Edge.delete_all
graph["edges"].each do |e|
  Edge.create!(
    edge_id: e["id"],
    from_station: e["from"],
    to_station: e["to"],
    mode: e["mode"],
    line: e["line"],
    travel_time_minutes: e["travelTimeMinutes"],
    distance_km: e["distanceKm"],
    base_fare: e["baseFare"] || 0,
    fare_per_km: e["farePerKm"] || 0,
    accepted_payments: e["acceptedPayments"] || [],
    is_air_conditioned: e.fetch("isAirConditioned", false),
    crowd_factor: e["crowdFactor"] || 0.5,
    reliability: e["reliability"] || 0.9,
    bidirectional: e.fetch("bidirectional", true),
    direction: e["direction"],
    polyline_coordinates: e["polylineCoordinates"] || [],
    mk_directions_transport_type: e["mkDirectionsTransportType"] || "transit"
  )
end
puts "Edges seeded: #{Edge.count}"

puts "\nSeed complete."
