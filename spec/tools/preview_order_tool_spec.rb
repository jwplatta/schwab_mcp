
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

  before do
    allow(SchwabRb::Auth).to receive(:init_client_easy).and_return(client)
    allow(client).to receive(:available_account_names).and_return(['TRADING_BROKERAGE_ACCOUNT'])
    allow(client).to receive(:preview_order).and_return(order_preview)
  end

  it 'returns a formatted preview response for a callspread' do
    params = {
      account_name: 'TRADING_BROKERAGE_ACCOUNT',
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL,
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
      strategy_type: 'vertical',
      price: 1.23,
      quantity: 2,
      short_leg_symbol: 'CALLSHORT',
      long_leg_symbol: 'CALLLONG'
    }
    resp = described_class.call(server_context: nil, **params)
    expect(resp.content.first[:text]).to match(/Account name must end with '_ACCOUNT'/)
  end
end
