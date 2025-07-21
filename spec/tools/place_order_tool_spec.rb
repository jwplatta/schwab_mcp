# frozen_string_literal: true

require "spec_helper"

RSpec.describe SchwabMCP::Tools::PlaceOrderTool do
  describe ".call" do
    let(:mock_client) { instance_double("SchwabRb::Client") }
    let(:account_numbers) { instance_double("SchwabRb::DataObjects::AccountNumbers") }
    let(:mock_response) { instance_double("HTTP::Response") }
    let(:mock_order_builder) { double("OrderBuilder") }

    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(mock_client)
      allow(SchwabMCP::Orders::OrderFactory).to receive(:build).and_return(mock_order_builder)

      allow(account_numbers).to receive(:size).and_return(1)
      allow(account_numbers).to receive(:find_hash_value).with("12345678").and_return("hash1")

      allow(mock_response).to receive(:status).and_return(201)
      allow(mock_response).to receive(:headers).and_return({ "Location" => "https://api.schwabapi.com/trader/v1/accounts/hash1/orders/67890" })
      allow(mock_response).to receive(:body).and_return('{"orderId": "67890", "status": "PENDING"}')
    end

    context "when client initialization fails" do
      it "returns error response" do
        allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(nil)

        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "callspread",
          price: 1.50,
          short_leg_symbol: "AAPL240315C00180000",
          long_leg_symbol: "AAPL240315C00185000",
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to initialize Schwab client")
      end
    end

    context "when account name format is invalid" do
      it "returns error response" do
        response = described_class.call(
          account_name: "INVALID_NAME",
          strategy_type: "callspread",
          price: 1.50,
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Account name must end with '_ACCOUNT'")
      end
    end

    context "when account numbers retrieval fails" do
      it "returns error response" do
        allow(mock_client).to receive(:get_account_numbers).and_return(nil)

        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "callspread",
          price: 1.50,
          short_leg_symbol: "AAPL240315C00180000",
          long_leg_symbol: "AAPL240315C00185000",
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to retrieve account numbers")
      end
    end

    context "when account hash not found" do
      it "returns error response" do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(account_numbers).to receive(:find_hash_value).with("12345678").and_return(nil)

        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "callspread",
          price: 1.50,
          short_leg_symbol: "AAPL240315C00180000",
          long_leg_symbol: "AAPL240315C00185000",
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Account ID not found in available accounts")
      end
    end

    context "with valid call spread order" do
      before do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_client).to receive(:place_order).and_return(mock_response)
      end

      it "places order successfully" do
        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "callspread",
          price: 1.50,
          quantity: 2,
          short_leg_symbol: "AAPL240315C00180000",
          long_leg_symbol: "AAPL240315C00185000",
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        content_text = response.content.first[:text]

        expect(content_text).to include("Callspread Order Placed")
        expect(content_text).to include("**Order ID**: 67890")
        expect(content_text).to include("Price: $1.5")
        expect(content_text).to include("Quantity: 2")
      end

      it "calls place_order with correct parameters" do
        expect(mock_client).to receive(:place_order).with("hash1", mock_order_builder)

        described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "callspread",
          price: 1.50,
          short_leg_symbol: "AAPL240315C00180000",
          long_leg_symbol: "AAPL240315C00185000",
          server_context: {}
        )
      end
    end

    context "with valid iron condor order" do
      before do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_client).to receive(:place_order).and_return(mock_response)
      end

      it "places order successfully" do
        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "ironcondor",
          price: 2.50,
          put_short_symbol: "AAPL240315P00170000",
          put_long_symbol: "AAPL240315P00165000",
          call_short_symbol: "AAPL240315C00185000",
          call_long_symbol: "AAPL240315C00190000",
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        content_text = response.content.first[:text]

        expect(content_text).to include("Iron Condor Order Placed")
        expect(content_text).to include("Put Short: AAPL240315P00170000")
        expect(content_text).to include("Call Long: AAPL240315C00190000")
      end
    end

    context "when strategy validation fails" do
      it "returns error for missing call spread symbols" do
        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "callspread",
          price: 1.50,
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("callspread strategy requires")
      end
    end

    context "when order placement fails" do
      before do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_response).to receive(:status).and_return(400)
        allow(mock_response).to receive(:body).and_return('{"error": "Invalid order"}')
        allow(mock_client).to receive(:place_order).and_return(mock_response)
      end

      it "returns error response" do
        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          strategy_type: "callspread",
          price: 1.50,
          short_leg_symbol: "AAPL240315C00180000",
          long_leg_symbol: "AAPL240315C00185000",
          server_context: {}
        )

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Order placement failed (HTTP 400)")
      end
    end
  end
end
