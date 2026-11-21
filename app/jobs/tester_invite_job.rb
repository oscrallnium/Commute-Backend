# Sends a TestFlight invite, or resends one, for a tester request in the `inviting` status.
# Sets `invited`, or `failed` with the App Store Connect error in `last_error`.
class TesterInviteJob < ApplicationJob
  ACTIONS = %w[invite resend].freeze
  RETRY_ATTEMPTS = 4

  # Runs in the web process. The deploy has no Sidekiq worker. A restart loses a running job,
  # and the row stays `inviting` until an admin invites it again.
  self.queue_adapter = :async

  retry_on AppStoreConnect::Client::TransientError, attempts: RETRY_ATTEMPTS, wait: :polynomially_longer do |job, error|
    job.mark_failed(job.arguments.first, error.message)
  end

  def perform(request_id, action, client: AppStoreConnect::Client.new)
    raise ArgumentError, "Unknown action #{action}" unless ACTIONS.include?(action)

    tester_request = TesterRequest.find_by(id: request_id)
    return unless tester_request&.inviting?

    tester_id = action == "invite" ? invite(tester_request, client) : resend(tester_request, client)
    tester_request.update!(status: :invited, asc_beta_tester_id: tester_id, invited_at: Time.current, last_error: nil)
  rescue AppStoreConnect::Client::Error => e
    mark_failed(request_id, e.message)
  end

  def mark_failed(request_id, message)
    TesterRequest.find_by(id: request_id)&.update!(status: :failed, last_error: message)
  end

  private

  def invite(tester_request, client)
    client.invite_tester(email: tester_request.email, **tester_request.name_parts)
  end

  def resend(tester_request, client)
    client.resend_invitation(tester_id: tester_request.asc_beta_tester_id)
    tester_request.asc_beta_tester_id
  end
end
