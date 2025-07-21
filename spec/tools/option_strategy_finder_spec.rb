# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/schwab_mcp/tools/option_strategy_finder_tool"

RSpec.describe SchwabMCP::Tools::OptionStrategyFinderTool do
  let(:server_context) { double("server_context") }
  let(:client) { instance_double("SchwabRb::Client") }
  let(:option_chain) { instance_double("SchwabRb::DataObjects::OptionChain") }

  let(:short_call_option) do
    instance_double("SchwabRb::DataObjects::Option",
                    symbol: "SPY240719C00550000",
                    strike: 550.0,
                    mark: 2.50,
                    bid: 2.45,
                    ask: 2.55,
                    delta: 0.12,
                    open_interest: 100,
                    expiration_date: Date.parse("2024-07-19"),
                    days_to_expiration: 7,
                    expiration_type: "W",
                    settlement_type: "P",
                    option_root: "SPY")
  end

  let(:long_call_option) do
    instance_double("SchwabRb::DataObjects::Option",
                    symbol: "SPY240719C00560000",
                    strike: 560.0,
                    mark: 1.50,
                    bid: 1.45,
                    ask: 1.55,
                    delta: 0.08,
                    open_interest: 80,
                    expiration_date: Date.parse("2024-07-19"),
                    days_to_expiration: 7,
                    expiration_type: "W",
                    settlement_type: "P",
                    option_root: "SPY")
  end

  let(:short_put_option) do
    instance_double("SchwabRb::DataObjects::Option",
                    symbol: "SPY240719P00520000",
                    strike: 520.0,
                    mark: 1.80,
                    bid: 1.75,
                    ask: 1.85,
                    delta: -0.10,
                    open_interest: 150,
                    expiration_date: Date.parse("2024-07-19"),
                    days_to_expiration: 7,
                    expiration_type: "W",
                    settlement_type: "P",
                    option_root: "SPY")
  end

  let(:long_put_option) do
    instance_double("SchwabRb::DataObjects::Option",
                    symbol: "SPY240719P00510000",
                    strike: 510.0,
                    mark: 1.20,
                    bid: 1.15,
                    ask: 1.25,
                    delta: -0.06,
                    open_interest: 120,
                    expiration_date: Date.parse("2024-07-19"),
                    days_to_expiration: 7,
                    expiration_type: "W",
                    settlement_type: "P",
                    option_root: "SPY")
  end

  before do
    allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(client)
    allow(option_chain).to receive(:underlying_price).and_return(535.0)
    allow(option_chain).to receive(:call_opts).and_return([short_call_option, long_call_option])
    allow(option_chain).to receive(:put_opts).and_return([short_put_option, long_put_option])
  end

  describe ".call" do
    context "with valid callspread strategy" do
      it "returns a successful response when options are found" do
        allow(client).to receive(:get_option_chain).and_return(option_chain)

        result = described_class.call(
          strategy_type: "callspread",
          underlying_symbol: "SPY",
          expiration_date: "2024-07-19",
          server_context: server_context
        )

        expect(result).to be_a(MCP::Tool::Response)
        expect(result.content.first[:type]).to eq("text")
        expect(result.content.first[:text]).to include("CALL SPREAD")
      end
    end

    context "with valid putspread strategy" do
      it "returns a successful response when options are found" do
        allow(client).to receive(:get_option_chain).and_return(option_chain)

        result = described_class.call(
          strategy_type: "putspread",
          underlying_symbol: "SPY",
          expiration_date: "2024-07-19",
          server_context: server_context
        )

        expect(result).to be_a(MCP::Tool::Response)
        expect(result.content.first[:type]).to eq("text")
        expect(result.content.first[:text]).to include("PUT SPREAD")
      end
    end

    context "with invalid strategy type" do
      it "returns an error response" do
        result = described_class.call(
          strategy_type: "invalid",
          underlying_symbol: "SPY",
          expiration_date: "2024-07-19",
          server_context: server_context
        )

        expect(result).to be_a(MCP::Tool::Response)
        expect(result.content.first[:text]).to include("**Error**: Invalid strategy type")
      end
    end

    context "when client creation fails" do
      it "returns client error response" do
        allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(nil)
        allow(SchwabMCP::SchwabClientFactory).to receive(:client_error_response).and_return(
          MCP::Tool::Response.new([{ type: "text", text: "Client error" }])
        )

        result = described_class.call(
          strategy_type: "callspread",
          underlying_symbol: "SPY",
          expiration_date: "2024-07-19",
          server_context: server_context
        )

        expect(result.content.first[:text]).to eq("Client error")
      end
    end

    context "when option chain is empty" do
      it "returns no data response" do
        allow(client).to receive(:get_option_chain).and_return(nil)

        result = described_class.call(
          strategy_type: "callspread",
          underlying_symbol: "SPY",
          expiration_date: "2024-07-19",
          server_context: server_context
        )

        expect(result.content.first[:text]).to include("**No Data**")
      end
    end

    context "with invalid date format" do
      it "returns date error response" do
        result = described_class.call(
          strategy_type: "callspread",
          underlying_symbol: "SPY",
          expiration_date: "invalid-date",
          server_context: server_context
        )

        expect(result.content.first[:text]).to include("**Error**: Invalid date format")
      end
    end

    context "when no suitable strategy is found" do
      it "returns not found response" do
        # Mock empty option arrays to simulate no suitable strategy
        allow(option_chain).to receive(:call_opts).and_return([])
        allow(option_chain).to receive(:put_opts).and_return([])
        allow(client).to receive(:get_option_chain).and_return(option_chain)

        result = described_class.call(
          strategy_type: "ironcondor",
          underlying_symbol: "SPY",
          expiration_date: "2024-07-19",
          server_context: server_context
        )

        expect(result.content.first[:text]).to include("**No Strategy Found**")
      end
    end
  end
end
