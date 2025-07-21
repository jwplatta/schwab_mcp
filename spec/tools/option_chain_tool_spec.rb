# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SchwabMCP::Tools::OptionChainTool do
  let(:server_context) { double('server_context') }
  let(:client) { double('SchwabRb::Client') }

  before do
    allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(client)
  end

  context 'when option chain is returned' do
    let(:option_chain) do
      double('option_chain', 
        symbol: 'AAPL',
        status: 'SUCCESS'
      )
    end

    it 'returns formatted option chain data' do
      expect(client).to receive(:get_option_chain).with('AAPL', return_data_objects: true).and_return(option_chain)
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('Symbol: AAPL')
      expect(resp.content.first[:text]).to include('Status: SUCCESS')
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
      expect(resp.content.first[:text]).to include('Symbol: AAPL')
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