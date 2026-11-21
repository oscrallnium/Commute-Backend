class TesterRequest < ApplicationRecord
  # The current status does not permit the action.
  class TransitionError < StandardError; end

  MINIMUM_AGE = 16
  MAXIMUM_AGE = 120
  INVITABLE = %w[pending failed declined].freeze
  DECLINABLE = %w[pending failed].freeze
  STALE_INVITE_AFTER = 10.minutes

  enum :status, {
    pending: "pending", inviting: "inviting", invited: "invited", failed: "failed", declined: "declined"
  }, default: :pending, validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, :location, with: ->(text) { text.strip.presence }

  validates :email, presence: true, length: { maximum: 254 },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :age, presence: true,
                  numericality: { only_integer: true, greater_than_or_equal_to: MINIMUM_AGE,
                                  less_than_or_equal_to: MAXIMUM_AGE }
  validates :name, length: { maximum: 60 }
  validates :location, presence: true, length: { maximum: 80 }
  validates :consent_at, presence: true
  validates :source, presence: true, format: { with: /\A[a-z_]{1,40}\z/ }

  after_create_commit  { TesterRequestsChannel.broadcast_request("created", self) }
  after_update_commit  { TesterRequestsChannel.broadcast_request("updated", self) }
  after_destroy_commit { TesterRequestsChannel.broadcast_deleted(id) }

  # Saves a new request, or touches the row that has the same email. Returns the record,
  # which holds the validation errors when the attributes are not valid.
  def self.submit(attributes)
    candidate = new(attributes)
    return candidate unless candidate.valid?

    existing = find_by(email: candidate.email)
    return existing.tap { |row| row.update!(updated_at: Time.current) } if existing

    candidate.tap(&:save!)
  rescue ActiveRecord::RecordNotUnique
    find_by!(email: candidate.email).tap { |row| row.update!(updated_at: Time.current) }
  end

  # A row stays `inviting` when the process restarts during the job. After
  # STALE_INVITE_AFTER an admin can invite it again.
  def start_invite!(admin)
    transition!(:inviting, invited_by_id: admin.id, last_error: nil) do
      INVITABLE.include?(status) || (inviting? && updated_at < STALE_INVITE_AFTER.ago)
    end
  end

  def start_resend!(admin)
    transition!(:inviting, invited_by_id: admin.id, last_error: nil) { invited? && asc_beta_tester_id.present? }
  end

  def decline!
    transition!(:declined) { DECLINABLE.include?(status) }
  end

  # Returns the row in the shape of the tester-request API. See docs/tester-requests.md.
  def as_api_json
    {
      id: id, name: name, age: age, location: location, email: email, status: status,
      consentAt: consent_at&.iso8601, source: source, ascBetaTesterId: asc_beta_tester_id,
      invitedAt: invited_at&.iso8601, lastError: last_error,
      createdAt: created_at&.iso8601, updatedAt: updated_at&.iso8601
    }
  end

  def name_parts
    first, last = name.to_s.split(/\s+/, 2)
    { first_name: first, last_name: last }
  end

  private

  def transition!(new_status, **attributes)
    with_lock do
      raise TransitionError, "A request in the #{status} status cannot become #{new_status}" unless yield

      update!(status: new_status, **attributes)
    end
  end
end
