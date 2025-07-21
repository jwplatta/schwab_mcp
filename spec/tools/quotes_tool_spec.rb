# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SchwabMCP::Tools::QuotesTool do
  let(:server_context) { double('server_context') }
  let(:client) { double('SchwabRb::Client') }

  before do
    allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(client)
  end

  context 'when quotes are for equities' do
    let(:equity_quote1) do
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

    let(:equity_quote2) do
      obj = instance_double(
        SchwabRb::DataObjects::EquityQuote,
        symbol: 'TSLA',
        last_price: 250.0,
        bid_price: 249.5,
        ask_price: 250.5,
        mark: 250.0,
        net_change: -2.0,
        net_percent_change: -0.8,
        total_volume: 500000
      )
      allow(obj).to receive(:is_a?).with(SchwabRb::DataObjects::EquityQuote).and_return(true)
      allow(SchwabRb::DataObjects::EquityQuote).to receive(:===).with(obj).and_return(true)
      obj
    end

    it 'returns formatted equity quotes as hash' do
      quotes_data = { 'AAPL' => equity_quote1, 'TSLA' => equity_quote2 }
      expect(client).to receive(:get_quotes).with(['AAPL', 'TSLA'], fields: ['quote'], indicative: false, return_data_objects: true).and_return(quotes_data)
      
      resp = described_class.call(symbols: ['AAPL', 'TSLA'], server_context: server_context)
      
      expect(resp.content.first[:text]).to include('Equity: AAPL')
      expect(resp.content.first[:text]).to include('Equity: TSLA')
      expect(resp.content.first[:text]).to include('Last: 200.0')
      expect(resp.content.first[:text]).to include('Last: 250.0')
    end

    it 'returns formatted equity quotes as array' do
      quotes_data = [equity_quote1, equity_quote2]
      expect(client).to receive(:get_quotes).with(['AAPL', 'TSLA'], fields: ['quote'], indicative: false, return_data_objects: true).and_return(quotes_data)
      
      resp = described_class.call(symbols: ['AAPL', 'TSLA'], server_context: server_context)
      
      expect(resp.content.first[:text]).to include('Equity: AAPL')
      expect(resp.content.first[:text]).to include('Equity: TSLA')
    end
  end

  context 'when quotes are for options' do
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
      quotes_data = { 'AAPL_072525C200' => option_quote }
      expect(client).to receive(:get_quotes).with(['AAPL_072525C200'], fields: ['quote'], indicative: false, return_data_objects: true).and_return(quotes_data)
      
      resp = described_class.call(symbols: ['AAPL_072525C200'], server_context: server_context)
      
      expect(resp.content.first[:text]).to include('Option: AAPL_072525C200')
      expect(resp.content.first[:text]).to include('Last: 5.0')
      expect(resp.content.first[:text]).to include('Strike: 200')
      expect(resp.content.first[:text]).to include('Delta: 0.5')
    end
  end

  context 'with custom fields and indicative flag' do
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

    it 'passes fields and indicative parameters correctly' do
      quotes_data = { 'AAPL' => equity_quote }
      expect(client).to receive(:get_quotes).with(['AAPL'], fields: ['quote', 'fundamental'], indicative: true, return_data_objects: true).and_return(quotes_data)
      
      resp = described_class.call(symbols: ['AAPL'], fields: ['quote', 'fundamental'], indicative: true, server_context: server_context)
      
      expect(resp.content.first[:text]).to include('(fields: quote, fundamental)')
      expect(resp.content.first[:text]).to include('(indicative: true)')
    end
  end

  context 'when symbols input is a string' do
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

    it 'converts string to array' do
      quotes_data = { 'AAPL' => equity_quote }
      expect(client).to receive(:get_quotes).with(['AAPL'], fields: ['quote'], indicative: false, return_data_objects: true).and_return(quotes_data)
      
      resp = described_class.call(symbols: 'AAPL', server_context: server_context)
      
      expect(resp.content.first[:text]).to include('Equity: AAPL')
    end
  end

  context 'when Schwab client fails to initialize' do
    before do
      allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(nil)
    end

    it 'returns an error message' do
      resp = described_class.call(symbols: ['AAPL'], server_context: server_context)
      expect(resp.content.first[:text]).to include('Failed to initialize Schwab client')
    end
  end

  context 'when no quotes are returned' do
    it 'returns a no data message' do
      expect(client).to receive(:get_quotes).and_return(nil)
      resp = described_class.call(symbols: ['AAPL'], server_context: server_context)
      expect(resp.content.first[:text]).to include('No quote data returned')
    end
  end

  context 'when an exception is raised' do
    it 'returns an error message' do
      expect(client).to receive(:get_quotes).and_raise(StandardError.new('API error'))
      resp = described_class.call(symbols: ['AAPL'], server_context: server_context)
      expect(resp.content.first[:text]).to include('Error')
      expect(resp.content.first[:text]).to include('API error')
    end
  end

  context 'when some quotes are missing from hash' do
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

    it 'shows no data available for missing symbols' do
      quotes_data = { 'AAPL' => equity_quote }
      expect(client).to receive(:get_quotes).with(['AAPL', 'TSLA'], fields: ['quote'], indicative: false, return_data_objects: true).and_return(quotes_data)
      
      resp = described_class.call(symbols: ['AAPL', 'TSLA'], server_context: server_context)
      
      expect(resp.content.first[:text]).to include('Equity: AAPL')
      expect(resp.content.first[:text]).to include('TSLA: No data available')
    end
  end
end