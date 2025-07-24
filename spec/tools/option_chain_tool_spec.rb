# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SchwabMCP::Tools::OptionChainTool do
  let(:server_context) { double('server_context') }
  let(:client) { double('SchwabRb::Client') }

  before do
    allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(client)
  end

  context 'when option chain is returned' do
    let(:call_option) do
      double('call_option',
        symbol: 'AAPL240315C00180000',
        strike: 180.0,
        mark: 5.25,
        ask: 5.30,
        bid: 5.20,
        delta: 0.65,
        open_interest: 103
      )
    end

    let(:put_option) do
      double('put_option',
        symbol: 'AAPL240315P00180000',
        strike: 180.0,
        mark: 3.15,
        ask: 3.20,
        bid: 3.10,
        delta: -0.35,
        open_interest: 150
      )
    end

    let(:option_chain) do
      double('option_chain',
        symbol: 'AAPL',
        status: 'SUCCESS',
        underlying_price: 175.50,
        call_opts: [call_option],
        put_opts: [put_option]
      )
    end

    it 'returns formatted option chain data' do
      expect(client).to receive(:get_option_chain).with('AAPL', return_data_objects: true).and_return(option_chain)
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('**Option Chain for AAPL**')
      expect(resp.content.first[:text]).to include('Status: SUCCESS')
      expect(resp.content.first[:text]).to include('Underlying Price: $175.5')
      expect(resp.content.first[:text]).to include('| Call Symbol | Call Mark | Call Ask | Call Bid | Call Delta | Call Open Interest | Strike | Put Symbol | Put Mark | Put Ask | Put Bid | Put Delta | Put Open Interest |')
      expect(resp.content.first[:text]).to include('| AAPL240315C00180000 | 5.25 | 5.30 | 5.20 | 0.650 | 103 | 180.0 | AAPL240315P00180000 | 3.15 | 3.20 | 3.10 | -0.350 | 150 |')
    end

    it 'handles additional parameters' do
      expect(client).to receive(:get_option_chain).with(
        'AAPL',
        return_data_objects: true,
        contract_type: 'CALL',
        strike_count: 5
      ).and_return(option_chain)

      resp = described_class.call(
        symbol: 'AAPL',
        contract_type: 'CALL',
        strike_count: 5,
        server_context: server_context
      )
      expect(resp.content.first[:text]).to include('**Option Chain for AAPL**')
    end
  end

  context 'when Schwab client fails to initialize' do
    before do
      allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(nil)
      allow(SchwabMCP::SchwabClientFactory).to receive(:client_error_response).and_return(
        MCP::Tool::Response.new([{ type: "text", text: "Failed to initialize Schwab client" }])
      )
    end

    it 'returns an error message' do
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('Failed to initialize Schwab client')
    end
  end

  context 'when no option chain is returned' do
    it 'returns a no data message' do
      expect(client).to receive(:get_option_chain).and_return(nil)
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('Empty response from Schwab API')
    end
  end

  context 'when an exception is raised' do
    it 'returns an error message' do
      expect(client).to receive(:get_option_chain).and_raise(StandardError.new('API error'))
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('Error')
      expect(resp.content.first[:text]).to include('API error')
    end
  end
end