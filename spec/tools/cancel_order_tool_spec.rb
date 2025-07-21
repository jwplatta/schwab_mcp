require "spec_helper"

RSpec.describe SchwabMCP::Tools::CancelOrderTool do
  describe ".call" do
    let(:server_context) { instance_double("server_context") }
    let(:client) { instance_double("SchwabRb::Client") }
    let(:order_id) { "123456789" }
    let(:account_name) { "TRADING_BROKERAGE_ACCOUNT" }
    let(:account_id) { "12345678" }
    let(:account_hash) { "abc123hash" }
    let(:order_object) { instance_double("Order", status: "WORKING", order_type: "LIMIT", duration: "DAY", quantity: 1, price: 100.0, order_leg_collection: [], cancelable: true) }
    let(:account_double) { instance_double("Account", account_number: account_id, hash_value: account_hash) }
    let(:account_numbers) { instance_double("AccountNumbers", accounts: [account_double]) }
    let(:cancel_response) { double("Response", status: 200) }

    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(client)
      allow(client).to receive(:get_account_numbers).and_return(account_numbers)
      allow(client).to receive(:get_order).and_return(order_object)
      allow(client).to receive(:cancel_order).and_return(cancel_response)
    end

    context "with valid order and account" do
      it "returns cancellation success message" do
        response = described_class.call(order_id: order_id, account_name: account_name, server_context: server_context)
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Order Cancellation Successful")
        expect(response.content.first[:text]).to include(order_id)
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

    context "when account not found in ENV" do
      it "returns error" do
        allow(ENV).to receive(:[]).with(account_name).and_return(nil)
        response = described_class.call(order_id: order_id, account_name: account_name, server_context: server_context)
        expect(response.content.first[:text]).to match(/not found in environment variables/)
      end
    end

    context "when account id not found in account numbers" do
      it "returns error" do
        allow(account_numbers).to receive(:accounts).and_return([])
        response = described_class.call(order_id: order_id, account_name: account_name, server_context: server_context)
        expect(response.content.first[:text]).to match(/Account ID not found in available accounts/)
      end
    end

    context "when order is not found" do
      it "returns warning" do
        allow(client).to receive(:get_order).and_return(nil)
        response = described_class.call(order_id: order_id, account_name: account_name, server_context: server_context)
        expect(response.content.first[:text]).to match(/not found or empty response/)
      end
    end

    context "when order is not cancelable" do
      it "returns warning" do
        allow(order_object).to receive(:cancelable).and_return(false)
        response = described_class.call(order_id: order_id, account_name: account_name, server_context: server_context)
        expect(response.content.first[:text]).to match(/cannot be cancelled/)
      end
    end
  end
end
