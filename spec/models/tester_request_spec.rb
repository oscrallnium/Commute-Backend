require "rails_helper"

RSpec.describe TesterRequest, type: :model do
  let(:valid_attributes) do
    { name: "Juan Dela Cruz", age: 21, location: "Quezon City", email: "Juan@Example.com ",
      consent_at: Time.current }
  end

  it "stores the email in lower case" do
    expect(described_class.create!(valid_attributes).email).to eq("juan@example.com")
  end

  it "defaults to pending and website" do
    row = described_class.create!(valid_attributes)
    expect([row.status, row.source]).to eq(%w[pending website])
  end

  it "stores a blank name as null" do
    expect(described_class.create!(valid_attributes.merge(name: "  ")).name).to be_nil
  end

  it "refuses an age under 16, a long name, a long location, a bad email, and no consent time" do
    row = described_class.new(valid_attributes.merge(age: 15, name: "a" * 61, location: "b" * 81,
                                                     email: "not-an-email", consent_at: nil))
    expect(row).not_to be_valid
    expect(row.errors.attribute_names).to include(:age, :name, :location, :email, :consent_at)
  end

  it "refuses an age that is not a whole number" do
    expect(described_class.new(valid_attributes.merge(age: "21.5"))).not_to be_valid
  end

  it "refuses an unknown status with a validation error" do
    row = described_class.new(valid_attributes.merge(status: "approved"))
    expect(row).not_to be_valid
    expect(row.errors.attribute_names).to include(:status)
  end

  it "enforces the age check in the database" do
    row = described_class.create!(valid_attributes)
    expect { row.update_column(:age, 15) }.to raise_error(ActiveRecord::StatementInvalid, /tester_requests_age_check/)
  end

  it "enforces the status check in the database" do
    row = described_class.create!(valid_attributes)
    expect { row.update_column(:status, "approved") }
      .to raise_error(ActiveRecord::StatementInvalid, /tester_requests_status_check/)
  end

  describe ".submit" do
    it "touches the row that has the same email in any letter case and makes no duplicate" do
      first = described_class.create!(valid_attributes)
      first.update_column(:updated_at, 1.day.ago)
      result = described_class.submit(valid_attributes.merge(email: "JUAN@example.com", age: 40))
      expect(result.id).to eq(first.id)
      expect(described_class.count).to eq(1)
      expect(first.reload.age).to eq(21)
      expect(first.updated_at).to be > 1.minute.ago
    end

    it "returns the invalid record and saves nothing" do
      result = described_class.submit(valid_attributes.merge(age: 12))
      expect(result.errors).to include(:age)
      expect(described_class.count).to eq(0)
    end
  end

  describe "status changes" do
    let(:admin) { admin_user }
    let(:row) { described_class.create!(valid_attributes) }

    it "starts an invite from pending and records the admin" do
      row.start_invite!(admin)
      expect(row.reload).to have_attributes(status: "inviting", invited_by_id: admin.id)
    end

    it "refuses to invite an invited row" do
      row.update!(status: :invited, asc_beta_tester_id: "T1")
      expect { row.start_invite!(admin) }.to raise_error(TesterRequest::TransitionError)
    end

    it "permits a new invite of a row that stays inviting for too long" do
      row.update!(status: :inviting)
      row.update_column(:updated_at, 11.minutes.ago)
      expect { row.start_invite!(admin) }.not_to raise_error
    end

    it "refuses a new invite of a row that is inviting now" do
      row.update!(status: :inviting)
      expect { row.start_invite!(admin) }.to raise_error(TesterRequest::TransitionError)
    end

    it "resends only for an invited row" do
      expect { row.start_resend!(admin) }.to raise_error(TesterRequest::TransitionError)
      row.update!(status: :invited, asc_beta_tester_id: "T1")
      row.start_resend!(admin)
      expect(row.reload.status).to eq("inviting")
    end

    it "declines a pending or failed row only" do
      row.decline!
      expect(row.reload.status).to eq("declined")
      expect { row.decline! }.to raise_error(TesterRequest::TransitionError)
    end
  end

  it "splits the name into a first name and a last name" do
    expect(described_class.new(name: "Juan Dela Cruz").name_parts).to eq(first_name: "Juan", last_name: "Dela Cruz")
    expect(described_class.new(name: nil).name_parts).to eq(first_name: nil, last_name: nil)
  end

  describe "broadcasts" do
    it "broadcasts created, updated, and deleted events after commit" do
      row = nil
      expect { row = described_class.create!(valid_attributes) }
        .to have_broadcasted_to("tester_requests").with(hash_including("event" => "created"))
      expect { row.update!(location: "Manila") }
        .to have_broadcasted_to("tester_requests").with(hash_including("event" => "updated"))
      expect { row.destroy! }
        .to have_broadcasted_to("tester_requests").with("event" => "deleted", "id" => row.id)
    end
  end

  it "returns camelCase keys from as_api_json" do
    json = described_class.create!(valid_attributes).as_api_json
    expect(json.keys).to eq(%i[id name age location email status consentAt source ascBetaTesterId invitedAt
                               lastError createdAt updatedAt])
  end
end
