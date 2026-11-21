require "rails_helper"

RSpec.describe "Payment publish changes" do
  before { build_ops_graph! }

  def publish(*changes, base: graph_version_now)
    GraphPublisher.publish(base_version: base, changes: changes.map(&:deep_stringify_keys), user: admin_user)
  end

  def expect_created(result)
    expect(result.status).to eq(:created), result.body.inspect
  end

  def expect_rejected(result, field:, message: nil)
    expect(result.status).to eq(:unprocessable_content), result.body.inspect
    error = result.body[:errors].first
    expect(error[:field]).to eq(field)
    expect(error[:message]).to include(message) if message
  end

  def add_wallet(**overrides)
    { type: "payment_method_add", payment_method_id: "pmpb_wallet", name: "Pmpb Wallet" }.merge(overrides)
  end

  def walk_mode
    TransportMode.find("walk")
  end

  describe "payment_method_add" do
    it "creates the row, reports the ID, and raises the version once" do
      version = graph_version_now
      result = publish(add_wallet(sf_symbol: "building.columns.fill", color_hex: "#ff5722", is_default: false,
                                  accepted_by_modes: %w[bus], notes: " QR scan. "))

      expect_created(result)
      expect(graph_version_now).to eq(version + 1)
      expect(result.body[:data][:created]).to eq([{ index: 0, type: "payment_method_add", id: "pmpb_wallet" }])
      expect(PaymentMethod.find("pmpb_wallet")).to have_attributes(
        display_name: "Pmpb Wallet", sf_symbol: "building.columns.fill", color_hex: "#FF5722", is_default: false,
        accepted_by_modes: %w[bus], notes: "QR scan."
      )
    end

    it "uses the column defaults for the fields that the change leaves out" do
      expect_created(publish(add_wallet))

      expect(PaymentMethod.find("pmpb_wallet")).to have_attributes(sf_symbol: "", color_hex: "#000000",
                                                                   is_default: false, accepted_by_modes: [], notes: "")
    end

    it "refuses an ID that exists and a mode that does not" do
      expect_rejected(publish(add_wallet(payment_method_id: "cash")), field: "payment_method_id",
                                                                      message: "already exists")
      expect_rejected(publish(add_wallet(accepted_by_modes: %w[bus pmpb_boat])), field: "accepted_by_modes",
                                                                                message: "pmpb_boat")
      expect(PaymentMethod.exists?("pmpb_wallet")).to be false
    end
  end

  describe "payment_method_update" do
    before { expect_created(publish(add_wallet(accepted_by_modes: %w[bus]))) }

    it "changes only the fields that the change sends" do
      expect_created(publish({ type: "payment_method_update", payment_method_id: "pmpb_wallet",
                               accepted_by_modes: %w[bus train], notes: "Gate tap." }))

      expect(PaymentMethod.find("pmpb_wallet")).to have_attributes(display_name: "Pmpb Wallet",
                                                                   accepted_by_modes: %w[bus train], notes: "Gate tap.")
    end

    it "refuses an unknown payment method" do
      expect_rejected(publish({ type: "payment_method_update", payment_method_id: "pmpb_none", notes: "x" }),
                      field: "payment_method_id", message: "was not found")
    end
  end

  describe "payment_method_delete" do
    before { expect_created(publish(add_wallet)) }

    it "refuses while a ride edge, a service area, or a mode default lists the ID, and names each one" do
      Edge.where(edge_id: "OPST_ROAD_S1__OPST_ROAD_S2").update_all(accepted_payments: %w[cash pmpb_wallet])
      TransportMode.where(id: "bus").update_all(default_accepted_payments: %w[pmpb_wallet])

      result = publish({ type: "payment_method_delete", payment_method_id: "pmpb_wallet" })

      expect_rejected(result, field: "payment_method_id", message: "edges of lines OPST_ROAD")
      expect(result.body[:errors].first[:message]).to include("mode defaults bus")
      expect(PaymentMethod.exists?("pmpb_wallet")).to be true
    end

    it "refuses while a service area lists the ID" do
      build_area_mode!
      expect_created(publish(service_area_change(accepted_payments: %w[pmpb_wallet])))

      expect_rejected(publish({ type: "payment_method_delete", payment_method_id: "pmpb_wallet" }),
                      field: "payment_method_id", message: "service areas SAPB_ZONE")
    end

    it "removes the ID from INTERCHANGE edges and from always-allowed modes, then deletes the row" do
      transfer = "X__OPST_ROAD_S2__OPST_RAIL_B"
      Edge.where(edge_id: transfer).update_all(accepted_payments: %w[cash pmpb_wallet])
      walk_mode.update!(is_always_allowed: true, default_accepted_payments: %w[cash pmpb_wallet])

      expect_created(publish({ type: "payment_method_delete", payment_method_id: "pmpb_wallet" }))

      expect(PaymentMethod.exists?("pmpb_wallet")).to be false
      expect(Edge.find(transfer).accepted_payments).to eq(%w[cash])
      expect(walk_mode.default_accepted_payments).to eq(%w[cash])
    end
  end

  describe "line_payments" do
    it "writes every edge of the line, hidden edges included" do
      Edge.where(edge_id: "OPST_RAIL_B__OPST_RAIL_C").update_all(enabled: false)

      expect_created(publish(add_wallet,
                             { type: "line_payments", line_id: "OPST_RAIL", accepted_payments: %w[cash pmpb_wallet] }))

      expect(Edge.where(line: "OPST_RAIL").pluck(:accepted_payments)).to all(eq(%w[cash pmpb_wallet]))
      expect(Edge.where(line: "OPST_ROAD").pluck(:accepted_payments)).to all(eq(%w[cash]))
    end

    it "refuses an unknown payment method and changes nothing" do
      expect_rejected(publish({ type: "line_payments", line_id: "OPST_RAIL", accepted_payments: %w[cash pmpb_none] }),
                      field: "accepted_payments", message: "pmpb_none")
      expect(Edge.where(line: "OPST_RAIL").pluck(:accepted_payments)).to all(eq(%w[cash]))
    end

    it "refuses INTERCHANGE, a line with no edges, and a service area" do
      build_area_mode!
      expect_created(publish(service_area_change))
      change = { type: "line_payments", accepted_payments: %w[cash] }

      expect_rejected(publish(change.merge(line_id: "INTERCHANGE")), field: "line_id", message: "reserved line")
      expect_rejected(publish(change.merge(line_id: "OPST_EMPTY")), field: "line_id", message: "no edges")
      expect_rejected(publish(change.merge(line_id: "SAPB_ZONE")), field: "line_id", message: "service_area_fare")
    end
  end

  describe "mode_default_payments" do
    it "sets the default payments of the mode" do
      expect_created(publish({ type: "mode_default_payments", mode_id: "bus", accepted_payments: %w[cash] }))

      expect(TransportMode.find("bus").default_accepted_payments).to eq(%w[cash])
    end

    it "refuses an unknown mode and an unknown payment method" do
      expect_rejected(publish({ type: "mode_default_payments", mode_id: "pmpb_boat", accepted_payments: %w[cash] }),
                      field: "mode_id")
      expect_rejected(publish({ type: "mode_default_payments", mode_id: "bus", accepted_payments: %w[pmpb_none] }),
                      field: "accepted_payments")
    end
  end
end
