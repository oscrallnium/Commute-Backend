# Rebuilds a closed loop whose road geometry sits on one edge. The task renumbers the stops
# to `order`, cuts the source edge's polyline at each stop, and writes one edge per pair.
# See lib/tasks/graph_repair.rake for how to run it.
class LoopReslicer
  Plan = Struct.new(:order, :vertex_indices, :edges, keyword_init: true)

  # `order` lists every current station id of the loop in the new travel order.
  # `source_edge_id` names the edge whose polyline covers the loop.
  def initialize(prefix:, order:, source_edge_id:)
    @prefix = prefix
    @order = order
    @source = Edge.find(source_edge_id)
    @service = GraphService.new
  end

  def plan
    stations = @order.map { |id| Station.find(id) }
    validate!(stations)

    poly = @source.polyline_coordinates.map { |p| [p["lat"].to_f, p["lng"].to_f] }
    k = @order.index(@source.from_station)
    # The polyline runs from order[k] around to order[k - 1]; that last pair has no geometry.
    along = (0...stations.length).map { |j| (k + j) % stations.length }
    indices = monotonic_indices(along.map { |i| coords(stations[i]) }, poly)

    edges = stations.each_index.map do |i|
      from = stations[i]
      to = stations[(i + 1) % stations.length]
      j = along.index(i)
      points = j < along.length - 1 ? poly[indices[j]..indices[j + 1]] : []
      points = [coords(from), coords(to)] if points.length < 2
      points[0] = coords(from)
      points[-1] = coords(to)
      { from_index: i, to_index: (i + 1) % stations.length, points: points,
        is_road_snapped: j < along.length - 1 }
    end

    Plan.new(order: stations, vertex_indices: along.zip(indices).to_h, edges: edges)
  end

  def apply!(plan)
    line_id = @source.line
    template = @source.dup
    n = plan.order.length

    ActiveRecord::Base.transaction do
      Edge.where(line: line_id).where("edge_id ~ ?", "^#{Regexp.escape(@prefix)}_SEG[0-9]+$").delete_all
      # Two passes through temporary ids, so no rename lands on an id still in use.
      plan.order.each_with_index { |s, i| @service.send(:rename_stop!, s.station_id, "#{@prefix}_TMP#{i + 1}") }
      n.times { |i| @service.send(:rename_stop!, "#{@prefix}_TMP#{i + 1}", stop_id(i)) }

      plan.edges.each_with_index do |e, i|
        points = e[:points].map { |lat, lng| { lat: lat, lng: lng } }
        dist = @service.send(:poly_length_km, points)
        Edge.create!(@service.send(:edge_attrs, template,
                                   edge_id: "#{@prefix}_SEG#{i + 1}",
                                   from: stop_id(e[:from_index]), to: stop_id(e[:to_index]),
                                   distance_km: dist, polyline: points,
                                   is_road_snapped: e[:is_road_snapped]))
      end

      @service.send(:recompute_terminals!, line_id, @prefix)
      @service.send(:bump_graph_version!)
    end
  end

  private

  def stop_id(index) = "#{@prefix}_STOP#{index + 1}"

  def coords(station) = [station.lat.to_f, station.lng.to_f]

  def validate!(stations)
    current = Station.where(line: @source.line)
                     .where("station_id ~ ?", "^#{Regexp.escape(@prefix)}_STOP[0-9]+$").pluck(:station_id)
    raise ArgumentError, "order must list every stop of #{@prefix} once" unless current.sort == @order.sort
    raise ArgumentError, "source edge must start at a stop in order" unless @order.include?(@source.from_station)
    raise ArgumentError, "source edge must end at the stop before its start in order" unless
      @order[(@order.index(@source.from_station) - 1) % @order.length] == @source.to_station
    raise ArgumentError, "polyline has fewer points than stops" if @source.polyline_coordinates.length < stations.length
  end

  # Picks one vertex per stop, in order, that minimises the summed stop-to-vertex distance.
  # The first stop takes vertex 0 and the last stop takes the final vertex.
  def monotonic_indices(stops, poly)
    last = poly.length - 1
    cost = stops.map { |s| poly.map { |p| metres(s, p) } }
    best = Array.new(stops.length) { Array.new(poly.length, Float::INFINITY) }
    back = Array.new(stops.length) { Array.new(poly.length) }
    best[0][0] = cost[0][0]
    (1...stops.length).each do |j|
      running = Float::INFINITY
      running_at = nil
      (1..last).each do |v|
        if best[j - 1][v - 1] < running
          running = best[j - 1][v - 1]
          running_at = v - 1
        end
        best[j][v] = running + cost[j][v]
        back[j][v] = running_at
      end
    end
    indices = [last]
    (stops.length - 1).downto(1) { |j| indices.unshift(back[j][indices.first]) }
    indices
  end

  def metres(a, b)
    dy = (a[0] - b[0]) * 111_320
    dx = (a[1] - b[1]) * 111_320 * Math.cos(a[0] * Math::PI / 180)
    Math.hypot(dx, dy)
  end
end
