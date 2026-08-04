namespace :stations do
  desc "Apply the STATION_COORDS_AUDIT.md coordinate corrections (idempotent, safe to re-run)"
  task correct_coordinates: :environment do
    # Migration 016 carries the same corrections, but a migration runs once and is then
    # recorded as done forever. On a database that was empty when it ran — which is the
    # state of the local development DB — it updated nothing, and `db:migrate` will never
    # revisit it. Seeding afterwards restores the wrong coordinates from the Hono seed
    # with no mechanism left to fix them.
    #
    # This task closes that gap. It sets absolute values keyed by station_id, so it is
    # idempotent: run it after any seed, as many times as you like.
    require Rails.root.join("db/migrate/016_correct_rail_station_coordinates.rb")

    corrections = CorrectRailStationCoordinates::CORRECTIONS
    updated = 0
    already = 0
    missing = []

    corrections.each do |station_id, (lat, lng, _old_lat, _old_lng)|
      station = Station.find_by(station_id: station_id)
      if station.nil?
        missing << station_id
        next
      end

      if station.lat.to_f.round(6) == lat.round(6) && station.lng.to_f.round(6) == lng.round(6)
        already += 1
        next
      end

      station.update_columns(lat: lat, lng: lng)
      updated += 1
    end

    puts "corrected #{updated} station(s); #{already} already correct"
    if missing.any?
      puts "#{missing.size} not in the database: #{missing.join(', ')}"
      puts "(seed the graph first — an empty stations table means nothing to correct)"
    end
  end
end
