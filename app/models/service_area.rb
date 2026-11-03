class ServiceArea < ApplicationRecord
  MIN_VERTICES = 3
  MAX_VERTICES = 200

  self.primary_key = "line_id"
  self.table_name  = "service_areas"

  belongs_to :line, primary_key: :id, inverse_of: :service_area

  before_validation :normalize_boundary

  validate :boundary_is_a_valid_ring
  validates :base_fare, :base_km, :fare_per_km, :wait_minutes,
            numericality: { greater_than_or_equal_to: 0 }
  validates :special_trip_fare, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :speed_kmh, numericality: { greater_than: 0 }
  validates :detour_factor, numericality: { greater_than_or_equal_to: 1 }
  validates :accepted_payments, presence: { message: "must list at least one payment method" }

  # Ray casting over the open ring. Latitude is y and longitude is x.
  def contains?(lat, lng)
    inside = false
    ring = boundary
    ring.each_with_index do |point, index|
      other = ring[index - 1]
      next if (point["lat"] > lat) == (other["lat"] > lat)

      crossing_lng = ((other["lng"] - point["lng"]) * (lat - point["lat"]) /
                     (other["lat"] - point["lat"])) + point["lng"]
      inside = !inside if lng < crossing_lng
    end
    inside
  end

  def as_graph_json(terminal_ids:)
    json = {
      line: line_id,
      boundary: boundary.map { |point| { lat: point["lat"], lng: point["lng"] } },
      terminalIds: terminal_ids,
      baseFare: base_fare.to_f,
      baseKm: base_km.to_f,
      farePerKm: fare_per_km.to_f,
      speedKmh: speed_kmh.to_f,
      detourFactor: detour_factor.to_f,
      waitMinutes: wait_minutes.to_f,
      acceptedPayments: accepted_payments
    }
    json[:specialTripFare] = special_trip_fare.to_f unless special_trip_fare.nil?
    json
  end

  private

  def normalize_boundary
    return unless boundary.is_a?(Array)

    points = boundary.map { |point| normalize_point(point) }
    points.pop if points.length > 1 && points.first && points.first == points.last
    self.boundary = points
  end

  def normalize_point(point)
    return point unless point.respond_to?(:to_h)

    values = point.to_h.transform_keys(&:to_s)
    lat = Float(values["lat"], exception: false)
    lng = Float(values["lng"], exception: false)
    return point if lat.nil? || lng.nil?

    { "lat" => lat, "lng" => lng }
  end

  def boundary_is_a_valid_ring
    unless boundary.is_a?(Array) && boundary.all? { |point| valid_point?(point) }
      return errors.add(:boundary, "must be a list of points that each have a numeric lat and lng")
    end
    return errors.add(:boundary, "must have at least #{MIN_VERTICES} points") if boundary.length < MIN_VERTICES
    return errors.add(:boundary, "must have at most #{MAX_VERTICES} points") if boundary.length > MAX_VERTICES
    return errors.add(:boundary, "has a point outside the valid latitude or longitude range") unless coordinates_in_range?
    return errors.add(:boundary, "must not repeat a point twice in a row") if repeated_consecutive_point?

    errors.add(:boundary, "must not cross itself") if self_intersecting?
  end

  def valid_point?(point)
    point.is_a?(Hash) && point["lat"].is_a?(Float) && point["lng"].is_a?(Float)
  end

  def coordinates_in_range?
    boundary.all? { |p| p["lat"].between?(-90, 90) && p["lng"].between?(-180, 180) }
  end

  def repeated_consecutive_point?
    boundary.each_index.any? { |index| boundary[index] == boundary[index - 1] }
  end

  def self_intersecting?
    count = boundary.length
    edges = Array.new(count) { |index| [boundary[index], boundary[(index + 1) % count]] }
    edges.each_index.any? do |first|
      (first + 1...count).any? do |second|
        next false if adjacent_edges?(first, second, count)

        segments_intersect?(*edges[first], *edges[second])
      end
    end
  end

  def adjacent_edges?(first, second, count)
    second == first + 1 || (first.zero? && second == count - 1)
  end

  def segments_intersect?(a, b, c, d)
    d1 = orientation(c, d, a)
    d2 = orientation(c, d, b)
    d3 = orientation(a, b, c)
    d4 = orientation(a, b, d)
    return true if d1 * d2 < 0 && d3 * d4 < 0

    (d1.zero? && on_segment?(c, d, a)) || (d2.zero? && on_segment?(c, d, b)) ||
      (d3.zero? && on_segment?(a, b, c)) || (d4.zero? && on_segment?(a, b, d))
  end

  def orientation(p, q, r)
    value = ((q["lng"] - p["lng"]) * (r["lat"] - p["lat"])) - ((q["lat"] - p["lat"]) * (r["lng"] - p["lng"]))
    value <=> 0
  end

  def on_segment?(p, q, r)
    r["lng"].between?(*[p["lng"], q["lng"]].minmax) && r["lat"].between?(*[p["lat"], q["lat"]].minmax)
  end
end
