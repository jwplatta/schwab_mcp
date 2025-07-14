# frozen_string_literal: true

require 'schwab_rb'

module SchwabMCP
  module Orders
    class IronCondorOrder
      class << self
        def build(
          account_number:,
          put_short_symbol:,
          put_long_symbol:,
          call_short_symbol:,
          call_long_symbol:,
          price:,
          order_instruction: :open,
          quantity: 1
        )
          schwab_order_builder.new.tap do |builder|
            builder.set_account_number(account_number)
            builder.set_order_strategy_type('SINGLE')
            builder.set_session(SchwabRb::Orders::Session::NORMAL)
            builder.set_duration(SchwabRb::Orders::Duration::DAY)
            builder.set_order_type(order_type(order_instruction))
            builder.set_complex_order_strategy_type(SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR)
            builder.set_quantity(quantity)
            builder.set_price(price)

            instructions = leg_instructions_for_position(order_instruction)

            builder.add_option_leg(
              instructions[:put_short],
              put_short_symbol,
              quantity
            )
            builder.add_option_leg(
              instructions[:put_long],
              put_long_symbol,
              quantity
            )
            builder.add_option_leg(
              instructions[:call_short],
              call_short_symbol,
              quantity
            )
            builder.add_option_leg(
              instructions[:call_long],
              call_long_symbol,
              quantity
            )
          end
        end

        def order_type(order_instruction)
          if order_instruction == :open
            SchwabRb::Order::Types::NET_CREDIT
          else
            SchwabRb::Order::Types::NET_DEBIT
          end
        end

        def leg_instructions_for_position(order_instruction)
          case order_instruction
          when :open
            {
              put_short: SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN,
              put_long: SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN,
              call_short: SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN,
              call_long: SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN
            }
          when :exit
            {
              put_short: SchwabRb::Orders::OptionInstructions::BUY_TO_CLOSE,
              put_long: SchwabRb::Orders::OptionInstructions::SELL_TO_CLOSE,
              call_short: SchwabRb::Orders::OptionInstructions::BUY_TO_CLOSE,
              call_long: SchwabRb::Orders::OptionInstructions::SELL_TO_CLOSE
            }
          end
        end

        def schwab_order_builder
          SchwabRb::Orders::Builder
        end
      end
    end
  end
end
