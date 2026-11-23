module SocialAuth
  # Raised when a provider token fails any check.
  class InvalidTokenError < StandardError; end
end
