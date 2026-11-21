require "rails_helper"

RSpec.describe "Admin tester requests", type: :request do
  let(:headers) { auth_headers_for(admin_user) }

  def create_request(email, **attributes)
    TesterRequest.create!({ age: 20, location: "Makati", email: email, consent_at: Time.current }.merge(attributes))
  end

  describe "authentication" do
    let!(:row) { create_request("a@example.com") }

    it "answers 401 with no token" do
      get "/api/v1/admin/tester_requests"
      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 403 for a commuter on every endpoint" do
      rider = auth_headers_for(rider_user)
      get "/api/v1/admin/tester_requests", headers: rider
      expect(response).to have_http_status(:forbidden)
      %w[invite resend decline].each do |action|
        post "/api/v1/admin/tester_requests/#{row.id}/#{action}", headers: rider
        expect(response).to have_http_status(:forbidden)
      end
      delete "/api/v1/admin/tester_requests/#{row.id}", headers: rider
      expect(response).to have_http_status(:forbidden)
      expect(row.reload.status).to eq("pending")
    end
  end

  describe "GET /api/v1/admin/tester_requests" do
    before do
      create_request("old@example.com", created_at: 2.days.ago)
      create_request("new@example.com", created_at: 1.hour.ago)
      create_request("failed@example.com", status: :failed, created_at: 3.days.ago)
    end

    it "lists the newest first with the page meta" do
      get "/api/v1/admin/tester_requests", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].pluck("email"))
        .to eq(%w[new@example.com old@example.com failed@example.com])
      expect(response.parsed_body["meta"]).to eq("page" => 1, "perPage" => 50, "total" => 3)
    end

    it "returns every contract key" do
      get "/api/v1/admin/tester_requests", headers: headers
      expect(response.parsed_body["data"].first.keys).to match_array(
        %w[id name age location email status consentAt source ascBetaTesterId invitedAt lastError createdAt updatedAt]
      )
    end

    it "filters by status" do
      get "/api/v1/admin/tester_requests", params: { status: "failed" }, headers: headers
      expect(response.parsed_body["data"].pluck("email")).to eq(%w[failed@example.com])
      expect(response.parsed_body["meta"]["total"]).to eq(1)
    end

    it "pages the list" do
      get "/api/v1/admin/tester_requests", params: { page: 2, per_page: 2 }, headers: headers
      expect(response.parsed_body["data"].pluck("email")).to eq(%w[failed@example.com])
      expect(response.parsed_body["meta"]).to eq("page" => 2, "perPage" => 2, "total" => 3)
    end

    it "refuses an unknown status with 422" do
      get "/api/v1/admin/tester_requests", params: { status: "approved" }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/admin/tester_requests/:id/invite" do
    let!(:row) { create_request("a@example.com") }

    it "sets inviting, records the admin, starts the job, and answers 202" do
      expect(TesterInviteJob).to receive(:perform_later).with(row.id, "invite")
      post "/api/v1/admin/tester_requests/#{row.id}/invite", headers: headers
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["data"]["status"]).to eq("inviting")
      expect(row.reload.invited_by_id).to eq(admin_user.id)
    end

    it "answers 409 for an invited row and starts no job" do
      row.update!(status: :invited, asc_beta_tester_id: "T1")
      expect(TesterInviteJob).not_to receive(:perform_later)
      post "/api/v1/admin/tester_requests/#{row.id}/invite", headers: headers
      expect(response).to have_http_status(:conflict)
    end

    it "answers 404 for an unknown id" do
      post "/api/v1/admin/tester_requests/#{SecureRandom.uuid}/invite", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/admin/tester_requests/:id/resend" do
    let!(:row) { create_request("a@example.com", status: :invited, asc_beta_tester_id: "T1") }

    it "sets inviting, starts the resend job, and answers 202" do
      expect(TesterInviteJob).to receive(:perform_later).with(row.id, "resend")
      post "/api/v1/admin/tester_requests/#{row.id}/resend", headers: headers
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["data"]["status"]).to eq("inviting")
    end

    it "answers 409 for a row that is not invited" do
      row.update!(status: :pending)
      post "/api/v1/admin/tester_requests/#{row.id}/resend", headers: headers
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "POST /api/v1/admin/tester_requests/:id/decline" do
    let!(:row) { create_request("a@example.com") }

    it "sets declined and answers 200" do
      post "/api/v1/admin/tester_requests/#{row.id}/decline", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["status"]).to eq("declined")
    end

    it "answers 409 for an invited row" do
      row.update!(status: :invited, asc_beta_tester_id: "T1")
      post "/api/v1/admin/tester_requests/#{row.id}/decline", headers: headers
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "DELETE /api/v1/admin/tester_requests/:id" do
    let!(:row) { create_request("a@example.com") }

    it "deletes the row, answers 204, and broadcasts deleted" do
      expect { delete "/api/v1/admin/tester_requests/#{row.id}", headers: headers }
        .to have_broadcasted_to("tester_requests").with("event" => "deleted", "id" => row.id)
      expect(response).to have_http_status(:no_content)
      expect(TesterRequest.exists?(row.id)).to be false
    end
  end
end
