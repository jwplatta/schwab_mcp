# frozen_string_literal: true

require "mcp"
require "schwab_rb"
require "date"
require_relative "../loggable"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class OptionChainTool < MCP::Tool
      extend Loggable
      description "Get option chain data for an optionable symbol using Schwab API"

      input_schema(
        properties: {
          symbol: {
            type: "string",
            description: "Instrument symbol (e.g., 'AAPL', 'TSLA')",
            pattern: "^[A-Za-z]{1,5}$"
          },
          contract_type: {
            type: "string",
            description: "Type of contracts to return in the chain",
            enum: %w[CALL PUT ALL]
          },
          strike_count: {
            type: "integer",
            description: "Number of strikes above and below the ATM price",
            minimum: 1
          },
          include_underlying_quote: {
            type: "boolean",
            description: "Include a quote for the underlying instrument"
          },
          strategy: {
            type: "string",
            description: "Strategy type for the option chain",
            enum: %w[SINGLE ANALYTICAL COVERED VERTICAL CALENDAR STRANGLE STRADDLE BUTTERFLY
                     CONDOR DIAGONAL COLLAR ROLL]
          },
          strike_range: {
            type: "string",
            description: "Range of strikes to include",
            enum: %w[ITM NTM OTM SAK SBK SNK ALL]
          },
          option_type: {
            type: "string",
            description: "Type of options to include in the chain",
            enum: %w[S NS ALL]
          },
          exp_month: {
            type: "string",
            description: "Filter options by expiration month",
            enum: %w[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC ALL]
          },
          interval: {
            type: "number",
            description: "Strike interval for spread strategy chains"
          },
          strike: {
            type: "number",
            description: "Specific strike price for the option chain"
          },
          from_date: {
            type: "string",
            description: "Filter expirations after this date (YYYY-MM-DD format)"
          },
          to_date: {
            type: "string",
            description: "Filter expirations before this date (YYYY-MM-DD format)"
          },
          volatility: {
            type: "number",
            description: "Volatility for analytical calculations"
          },
          underlying_price: {
            type: "number",
            description: "Underlying price for analytical calculations"
          },
          interest_rate: {
            type: "number",
            description: "Interest rate for analytical calculations"
          },
          days_to_expiration: {
            type: "integer",
            description: "Days to expiration for analytical calculations"
          },
          entitlement: {
            type: "string",
            description: "Client entitlement",
            enum: %w[PP NP PN]
          },
          max_delta: {
            type: "number",
            description: "Maximum delta value for option filtering",
            minimum: 0,
            maximum: 1
          },
          min_delta: {
            type: "number",
            description: "Minimum delta value for option filtering",
            minimum: 0,
            maximum: 1
          },
          max_strike: {
            type: "number",
            description: "Maximum strike price for option filtering"
          },
          min_strike: {
            type: "number",
            description: "Minimum strike price for option filtering"
          },
          expiration_date: {
            type: "string",
            description: "Filter options by specific expiration date (YYYY-MM-DD format)"
          }
        },
        required: ["symbol"]
      )

      annotations(
        title: "Get Option Chain Data",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(
        symbol:, server_context:, contract_type: nil, strike_count: nil,
        include_underlying_quote: nil,
        strategy: nil, strike_range: nil,
        option_type: nil, exp_month: nil,
        interval: nil, strike: nil, from_date: nil, to_date: nil, volatility: nil,
        underlying_price: nil, interest_rate: nil, days_to_expiration: nil,
        entitlement: nil, max_delta: nil, min_delta: nil, max_strike: nil,
        min_strike: nil, expiration_date: nil
      )
        log_info("Getting option chain for symbol: #{symbol}")

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          params = {}
          params[:contract_type] = contract_type if contract_type
          params[:strike_count] = strike_count if strike_count
          params[:include_underlying_quote] = include_underlying_quote unless include_underlying_quote.nil?
          params[:strategy] = strategy if strategy
          params[:interval] = interval if interval
          params[:strike] = strike if strike
          params[:strike_range] = strike_range if strike_range

          if expiration_date
            exp_date = Date.parse(expiration_date)
            params[:from_date] = exp_date
            params[:to_date] = exp_date
          else
            params[:from_date] = Date.parse(from_date) if from_date
            params[:to_date] = Date.parse(to_date) if to_date
          end

          params[:volatility] = volatility if volatility
          params[:underlying_price] = underlying_price if underlying_price
          params[:interest_rate] = interest_rate if interest_rate
          params[:days_to_expiration] = days_to_expiration if days_to_expiration
          params[:exp_month] = exp_month if exp_month
          params[:option_type] = option_type if option_type
          params[:entitlement] = entitlement if entitlement

          log_debug("Making API request for option chain with params: #{params}")
          option_chain = client.get_option_chain(symbol.upcase, return_data_objects: true, **params)

          if option_chain
            log_info("Successfully retrieved option chain for #{symbol}")

            if max_delta || min_delta || max_strike || min_strike
              begin
                log_debug("Applying option chain filtering")

                filter = SchwabMCP::OptionChainFilter.new(
                  expiration_date: Date.parse(expiration_date),
                  max_delta: max_delta || 1.0,
                  min_delta: min_delta || 0.0,
                  max_strike: max_strike,
                  min_strike: min_strike
                )

                filtered_calls = filter.select(option_chain.call_opts)
                filtered_puts = filter.select(option_chain.put_opts)

                log_debug("Filtered #{filtered_calls.size} call options")
                log_debug("Filtered #{filtered_puts.size} put options")

                filtered_option_chain = create_filtered_option_chain(option_chain, filtered_calls, filtered_puts)

                MCP::Tool::Response.new([{
                                          type: "text",
                                          text: format_option_chain_response(filtered_option_chain)
                                        }])
              rescue StandardError => e
                log_error("Error applying option chain filter: #{e.message}")
              end
            else
              log_debug("No filtering applied, returning full response")
              MCP::Tool::Response.new([{
                                        type: "text",
                                        text: format_option_chain_response(option_chain)
                                      }])
            end
          else
            log_warn("Empty response from Schwab API for option chain: #{symbol}")
            MCP::Tool::Response.new([{
                                      type: "text",
                                      text: "**No Data**: Empty response from Schwab API for option chain: #{symbol}"
                                    }])
          end
        rescue StandardError => e
          log_error("Error retrieving option chain for #{symbol}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          error_text = "**Error** retrieving option chain for #{symbol}: #{e.message}\n\n"
          error_text += e.backtrace.first(3).join('\n')
          MCP::Tool::Response.new([{
                                    type: "text",
                                    text: error_text
                                  }])
        end
      end

      private_class_method def self.format_option_chain_response(data)
        return data.to_s if data.is_a?(Hash)

        output = []
        output << "**Option Chain for #{data.symbol}**"
        output << "Status: #{data.status}" if data.respond_to?(:status)
        output << "Underlying Price: $#{data.underlying_price}" if data.respond_to?(:underlying_price)
        output << ""

        strikes_hash = {}

        data.call_opts.each do |call_opt|
          strike = call_opt.strike
          strikes_hash[strike] ||= { call: nil, put: nil }
          strikes_hash[strike][:call] = call_opt
        end

        data.put_opts.each do |put_opt|
          strike = put_opt.strike
          strikes_hash[strike] ||= { call: nil, put: nil }
          strikes_hash[strike][:put] = put_opt
        end

        output << "| Call Symbol | Call Mark | Call Ask | Call Bid | Call Delta | Call Open Interest |" \
                  " Strike | Put Symbol | Put Mark | Put Ask | Put Bid | Put Delta | Put Open Interest |"
        output << "|-------------|-----------|----------|----------|------------|------------|" \
                  "--------|------------|----------|---------|---------|-----------|-----------|"

        # Sort strikes and create table rows
        strikes_hash.keys.sort.each do |strike|
          call_opt = strikes_hash[strike][:call]
          put_opt = strikes_hash[strike][:put]

          call_symbol = call_opt ? call_opt.symbol : ""
          call_mark = call_opt ? format_price(call_opt.mark) : ""
          call_ask = call_opt ? format_price(call_opt.ask) : ""
          call_bid = call_opt ? format_price(call_opt.bid) : ""
          call_delta = call_opt ? format_greek(call_opt.delta) : ""
          call_open_interest = call_opt ? format_count(call_opt.open_interest) : ""

          put_symbol = put_opt ? put_opt.symbol : ""
          put_mark = put_opt ? format_price(put_opt.mark) : ""
          put_ask = put_opt ? format_price(put_opt.ask) : ""
          put_bid = put_opt ? format_price(put_opt.bid) : ""
          put_delta = put_opt ? format_greek(put_opt.delta) : ""
          put_open_interest = put_opt ? format_count(put_opt.open_interest) : ""

          output << "| #{call_symbol} | #{call_mark} | #{call_ask} | #{call_bid} | #{call_delta} | #{call_open_interest} |" \
                    " #{strike} | #{put_symbol} | #{put_mark} | #{put_ask} | #{put_bid} | #{put_delta} | #{put_open_interest} |"
        end

        output.join("\n")
      end

      private_class_method def self.format_price(price)
        return "" if price.nil?

        price.zero? ? "0.00" : format("%.2f", price)
      end

      private_class_method def self.format_greek(greek)
        return "" if greek.nil?

        greek.zero? ? "0.00" : format("%.3f", greek)
      end

      private_class_method def self.format_count(count)
        return "" if count.nil?

        count.zero? ? "0" : count.to_s
      end


      private_class_method def self.create_filtered_option_chain(original_chain, filtered_calls, filtered_puts)
        # Create a simple object that mimics the original data object interface
        FilteredOptionChain.new(
          symbol: original_chain.symbol,
          status: original_chain.status,
          underlying_price: original_chain.underlying_price,
          call_opts: filtered_calls,
          put_opts: filtered_puts
        )
      end

      # Simple struct to hold filtered option chain data
      FilteredOptionChain = Struct.new(:symbol, :status, :underlying_price, :call_opts, :put_opts) do
        def respond_to?(method_name)
          super || members.include?(method_name)
        end
      end
    end
  end
end
