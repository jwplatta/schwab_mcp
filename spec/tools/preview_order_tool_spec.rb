
require 'spec_helper'

RSpec.describe SchwabMCP::Tools::PreviewOrderTool do
  let(:client) { double('SchwabRb::Client') }
  let(:order_preview) do
    instance_double(
      'SchwabRb::DataObjects::OrderPreview',
      status: 'ACCEPTED',
      price: 1.23,
      quantity: 2,
      commission: 0.65,
      fees: 0.05,
      accepted?: true,
      to_h: { status: 'ACCEPTED', price: 1.23, quantity: 2, commission: 0.65, fees: 0.05 }
    )
  end
  let(:account_numbers) do
    [double('AccountNumber', account_number: '12345678', hash_value: 'abc123')]
  end

  before do
    allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(client)
    allow(client).to receive(:get_account_numbers).with(any_args).and_return(account_numbers)
    allow(client).to receive(:preview_order).and_return(order_preview)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('TRADING_BROKERAGE_ACCOUNT').and_return('12345678')
  end

  it 'returns a formatted preview response for a callspread' do
    params = {
      account_name: 'TRADING_BROKERAGE_ACCOUNT',
      strategy_type: 'callspread',
      price: 1.23,
      quantity: 2,
      short_leg_symbol: 'CALLSHORT',
      long_leg_symbol: 'CALLLONG'
    }
    resp = described_class.call(server_context: nil, **params)
    expect(resp).to be_a(MCP::Tool::Response)
    expect(resp.content.first[:text]).to include('**Preview Result:**')
    expect(resp.content.first[:text]).to include('ACCEPTED')
    expect(resp.content.first[:text]).to include('CALLSHORT')
    expect(resp.content.first[:text]).to include('CALLLONG')
  end

  it 'returns an error if account name is invalid' do
    params = {
      account_name: 'INVALID',
      strategy_type: 'callspread',
      price: 1.23,
      quantity: 2,
      short_leg_symbol: 'CALLSHORT',
      long_leg_symbol: 'CALLLONG'
    }
    resp = described_class.call(server_context: nil, **params)
    expect(resp.content.first[:text]).to match(/Account name must end with '_ACCOUNT'/)
  end
end
