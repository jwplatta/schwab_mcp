
require "spec_helper"
require "schwab_mcp/tools/list_account_transactions_tool"
require "schwab_rb/data_objects/transaction"

RSpec.describe SchwabMCP::Tools::ListAccountTransactionsTool do
  let(:server_context) { double("server_context") }
  let(:account_name) { "TRADING_BROKERAGE_ACCOUNT" }
  let(:transaction_hash) do
    {
      activityId: "A123",
      time: "2025-07-21T10:00:00Z",
      type: "TRADE",
      status: "EXECUTED",
      subAccount: "CASH",
      tradeDate: "2025-07-21",
      positionId: "P123",
      orderId: "O123",
      netAmount: 100.0,
      transferItems: [
        {
          instrument: {
            symbol: "AAPL",
            assetType: "EQUITY",
            description: "Apple Inc."
          },
          amount: 1,
          cost: 100.0
        }
      ]
    }
  end

  describe ".format_transactions_data" do
    it "formats a single transaction object" do
      transaction = SchwabRb::DataObjects::Transaction.build(transaction_hash)
      result = described_class.send(:format_transactions_data, [transaction], account_name, {})
      expect(result).to include("A123")
      expect(result).to include("TRADE")
      expect(result).to include("Apple Inc.")
      expect(result).to include("Total Transactions: 1")
    end

    it "shows no transactions if array is empty" do
      result = described_class.send(:format_transactions_data, [], account_name, {})
      expect(result).to include("No transactions found")
    end
  end

  describe ".call" do
    let(:client) { double("client") }
    let(:account_numbers_response) { double("response", body: [{ accountNumber: "123", hashValue: "abc" }].to_json) }
    let(:transactions_response) { double("response", body: [transaction_hash]) }

    before do
      stub_const("ENV", ENV.to_hash.merge(account_name => "123"))
      allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(client)
      allow(client).to receive(:get_account_numbers).and_return(account_numbers_response)
      allow(client).to receive(:get_transactions).and_return(transactions_response)
    end

    it "returns formatted transactions text" do
      response = described_class.call(account_name: account_name, server_context: server_context)
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.instance_variable_get(:@content).first[:text]).to include("A123")
      expect(response.instance_variable_get(:@content).first[:text]).to include("Apple Inc.")
    end

    it "returns error if account name is missing in ENV" do
      stub_const("ENV", ENV.to_hash.reject { |k, _| k == account_name })
      response = described_class.call(account_name: account_name, server_context: server_context)
      expect(response.instance_variable_get(:@content).first[:text]).to include("not found in environment variables")
    end
  end
end
