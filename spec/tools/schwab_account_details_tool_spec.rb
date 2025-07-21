# frozen_string_literal: true

require "spec_helper"

RSpec.describe SchwabMCP::Tools::SchwabAccountDetailsTool do
  describe ".call" do
    let(:mock_client) { instance_double("SchwabRb::Client") }
    let(:account_numbers) { instance_double("SchwabRb::DataObjects::AccountNumbers") }
    let(:account) { instance_double("SchwabRb::DataObjects::Account") }
    let(:current_balances) { instance_double("SchwabRb::DataObjects::CurrentBalances") }
    let(:position) { instance_double("SchwabRb::DataObjects::Position") }
    let(:instrument) { instance_double("SchwabRb::DataObjects::Instrument") }

    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(mock_client)
      allow(ENV).to receive(:[]).with("TRADING_ACCOUNT").and_return("123456789")

      allow(account_numbers).to receive(:find_hash_value).with("123456789").and_return("hash123")
      allow(account_numbers).to receive(:size).and_return(1)
      
      allow(current_balances).to receive(:cash_balance).and_return(10000.50)
      allow(current_balances).to receive(:buying_power).and_return(20000.75)
      allow(current_balances).to receive(:liquidation_value).and_return(30000.25)
      allow(current_balances).to receive(:long_market_value).and_return(25000.00)
      allow(current_balances).to receive(:short_market_value).and_return(0.0)
      
      allow(instrument).to receive(:symbol).and_return("AAPL")
      allow(position).to receive(:instrument).and_return(instrument)
      allow(position).to receive(:long_quantity).and_return(100.0)
      allow(position).to receive(:short_quantity).and_return(0.0)
      allow(position).to receive(:market_value).and_return(15000.0)
      allow(position).to receive(:to_h).and_return({symbol: "AAPL", quantity: 100})
      
      allow(account).to receive(:type).and_return("MARGIN")
      allow(account).to receive(:account_number).and_return("123456789")
      allow(account).to receive(:current_balances).and_return(current_balances)
      allow(account).to receive(:positions).and_return([position])
    end

    context "with invalid account name format" do
      it "returns error for invalid account name" do
        response = described_class.call(account_name: "INVALID", server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Account name must end with '_ACCOUNT'")
      end
    end

    context "when client initialization fails" do
      it "returns error response" do
        allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(nil)
        
        response = described_class.call(account_name: "TRADING_ACCOUNT", server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to initialize Schwab client")
      end
    end

    context "when account not found in environment" do
      it "returns error response" do
        allow(ENV).to receive(:[]).with("MISSING_ACCOUNT").and_return(nil)
        allow(ENV).to receive(:keys).and_return(["TRADING_ACCOUNT"])
        
        response = described_class.call(account_name: "MISSING_ACCOUNT", server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("not found in environment variables")
      end
    end

    context "when account numbers API call fails" do
      it "returns error response" do
        allow(mock_client).to receive(:get_account_numbers).and_return(nil)
        
        response = described_class.call(account_name: "TRADING_ACCOUNT", server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to retrieve account numbers")
      end
    end

    context "when account ID not found in available accounts" do
      it "returns error response" do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(account_numbers).to receive(:find_hash_value).with("123456789").and_return(nil)
        
        response = described_class.call(account_name: "TRADING_ACCOUNT", server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Account ID not found in available accounts")
      end
    end

    context "when account information is successfully retrieved" do
      it "returns formatted account data" do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_client).to receive(:get_account).with("hash123", fields: nil).and_return(account)
        
        response = described_class.call(account_name: "TRADING_ACCOUNT", server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Account Information for Trading")
        expect(response.content.first[:text]).to include("MARGIN")
        expect(response.content.first[:text]).to include("$10000.50")
        expect(response.content.first[:text]).to include("$20000.75")
        expect(response.content.first[:text]).to include("AAPL")
        expect(response.content.first[:text]).to include("100.0 shares")
      end
    end

    context "when account API returns no data" do
      it "returns no data message" do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(mock_client).to receive(:get_account).with("hash123", fields: nil).and_return(nil)
        
        response = described_class.call(account_name: "TRADING_ACCOUNT", server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Empty response from Schwab API")
      end
    end
  end

  describe ".format_currency" do
    it "formats currency correctly" do
      expect(described_class.send(:format_currency, 1234.56)).to eq("1234.56")
      expect(described_class.send(:format_currency, nil)).to eq("0.00")
      expect(described_class.send(:format_currency, 0)).to eq("0.00")
    end
  end
end
