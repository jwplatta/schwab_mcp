require "spec_helper"

RSpec.describe SchwabMCP::Tools::GetPriceHistoryTool do
  let(:server_context) { double("server_context") }
  let(:client) { double("schwab_client") }

  before do
    allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(client)
  end

  context "when price history is returned with candles" do
    let(:price_history) do
      SchwabRb::DataObjects::PriceHistory.new(
        "symbol" => "AAPL",
        "empty" => false,
        "candles" => [
          { "open" => 100, "high" => 110, "low" => 95, "close" => 105, "volume" => 1000, "datetime" => 1_700_000_000_000 },
          { "open" => 105, "high" => 115, "low" => 104, "close" => 110, "volume" => 1200, "datetime" => 1_700_000_060_000 }
        ]
      )
    end

    it "returns a summary with candle count and JSON preview" do
      expect(client).to receive(:get_price_history).and_return(price_history)
      response = described_class.call(symbol: "AAPL", server_context: server_context)
      expect(response.content.first[:text]).to include("Retrieved 2 price candles")
      expect(response.content.first[:text]).to include("\"symbol\": \"AAPL\"")
      expect(response.content.first[:text]).to include("\"candles\"")
    end
  end

  context "when price history is empty" do
    let(:price_history) do
      SchwabRb::DataObjects::PriceHistory.new(
        "symbol" => "AAPL",
        "empty" => true,
        "candles" => []
      )
    end

    it "returns a no data available message" do
      expect(client).to receive(:get_price_history).and_return(price_history)
      response = described_class.call(symbol: "AAPL", server_context: server_context)
      expect(response.content.first[:text]).to include("No price data available")
    end
  end

  context "when Schwab client is not available" do
    it "returns a client error response" do
      allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(nil)
      expect(SchwabMCP::SchwabClientFactory).to receive(:client_error_response)
      described_class.call(symbol: "AAPL", server_context: server_context)
    end
  end

  context "when invalid start_datetime is given" do
    it "returns an error message" do
      response = described_class.call(symbol: "AAPL", start_datetime: "not-a-date", server_context: server_context)
      expect(response.content.first[:text]).to include("Invalid start_datetime format")
    end
  end

  context "when both period and start_datetime are given" do
    it "returns an error message" do
      response = described_class.call(symbol: "AAPL", period: 1, start_datetime: "2024-01-01T00:00:00Z", server_context: server_context)
      expect(response.content.first[:text]).to include("Cannot use start_datetime/end_datetime with period_type/period")
    end
  end
end
