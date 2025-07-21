# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SchwabMCP::Tools::GetMarketHoursTool do
  let(:mock_client) { double('SchwabRb::Client') }
  let(:mock_market_hours_obj) { double('MarketHours', to_h: { 'equity' => { 'isOpen' => true } }) }

  before do
    allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(mock_client)
  end

  describe '.call' do
    context 'with valid markets parameter' do
      it 'returns market hours data using data objects' do
        allow(mock_client).to receive(:get_market_hours)
          .with(['equity'], date: nil, return_data_objects: true)
          .and_return(mock_market_hours_obj)

        response = described_class.call(markets: ['equity'], server_context: nil)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include('Market Hours for today')
      end

      it 'handles date parameter correctly' do
        allow(mock_client).to receive(:get_market_hours)
          .with(['equity'], date: Date.parse('2025-07-21'), return_data_objects: true)
          .and_return(mock_market_hours_obj)

        response = described_class.call(markets: ['equity'], date: '2025-07-21', server_context: nil)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include('Market Hours for 2025-07-21')
      end
    end

    context 'with invalid date format' do
      it 'returns error for invalid date' do
        response = described_class.call(markets: ['equity'], date: 'invalid-date', server_context: nil)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include('Invalid date format')
      end
    end

    context 'when no data is returned' do
      it 'handles nil response' do
        allow(mock_client).to receive(:get_market_hours).and_return(nil)

        response = described_class.call(markets: ['equity'], server_context: nil)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include('No Data')
      end
    end

    context 'when client creation fails' do
      it 'returns client error response' do
        allow(SchwabMCP::SchwabClientFactory).to receive(:create_client).and_return(nil)
        allow(SchwabMCP::SchwabClientFactory).to receive(:client_error_response)
          .and_return(MCP::Tool::Response.new([{ type: 'text', text: 'Client error' }]))

        response = described_class.call(markets: ['equity'], server_context: nil)

        expect(response.content.first[:text]).to include('Client error')
      end
    end

    context 'when API call raises exception' do
      it 'handles exceptions gracefully' do
        allow(mock_client).to receive(:get_market_hours).and_raise(StandardError, 'API Error')

        response = described_class.call(markets: ['equity'], server_context: nil)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content.first[:text]).to include('Error')
        expect(response.content.first[:text]).to include('API Error')
      end
    end
  end

  describe '.format_market_hours_object' do
    it 'formats object with to_h method' do
      obj = double('MarketHours', to_h: { 'equity' => { 'isOpen' => true } })
      result = described_class.format_market_hours_object(obj)
      expect(result).to include('equity')
    end

    it 'falls back to inspect for objects without to_h' do
      obj = double('MarketHours')
      allow(obj).to receive(:respond_to?).with(:to_h).and_return(false)
      allow(obj).to receive(:inspect).and_return('MarketHours object')

      result = described_class.format_market_hours_object(obj)
      expect(result).to eq('MarketHours object')
    end
  end
end