class StationAccessPoint < ApplicationRecord
  self.primary_key = "access_point_id" # TEXT PK — matches Station and Edge

  KINDS      = %w[entrance exit both].freeze
  DIRECTIONS = %w[northbound southbound].freeze

  belongs_to :station, primary_key: :station_id, foreign_key: :station_id

  validates :access_point_id, :station_id, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :direction, inclusion: { in: DIRECTIONS }, allow_nil: true
  validates :lat, presence: true, numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 }
  validates :lng, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  # position first, then id — an explicit tiebreak so two doors sharing a position never
  # swap places between requests and make the admin list look like it is reordering itself.
  scope :ordered, -> { order(:position, :access_point_id) }

  # The selection rule, in one place.
  #
  # NULL direction means "serves every direction", so it matches whatever is asked for —
  # including a nil `direction`, which is what every non-MRT-3 leg passes, since only
  # MRT-3 has directional edges. A station with one shared concourse (MRT Ayala) is
  # therefore a single NULL row and needs no special handling anywhere.
  #
  # `kind` is filtered the same way: 'both' answers to entrance and exit alike, so the
  # usual single-hall station is one row rather than two.
  #
  # A nil `direction` means the caller does not know or does not care — an LRT leg, or a
  # walk whose adjoining ride has no direction label. That must return *every* door, not
  # just the undirected ones: filtering to `direction IS NULL` would make a station whose
  # doors are all direction-tagged look like it had none at all, and it would fall back to
  # the centroid while perfectly good coordinates sat in the table. When direction is
  # unknown every door is a candidate and the caller's nearest-wins tiebreak decides.
  #
  # Returning empty is still a legitimate answer — it means "no doors surveyed for this
  # station yet", and the caller falls back to the station centroid.
  scope :serving, lambda { |direction: nil, kind: nil|
    rel = all
    # [nil, direction] becomes `direction IS NULL OR direction = ?` — the undirected
    # doors always qualify alongside the matching directed ones.
    rel = rel.where(direction: [nil, direction]) if direction.present?
    rel = rel.where(kind: ["both", kind]) if kind.present?
    rel.ordered
  }

  def as_api_json
    {
      id: access_point_id,
      station_id: station_id,
      name: name,
      kind: kind,
      direction: direction,
      coordinates: { lat: lat.to_f, lng: lng.to_f },
      position: position
    }
  end

  # camelCase twin of the above, for the graph payload the iOS client decodes.
  # GraphService#station_json is the only caller — see the note there about the two
  # serialisers having to be changed together.
  def as_graph_json
    {
      id: access_point_id,
      name: name,
      kind: kind,
      direction: direction,
      coordinates: { lat: lat.to_f, lng: lng.to_f }
    }
  end
end
