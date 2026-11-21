require "rails_helper"

RSpec.describe TesterInviteJob do
  let(:row) do
    TesterRequest.create!(name: "Juan Dela Cruz", age: 20, location: "Makati", email: "a@example.com",
                          consent_at: Time.current, status: :inviting)
  end

  def client_with(*responses, env: asc_env)
    AppStoreConnect::Client.new(env: env, transport: FakeAppStoreConnectTransport.new(*responses))
  end

  it "runs on the async adapter" do
    expect(described_class.queue_adapter).to be_a(ActiveJob::QueueAdapters::AsyncAdapter)
  end

  it "sets invited, the tester id, and the invite time" do
    described_class.new.perform(row.id, "invite", client: client_with([201, { data: { id: "T1" } }]))
    expect(row.reload).to have_attributes(status: "invited", asc_beta_tester_id: "T1", last_error: nil)
    expect(row.invited_at).to be_present
  end

  it "sets failed with Apple's detail for a 4xx answer" do
    client = client_with([422, { errors: [{ detail: "The email is not valid" }] }])
    described_class.new.perform(row.id, "invite", client: client)
    expect(row.reload).to have_attributes(status: "failed", last_error: "The email is not valid")
  end

  it "sets failed with a clear error when a setting is missing" do
    described_class.new.perform(row.id, "invite", client: client_with(env: {}))
    expect(row.reload.status).to eq("failed")
    expect(row.last_error).to start_with("App Store Connect is not configured. Missing: ASC_ISSUER_ID")
  end

  it "resends for an invited tester and keeps the tester id" do
    row.update!(asc_beta_tester_id: "T1")
    described_class.new.perform(row.id, "resend", client: client_with([201, { data: { id: "I1" } }]))
    expect(row.reload).to have_attributes(status: "invited", asc_beta_tester_id: "T1")
  end

  it "does nothing for a row that is not inviting" do
    row.update!(status: :declined)
    described_class.new.perform(row.id, "invite", client: client_with)
    expect(row.reload.status).to eq("declined")
  end

  it "does nothing for a deleted row" do
    id = row.id
    row.destroy!
    expect { described_class.new.perform(id, "invite", client: client_with) }.not_to raise_error
  end

  describe "retries" do
    include ActiveJob::TestHelper

    def run_job(*answers)
      allow(AppStoreConnect::Client).to receive(:new)
        .and_return(client_with(*answers))
      described_class.perform_now(row.id, "invite")
    end

    it "schedules a retry for a 5xx answer and keeps the row inviting" do
      allow(described_class).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::TestAdapter.new)
      run_job([503, {}])
      expect(described_class.queue_adapter.enqueued_jobs.size).to eq(1)
      expect(row.reload.status).to eq("inviting")
    end

    it "schedules a retry for a network error" do
      allow(described_class).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::TestAdapter.new)
      run_job(AppStoreConnect::Client::TransientError.new("Network error: Net::OpenTimeout"))
      expect(described_class.queue_adapter.enqueued_jobs.size).to eq(1)
    end

    it "does not retry a 4xx answer" do
      allow(described_class).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::TestAdapter.new)
      run_job([403, { errors: [{ detail: "Forbidden" }] }])
      expect(described_class.queue_adapter.enqueued_jobs).to be_empty
      expect(row.reload.status).to eq("failed")
    end

    it "sets failed after the last attempt" do
      allow(described_class).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::TestAdapter.new)
      job = described_class.new(row.id, "invite")
      job.exception_executions = { [AppStoreConnect::Client::TransientError].to_s => described_class::RETRY_ATTEMPTS - 1 }
      allow(AppStoreConnect::Client).to receive(:new).and_return(client_with([500, {}]))
      job.perform_now
      expect(row.reload).to have_attributes(status: "failed", last_error: "App Store Connect returned HTTP 500")
      expect(described_class.queue_adapter.enqueued_jobs).to be_empty
    end
  end
end
