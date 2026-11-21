require "rails_helper"

RSpec.describe TesterRequestsChannel, type: :channel do
  before { stub_connection current_user: admin_user }

  it "streams from tester_requests" do
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("tester_requests")
  end

  it "does not raise when the broadcast fails" do
    allow(ActionCable.server).to receive(:broadcast).and_raise(PG::ConnectionBad)
    expect { described_class.broadcast_deleted("x") }.not_to raise_error
  end
end
