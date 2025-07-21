# frozen_string_literal: true

require "rspec"
require "mcp"
require_relative "../../lib/schwab_mcp/tools/list_schwab_accounts_tool"

RSpec.describe SchwabMCP::Tools::ListSchwabAccountsTool do
  describe ".call" do
    let(:mock_client) { instance_double("SchwabRb::Client") }
    let(:account_numbers) { instance_double("SchwabRb::DataObjects::AccountNumbers") }
    let(:account1) { instance_double("SchwabRb::DataObjects::AccountNumbers::AccountNumber") }
    let(:account2) { instance_double("SchwabRb::DataObjects::AccountNumbers::AccountNumber") }

    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(mock_client)
      allow(account1).to receive(:account_number).and_return("123456789")
      allow(account1).to receive(:hash_value).and_return("hash1")
      allow(account2).to receive(:account_number).and_return("987654321")
      allow(account2).to receive(:hash_value).and_return("hash2")
      
      allow(account_numbers).to receive(:size).and_return(2)
      allow(account_numbers).to receive(:account_numbers).and_return(["123456789", "987654321"])
      allow(account_numbers).to receive(:accounts).and_return([account1, account2])
      allow(account_numbers).to receive(:find_by_account_number).with("123456789").and_return(account1)
      allow(account_numbers).to receive(:find_by_account_number).with("987654321").and_return(account2)
    end

    context "when client initialization fails" do
      it "returns error response" do
        allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(nil)
        
        response = described_class.call(server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to initialize Schwab client")
      end
    end

    context "when API call fails" do
      it "returns error response" do
        allow(mock_client).to receive(:get_account_numbers).and_return(nil)
        
        response = described_class.call(server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Failed to retrieve account numbers")
      end
    end

    context "when no accounts are configured" do
      it "returns no configured accounts message" do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(ENV).to receive(:each).and_return({}.each)
        
        response = described_class.call(server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("No Configured Accounts Found")
      end
    end

    context "when accounts are configured" do
      it "returns formatted list of accounts" do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers)
        allow(ENV).to receive(:each).and_yield("TRADING_BROKERAGE_ACCOUNT", "123456789")
        
        response = described_class.call(server_context: {})
        
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include("Configured Schwab Accounts")
        expect(response.content.first[:text]).to include("Trading Brokerage")
        expect(response.content.first[:text]).to include("TRADING_BROKERAGE_ACCOUNT")
      end
    end
  end

  describe ".find_configured_accounts" do
    let(:account_numbers) { instance_double("SchwabRb::DataObjects::AccountNumbers") }
    let(:account1) { instance_double("SchwabRb::DataObjects::AccountNumbers::AccountNumber") }

    before do
      allow(account1).to receive(:account_number).and_return("123456789")
      allow(account_numbers).to receive(:account_numbers).and_return(["123456789", "987654321"])
      allow(account_numbers).to receive(:find_by_account_number).with("123456789").and_return(account1)
    end

    it "finds configured accounts from environment variables" do
      allow(ENV).to receive(:each).and_yield("TRADING_ACCOUNT", "123456789")
      
      result = described_class.send(:find_configured_accounts, account_numbers)
      
      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq("TRADING_ACCOUNT")
      expect(result.first[:account_id]).to eq("123456789")
      expect(result.first[:account]).to eq(account1)
    end

    it "ignores non-account environment variables" do
      allow(ENV).to receive(:each).and_yield("API_KEY", "some_key")
      
      result = described_class.send(:find_configured_accounts, account_numbers)
      
      expect(result).to be_empty
    end
  end

  describe ".friendly_name_from_env_key" do
    it "converts environment key to friendly name" do
      result = described_class.send(:friendly_name_from_env_key, "TRADING_BROKERAGE_ACCOUNT")
      expect(result).to eq("Trading Brokerage")
    end

    it "handles single word accounts" do
      result = described_class.send(:friendly_name_from_env_key, "RETIREMENT_ACCOUNT")
      expect(result).to eq("Retirement")
    end
  end
end
