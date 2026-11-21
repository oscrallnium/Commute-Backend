# Streams tester-request events to admins. ApplicationCable::Connection rejects other users.
class TesterRequestsChannel < ApplicationCable::Channel
  STREAM = "tester_requests".freeze

  def subscribed
    stream_from STREAM
  end

  def self.broadcast_request(event, request)
    deliver(event: event, request: request.as_api_json)
  end

  def self.broadcast_deleted(id)
    deliver(event: "deleted", id: id)
  end

  # A broadcast failure never fails the request: the row is already committed, and the
  # dashboard reloads the list after each reconnect.
  def self.deliver(message)
    ActionCable.server.broadcast(STREAM, message)
  rescue StandardError => e
    Rails.logger.error("[cable] tester_requests broadcast failed: #{e.class}")
  end
  private_class_method :deliver
end
