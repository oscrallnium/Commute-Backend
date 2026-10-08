namespace :graph do
  desc "Rebuild a closed loop from the one edge that holds its geometry (DRY_RUN=1 prints the plan only)"
  task reslice_loop: :environment do
    prefix = ENV.fetch("PREFIX")
    order = ENV.fetch("ORDER").split(",").map(&:strip)
    reslicer = LoopReslicer.new(prefix: prefix, order: order, source_edge_id: ENV.fetch("SOURCE"))
    plan = reslicer.plan

    plan.edges.each_with_index do |e, i|
      from = plan.order[e[:from_index]]
      to = plan.order[e[:to_index]]
      puts format("%-3d %-22s -> %-22s %4d pts %s", i + 1, from.name, to.name,
                  e[:points].length, e[:is_road_snapped] ? "" : "(straight line, snap it in the edge editor)")
    end

    if ENV["DRY_RUN"].present?
      puts "DRY_RUN set; nothing written."
    else
      reslicer.apply!(plan)
      puts "Rebuilt #{plan.edges.length} edges for #{prefix}; graph version is now #{GraphMeta.first!.version}."
    end
  end
end
