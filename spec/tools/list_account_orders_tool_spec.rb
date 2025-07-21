# frozen_string_literal: true

require "spec_helper"

RSpec.describe SchwabMCP::Tools::ListAccountOrdersTool do
  describe ".call" do
    let(:mock_client) { instance_double("SchwabRb::Client") }
    let(:account_numbers) { instance_double("SchwabRb::DataObjects::AccountNumbers") }
    let(:account1) { instance_double("SchwabRb::DataObjects::AccountNumbers::AccountNumber") }
    let(:mock_order) { instance_double("SchwabRb::DataObjects::Order") }
    let(:mock_leg) { instance_double("SchwabRb::DataObjects::OrderLeg") }
    let(:mock_instrument) { instance_double("SchwabRb::DataObjects::Instrument") }

    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(mock_client)
      allow(account1).to receive(:account_number).and_return("123456789")
      allow(account1).to receive(:hash_value).and_return("hash1")

      allow(account_numbers).to receive(:size).and_return(1)
      allow(account_numbers).to receive(:find_hash_value).with("123456789").and_return("hash1")

      # Set up mock order data
      allow(mock_order).to receive(:order_id).and_return("12345")
      allow(mock_order).to receive(:status).and_return("FILLED")
      allow(mock_order).to receive(:order_type).and_return("MARKET")
      allow(mock_order).to receive(:duration).and_return("DAY")
      allow(mock_order).to receive(:entered_time).and_return("2023-01-01T10:00:00Z")
      allow(mock_order).to receive(:close_time).and_return("2023-01-01T10:30:00Z")
      allow(mock_order).to receive(:quantity).and_return(100)
      allow(mock_order).to receive(:filled_quantity).and_return(100)
      allow(mock_order).to receive(:price).and_return(150.50)
      allow(mock_order).to receive(:order_leg_collection).and_return([mock_leg])
      allow(mock_order).to receive(:to_h).and_return({
        "orderId" => "12345",
        "status" => "FILLED"
      })

      allow(mock_leg).to receive(:instruction).and_return("BUY")
      allow(mock_leg).to receive(:instrument).and_return(mock_instrument)
      allow(mock_instrument).to receive(:symbol).and_return("AAPL")
    end

    context "when client initialization fails" do
      it "returns error response" do
        allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(nil)

        response = described_class.call(account_name: "TRADING_BROKERAGE_ACCOUNT", server_context: {})

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to initialize Schwab client")
      end
    end

    context "when account name format is invalid" do
      it "returns error response" do
        response = described_class.call(account_name: "INVALID_NAME", server_context: {})

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Account name must end with '_ACCOUNT'")
      end
    end

    context "when account numbers retrieval fails" do
      it "returns error response" do
        allow(mock_client).to receive(:get_account_numbers).and_return(nil)

        response = described_class.call(account_name: "TRADING_BROKERAGE_ACCOUNT", server_context: {})

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to retrieve account numbers")
      end
    end

    context "when account hash not found" do
      it "returns error response" do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(account_numbers).to receive(:find_hash_value).with("123456789").and_return(nil)

        response = described_class.call(account_name: "TRADING_BROKERAGE_ACCOUNT", server_context: {})

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Account ID not found in available accounts")
      end
    end

    context "when orders retrieval succeeds" do
      before do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_client).to receive(:get_account_orders).and_return([mock_order])
      end

      it "returns formatted orders response" do
        response = described_class.call(account_name: "TRADING_BROKERAGE_ACCOUNT", server_context: {})

        expect(response).to be_a(MCP::Tool::Response)
        content_text = response.content.first[:text]
        
        expect(content_text).to include("Orders for Trading Brokerage (TRADING_BROKERAGE_ACCOUNT)")
        expect(content_text).to include("Total Orders: 1")
        expect(content_text).to include("Order ID: 12345")
        expect(content_text).to include("Status: FILLED")
        expect(content_text).to include("AAPL - BUY")
      end

      it "calls get_account_orders with correct parameters" do
        expect(mock_client).to receive(:get_account_orders).with(
          "hash1",
          hash_including(
            max_results: nil,
            from_entered_datetime: nil,
            to_entered_datetime: nil,
            status: nil
          )
        )

        described_class.call(account_name: "TRADING_BROKERAGE_ACCOUNT", server_context: {})
      end
    end

    context "with date filters" do
      before do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_client).to receive(:get_account_orders).and_return([mock_order])
      end

      it "formats dates correctly and includes them in the call" do
        expect(mock_client).to receive(:get_account_orders).with(
          "hash1",
          hash_including(
            from_entered_datetime: DateTime.parse("2023-01-01T00:00:00Z"),
            to_entered_datetime: DateTime.parse("2023-01-31T23:59:59Z")
          )
        )

        response = described_class.call(
          account_name: "TRADING_BROKERAGE_ACCOUNT",
          from_date: "2023-01-01",
          to_date: "2023-01-31",
          server_context: {}
        )
        
        expect(response.content.first[:text]).to include("From Date: 2023-01-01")
        expect(response.content.first[:text]).to include("To Date: 2023-01-31")
      end
    end

    context "when no orders are found" do
      before do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_client).to receive(:get_account_orders).and_return([])
      end

      it "returns message indicating no orders found" do
        response = described_class.call(account_name: "TRADING_BROKERAGE_ACCOUNT", server_context: {})

        expect(response).to be_a(MCP::Tool::Response)
        content_text = response.content.first[:text]
        
        expect(content_text).to include("Total Orders: 0")
        expect(content_text).to include("No orders found matching the specified criteria")
      end
    end
  end
end
