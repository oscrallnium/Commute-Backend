class CorrectRailStationCoordinates < ActiveRecord::Migration[7.1]
  # Applies the coordinate corrections in STATION_COORDS_AUDIT.md (2026-07-16), which
  # found 34 of 46 rail stations placed 200 m – 4.4 km from where they actually are.
  # The audit checked every station against two independent sources — OpenStreetMap
  # station footprints and Wikipedia geodata — which agree with each other within 56 m
  # everywhere, and treated anything under 150 m of them as correct.
  #
  # The errors are systematic, not random: the LRT-1 Taft stretch and its northern
  # stretch were interpolated along a straight line on the wrong bearing, so the drift
  # grows with distance from the anchor stations (EDSA and Central Terminal, both
  # correct). LRT1_ROOSEVELT is the worst at 4.4 km — placed as if LRT-1 kept running
  # north up Rizal Ave, when the line turns east along EDSA after Monumento.
  #
  # ── Why this is a Rails migration ──────────────────────────────────────────────
  #
  # CLAUDE.md reserves the `stations` and `edges` *schemas* to the Hono microservice and
  # forbids Rails migrations that create or alter them. This alters no schema: it is an
  # UPDATE of 34 rows, the same write the admin station editor already performs through
  # StationsController#update. Rails also assembles and serves the graph itself —
  # GraphController#show calls GraphService.assemble_graph against these models, and
  # HONO_API_URL is declared in render.yaml but referenced nowhere in app/ — so these
  # rows are what clients actually receive.
  #
  # ⚠️ The Hono seed still carries the old values and `commutebeh-api` is not checked out
  # here, so `npm run db:seed` would reintroduce every error below. Port these values to
  # the Hono station seed before anyone reseeds.
  #
  # ── What this deliberately does NOT do ─────────────────────────────────────────
  #
  # `edges.distance_km` was derived from the old coordinates and is left untouched. On
  # the 55 rail edges, 10 now disagree with their own geometry by more than 500 m, and
  # the network total moves 59.3 km → 66.3 km. Recomputing them changes both fares
  # (base_fare + fare_per_km × distance_km) and A* costs, i.e. which routes win — a
  # product decision, not a data fix, and it belongs in its own migration.

  # station_id => [corrected_lat, corrected_lng, previous_lat, previous_lng]
  #
  # Previous values are recorded so `down` restores exactly what was here before. They
  # are the seed values, verified against data/transit_graph_v3.json at the time this
  # migration was written. If a station has since been moved by hand through the admin
  # editor, `down` returns it to the seed value rather than to that edit — there is no
  # record of intermediate states to return to.
  CORRECTIONS = {
    # ── LRT-1 (16) ──
    "LRT1_LIBERTAD"          => [14.547751, 120.998637, 14.5437, 121.0028],
    "LRT1_GIL_PUYAT"         => [14.554181, 120.997166, 14.5504, 121.0079],
    "LRT1_VITO_CRUZ"         => [14.563470, 120.994751, 14.5567, 121.0122],
    "LRT1_QUIRINO"           => [14.570288, 120.991526, 14.5628, 121.0156],
    "LRT1_PEDRO_GIL"         => [14.576575, 120.988020, 14.5681, 121.0194],
    "LRT1_UN_AVE"            => [14.582526, 120.984624, 14.5741, 121.0231],
    "LRT1_CARRIEDO"          => [14.599170, 120.981364, 14.5994, 120.9839],
    "LRT1_DOROTEO_JOSE"      => [14.605309, 120.982050, 14.6061, 120.9872],
    "LRT1_BAMBANG"           => [14.611133, 120.982487, 14.6100, 120.9889],
    "LRT1_TAYUMAN"           => [14.616715, 120.982723, 14.6161, 120.9922],
    "LRT1_BLUMENTRITT"       => [14.622784, 120.982890, 14.6222, 120.9956],
    "LRT1_ABAD_SANTOS"       => [14.630606, 120.981405, 14.6283, 120.9989],
    "LRT1_R_PAPA"            => [14.636014, 120.982279, 14.6344, 121.0022],
    "LRT1_5TH_AVE"           => [14.644406, 120.983536, 14.6406, 121.0056],
    "LRT1_BALINTAWAK"        => [14.657424, 121.003896, 14.6628, 120.9833],
    "LRT1_ROOSEVELT"         => [14.657559, 121.021137, 14.6711, 120.9828],

    # ── LRT-2 (12) ──
    "LRT2_RECTO"             => [14.603507, 120.983371, 14.6011, 120.9844],
    "LRT2_LEGARDA"           => [14.600877, 120.992569, 14.6011, 120.9889],
    "LRT2_PUREZA"            => [14.601677, 121.005094, 14.6011, 121.0022],
    "LRT2_V_MAPA"            => [14.604090, 121.017114, 14.6011, 121.0139],
    "LRT2_J_RUIZ"            => [14.610569, 121.026099, 14.6044, 121.0189],
    "LRT2_GILMORE"           => [14.613536, 121.034146, 14.6111, 121.0256],
    "LRT2_BETTY_GO_BELMONTE" => [14.618597, 121.042706, 14.6144, 121.0322],
    "LRT2_CUBAO"             => [14.622861, 121.053125, 14.6194, 121.0522],
    "LRT2_ANONAS"            => [14.627986, 121.064723, 14.6194, 121.0644],
    "LRT2_KATIPUNAN"         => [14.631083, 121.072916, 14.6278, 121.0756],
    "LRT2_SANTOLAN"          => [14.622108, 121.085964, 14.6361, 121.0878],
    "LRT2_MARIKINA"          => [14.620441, 121.100648, 14.6394, 121.0978],

    # ── MRT-3 (6) ──
    # MRT_TAFT_AVE (151 m) and MRT_BONI (203 m) sit either side of the audit's 150 m
    # threshold; both are included. Taft matters beyond its size — it is the LRT-1 EDSA
    # interchange, whose transfer walk is measured from these coordinates.
    "MRT_QUEZON_AVE"         => [14.642555, 121.038575, 14.6428, 121.0356],
    "MRT_GMA_KAMUNING"       => [14.635347, 121.043294, 14.6354, 121.0381],
    "MRT_ARANETA_CUBAO"      => [14.619484, 121.051073, 14.6231, 121.0524],
    "MRT_SANTOLAN"           => [14.607856, 121.056524, 14.6194, 121.0574],
    "MRT_TAFT_AVE"           => [14.537564, 121.001818, 14.5369, 121.0006],
    "MRT_BONI"               => [14.573774, 121.048189, 14.5756, 121.0481]
  }.freeze

  # Local model so this migration keeps working if app/models/station.rb changes later.
  class MigrationStation < ActiveRecord::Base
    self.table_name  = "stations"
    self.primary_key = "station_id"
    # Without this, ActiveRecord's default STI behaviour treats `type` (here holding
    # "train"/"bus"/"jeepney"/etc., not a Ruby class name) as the inheritance
    # discriminator, and instantiating a row raises SubclassNotFound the moment it
    # tries to look up a class literally called Train. Mirrors app/models/station.rb,
    # which sets the same thing on the real model for the same column.
    self.inheritance_column = nil
  end

  def up
    apply(:corrected)
  end

  # Reversible on purpose, unlike migration 015: the previous values were recorded
  # facts (wrong ones, but deliberate seed data), not an unset default, so restoring
  # them puts the table back exactly as it was.
  def down
    apply(:previous)
  end

  private

  def apply(which)
    updated = 0
    missing = []

    CORRECTIONS.each do |station_id, (new_lat, new_lng, old_lat, old_lng)|
      lat, lng = which == :corrected ? [new_lat, new_lng] : [old_lat, old_lng]

      station = MigrationStation.find_by(station_id: station_id)
      if station.nil?
        missing << station_id
        next
      end

      # update_columns: no validations, no callbacks, no updated_at churn on a data fix.
      station.update_columns(lat: lat, lng: lng)
      updated += 1
    end

    say "#{which} coordinates written for #{updated} station(s)"
    say "skipped #{missing.size} station(s) not present: #{missing.join(', ')}" if missing.any?
  end
end
