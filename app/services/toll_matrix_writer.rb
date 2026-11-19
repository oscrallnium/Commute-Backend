# Replaces every toll plaza and every toll fare with the lists of a toll_matrix change.
# It refuses to remove a plaza that an edge references.
class TollMatrixWriter
  def replace(change)
    plazas = change["plazas"]
    refuse_referenced_removals!(plazas.pluck("id"))
    TollFare.delete_all
    TollPlaza.where.not(id: plazas.pluck("id")).delete_all
    plazas.each { |plaza| TollPlaza.find_or_initialize_by(id: plaza["id"]).update!(name: plaza["name"]) }
    change["fares"].each do |fare|
      TollFare.create!(entry_plaza_id: fare["entry"], exit_plaza_id: fare["exit"], amount: fare["amount"])
    end
    nil
  end

  private

  def refuse_referenced_removals!(kept_ids)
    used = (Edge.where.not(toll_entry_plaza_id: nil).distinct.pluck(:toll_entry_plaza_id) +
            Edge.where.not(toll_exit_plaza_id: nil).distinct.pluck(:toll_exit_plaza_id)).uniq
    removed = used - kept_ids
    return if removed.empty?

    raise GraphChangeApplier::Rejected.new("Edges still use these plazas: #{removed.sort.join(", ")}.", field: "plazas")
  end
end
