class Line < ApplicationRecord
  COLOR_HEX_FORMAT = /\A#[0-9A-F]{6}\z/

  self.primary_key = "id"
  self.table_name  = "lines"

  before_validation :normalize_color_hex
  validates :color_hex, format: { with: COLOR_HEX_FORMAT, message: "must look like #RRGGBB" },
                        allow_nil: true

  private

  def normalize_color_hex
    self.color_hex = color_hex.strip.upcase if color_hex.is_a?(String)
  end
end
