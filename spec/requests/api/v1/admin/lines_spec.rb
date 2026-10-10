require "rails_helper"

RSpec.describe "PATCH /api/v1/admin/lines/:id", type: :request do
  let(:admin) do
    User.create!(email: "admin_#{SecureRandom.hex(4)}@test.com", password: "Password1!",
                 display_name: "Admin", role: :admin)
  end
  let(:rider) do
    User.create!(email: "rider_#{SecureRandom.hex(4)}@test.com", password: "Password1!",
                 display_name: "Rider")
  end
  let!(:line) { Line.create!(id: "COLOR_API", display_name: "Color API", mode: "bus") }

  before { GraphMeta.first || GraphMeta.create! }

  def patch_line(body, user: admin, id: "COLOR_API")
    headers = user ? auth_headers_for(user) : {}
    patch "/api/v1/admin/lines/#{id}", params: body.to_json,
          headers: headers.merge("Content-Type" => "application/json")
  end

  it "sets the color, uppercases it, and bumps the graph version" do
    version = GraphMeta.first.version
    patch_line({ line: { color_hex: "#a1b2c3" } })

    expect(response).to have_http_status(:ok)
    expect(line.reload.color_hex).to eq("#A1B2C3")
    expect(response.parsed_body["data"]).to include("id" => "COLOR_API", "colorHex" => "#A1B2C3")
    expect(GraphMeta.first.version).to eq(version + 1)
  end

  it "clears the color when sent null" do
    line.update!(color_hex: "#A1B2C3")
    patch_line({ line: { color_hex: nil } })

    expect(response).to have_http_status(:ok)
    expect(line.reload.color_hex).to be_nil
  end

  it "rejects an invalid color with 422" do
    patch_line({ line: { color_hex: "blue" } })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to be_present
    expect(line.reload.color_hex).to be_nil
  end

  it "does not change other fields" do
    patch_line({ line: { color_hex: "#A1B2C3", display_name: "Hacked" } })

    expect(line.reload.display_name).to eq("Color API")
  end

  it "returns 403 for a non-admin" do
    patch_line({ line: { color_hex: "#A1B2C3" } }, user: rider)

    expect(response).to have_http_status(:forbidden)
    expect(line.reload.color_hex).to be_nil
  end

  it "returns 401 without a token" do
    patch_line({ line: { color_hex: "#A1B2C3" } }, user: nil)

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 404 for a missing line" do
    patch_line({ line: { color_hex: "#A1B2C3" } }, id: "NO_SUCH_LINE")

    expect(response).to have_http_status(:not_found)
  end
end
