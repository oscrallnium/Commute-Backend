class Line < ApplicationRecord
  COLOR_HEX_FORMAT = /\A#[0-9A-F]{6}\z/
  DIRECTIONS       = %w[both one_way].freeze
  INTERCHANGE_ID   = "INTERCHANGE".freeze

  self.primary_key = "id"
  self.table_name  = "lines"

  before_validation :normalize_color_hex
  validates :color_hex, format: { with: COLOR_HEX_FORMAT, message: "must look like #RRGGBB" },
                        allow_nil: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :base_km, numericality: { greater_than_or_equal_to: 0 }

  private

  def normalize_color_hex
    self.color_hex = color_hex.strip.upcase if color_hex.is_a?(String)
  end
end
