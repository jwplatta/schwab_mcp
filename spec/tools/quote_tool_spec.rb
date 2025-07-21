
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SchwabMCP::Tools::QuoteTool do
  let(:server_context) { double('server_context') }
  let(:client) { double('SchwabRb::Client') }

  before do
    allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(client)
  end

  context 'when quote is for an equity' do
    let(:equity_quote) do
      obj = instance_double(
        SchwabRb::DataObjects::EquityQuote,
        symbol: 'AAPL',
        last_price: 200.0,
        bid_price: 199.5,
        ask_price: 200.5,
        mark: 200.0,
        net_change: 1.0,
        net_percent_change: 0.5,
        total_volume: 1000000
      )
      allow(obj).to receive(:is_a?).with(SchwabRb::DataObjects::EquityQuote).and_return(true)
      allow(SchwabRb::DataObjects::EquityQuote).to receive(:===).with(obj).and_return(true)
      obj
    end

    it 'returns formatted equity quote' do
      expect(client).to receive(:get_quote).with('AAPL', return_data_objects: true).and_return(equity_quote)
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('Equity: AAPL')
      expect(resp.content.first[:text]).to include('Last: 200.0')
    end
  end

  context 'when quote is for an option' do
    let(:option_quote) do
      obj = instance_double(
        SchwabRb::DataObjects::OptionQuote,
        symbol: 'AAPL_072525C200',
        last_price: 5.0,
        bid_price: 4.9,
        ask_price: 5.1,
        mark: 5.0,
        delta: 0.5,
        gamma: 0.1,
        volatility: 0.2,
        open_interest: 100,
        expiration_month: 7,
        expiration_day: 25,
        expiration_year: 2025,
        strike_price: 200
      )
      allow(obj).to receive(:is_a?).with(SchwabRb::DataObjects::OptionQuote).and_return(true)
      allow(SchwabRb::DataObjects::OptionQuote).to receive(:===).with(obj).and_return(true)
      obj
    end

    it 'returns formatted option quote' do
      expect(client).to receive(:get_quote).with('AAPL_072525C200', return_data_objects: true).and_return(option_quote)
      resp = described_class.call(symbol: 'AAPL_072525C200', server_context: server_context)
      expect(resp.content.first[:text]).to include('Option: AAPL_072525C200')
      expect(resp.content.first[:text]).to include('Last: 5.0')
      expect(resp.content.first[:text]).to include('Strike: 200')
    end
  end

  context 'when Schwab client fails to initialize' do
    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(nil)
    end
    it 'returns an error message' do
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('Failed to initialize Schwab client')
    end
  end

  context 'when no quote is returned' do
    it 'returns a no data message' do
      expect(client).to receive(:get_quote).and_return(nil)
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('No quote data returned')
    end
  end

  context 'when an exception is raised' do
    it 'returns an error message' do
      expect(client).to receive(:get_quote).and_raise(StandardError.new('API error'))
      resp = described_class.call(symbol: 'AAPL', server_context: server_context)
      expect(resp.content.first[:text]).to include('Error')
      expect(resp.content.first[:text]).to include('API error')
    end
  end
end
