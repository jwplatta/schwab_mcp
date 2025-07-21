# frozen_string_literal: true


require 'spec_helper'
require 'schwab_mcp/schwab_client_factory'

RSpec.describe SchwabMCP::Tools::ListMoversTool do
  let(:server_context) { double('server_context') }
  let(:client) { double('SchwabRb::Client') }

  before do
    allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(client)
  end

  context 'when movers data is returned' do
    let(:mover1) do
      instance_double(
        SchwabRb::DataObjects::Mover,
        symbol: 'NVDA',
        description: 'NVIDIA CORP',
        net_change: 0.15,
        net_change_percentage: 0.09,
        volume: 83043184,
        last_price: 172.56
      )
    end

    let(:mover2) do
      instance_double(
        SchwabRb::DataObjects::Mover,
        symbol: 'AAPL',
        description: 'APPLE INC',
        net_change: -1.25,
        net_change_percentage: -0.68,
        volume: 45123456,
        last_price: 182.31
      )
    end

    let(:market_movers) do
      instance_double(
        SchwabRb::DataObjects::MarketMovers,
        count: 2,
        movers: [mover1, mover2]
      )
    end

    it 'returns formatted movers for $DJI index' do
      expect(client).to receive(:get_movers).with(
        '$DJI',
        sort_order: nil,
        frequency: nil
      ).and_return(market_movers)

      resp = described_class.call(index: '$DJI', server_context: server_context)

      expect(resp.content.first[:text]).to include('Market Movers for $DJI')
      expect(resp.content.first[:text]).to include('1. **NVDA** - NVIDIA CORP')
      expect(resp.content.first[:text]).to include('Last: $172.56')
      expect(resp.content.first[:text]).to include('Change: +0.15 (+0.09%)')
      expect(resp.content.first[:text]).to include('Volume: 83,043,184')
      expect(resp.content.first[:text]).to include('2. **AAPL** - APPLE INC')
      expect(resp.content.first[:text]).to include('Change: -1.25 (-0.68%)')
    end

    it 'includes sort order and frequency in header when provided' do
      expect(client).to receive(:get_movers).with(
        '$SPX',
        sort_order: 'PERCENT_CHANGE_UP',
        frequency: 5
      ).and_return(market_movers)

      resp = described_class.call(
        index: '$SPX',
        sort_order: 'PERCENT_CHANGE_UP',
        frequency: 5,
        server_context: server_context
      )

      expect(resp.content.first[:text]).to include('**Market Movers for $SPX** (sorted by PERCENT_CHANGE_UP) (frequency filter: 5)')
    end
  end

  context 'when no movers are returned' do
    let(:empty_market_movers) do
      instance_double(
        SchwabRb::DataObjects::MarketMovers,
        count: 0,
        movers: []
      )
    end

    it 'returns no data message' do
      expect(client).to receive(:get_movers).and_return(empty_market_movers)
      resp = described_class.call(index: '$DJI', server_context: server_context)
      expect(resp.content.first[:text]).to include('No movers found for index $DJI')
    end
  end

  context 'when nil is returned from API' do
    it 'returns no data message' do
      expect(client).to receive(:get_movers).and_return(nil)
      resp = described_class.call(index: '$DJI', server_context: server_context)
      expect(resp.content.first[:text]).to include('No movers found for index $DJI')
    end
  end

  context 'when Schwab client fails to initialize' do
    before do
      allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(nil)
    end

    it 'returns an error message' do
      resp = described_class.call(index: '$DJI', server_context: server_context)
      expect(resp.content.first[:text]).to include('Failed to initialize Schwab client')
    end
  end

  context 'when an exception is raised' do
    it 'returns an error message' do
      expect(client).to receive(:get_movers).and_raise(StandardError.new('API error'))
      resp = described_class.call(index: '$DJI', server_context: server_context)
      expect(resp.content.first[:text]).to include('Error')
      expect(resp.content.first[:text]).to include('API error')
    end
  end
end