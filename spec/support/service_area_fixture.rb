# Helpers for the service area publish specs. Every ID starts with SAPB.
module ServiceAreaFixture
  SAPB_BOUNDARY = [{ lat: 14.50, lng: 121.00 }, { lat: 14.50, lng: 121.02 },
                   { lat: 14.52, lng: 121.02 }, { lat: 14.52, lng: 121.00 }].freeze

  def build_area_mode!
    mode = TransportMode.find_or_create_by!(id: "tricycle") do |m|
      m.display_name = "Tricycle"
      m.mk_directions_type = "automobile"
    end
    mode.update!(service_shape: "area")
  end

  def service_area_change(**overrides)
    { type: "service_area_add", line_id: "SAPB_ZONE", name: "Sapb Zone", mode: "tricycle",
      boundary: SAPB_BOUNDARY,
      terminals: [{ name: "Plaza Gate", lat: 14.51, lng: 121.01 }, { name: "Market", lat: 14.515, lng: 121.005 }],
      base_fare: 15, base_km: 1, fare_per_km: 5, accepted_payments: %w[cash], open: "05:00", close: "21:00" }
      .merge(overrides)
  end
end

RSpec.configure do |config|
  config.include ServiceAreaFixture
end
