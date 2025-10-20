require "spec_helper"

RSpec.describe SchwabMCP::Tools::GetOrderTool do
  describe ".call" do
    let(:server_context) { instance_double("server_context") }
    let(:client) { instance_double("SchwabRb::Client") }
    let(:order_id) { "123456789" }
    let(:account_name) { "TRADING_BROKERAGE_ACCOUNT" }
    let(:order_object) { instance_double("Order", order_id: order_id, status: "FILLED", order_type: "LIMIT", duration: "DAY", complex_order_strategy_type: nil, entered_time: "2023-01-01T12:00:00Z", close_time: nil, quantity: 1, filled_quantity: 1, remaining_quantity: 0, price: 100.0, order_leg_collection: [], order_activity_collection: [], to_h: { orderId: order_id }) }

    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(client)
      allow(client).to receive(:available_account_names).and_return([account_name])
      allow(client).to receive(:get_order).and_return(order_object)
    end

    context "with valid order and account" do
      it "returns formatted order details" do
        response = described_class.call(order_id: order_id, account_name: account_name, server_context: server_context)
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Order Details for Order ID #{order_id}")
        expect(response.content.first[:text]).to include("FILLED")
      end
    end

    context "with invalid account name format" do
      it "returns error" do
        response = described_class.call(order_id: order_id, account_name: "BADNAME", server_context: server_context)
        expect(response.content.first[:text]).to match(/Account name must end with '_ACCOUNT'/)
      end
    end

    context "with invalid order id format" do
      it "returns error" do
        response = described_class.call(order_id: "abc", account_name: account_name, server_context: server_context)
        expect(response.content.first[:text]).to match(/Order ID must be numeric/)
      end
    end

    context "when account not found in configured accounts" do
      it "returns error" do
        allow(client).to receive(:available_account_names).and_return(["OTHER_ACCOUNT"])
        response = described_class.call(order_id: order_id, account_name: account_name, server_context: server_context)
        expect(response.content.first[:text]).to match(/not found in configured accounts/)
      end
    end
  end
end
