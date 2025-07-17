require "mcp"
require "schwab_rb"
require "json"
require "date"
require_relative "../loggable"
require_relative "../option_chain_filter"

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
            enum: ["CALL", "PUT", "ALL"]
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
            enum: ["SINGLE", "ANALYTICAL", "COVERED", "VERTICAL", "CALENDAR", "STRANGLE", "STRADDLE", "BUTTERFLY", "CONDOR", "DIAGONAL", "COLLAR", "ROLL"]
          },
          strike_range: {
            type: "string",
            description: "Range of strikes to include",
            enum: ["ITM", "NTM", "OTM", "SAK", "SBK", "SNK", "ALL"]
          },
          option_type: {
            type: "string",
            description: "Type of options to include in the chain",
            enum: ["S", "NS", "ALL"]
          },
          exp_month: {
            type: "string",
            description: "Filter options by expiration month",
            enum: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC", "ALL"]
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
            enum: ["PP", "NP", "PN"]
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

      def self.call(symbol:, contract_type: nil, strike_count: nil, include_underlying_quote: nil,
                    strategy: nil, strike_range: nil, option_type: nil, exp_month: nil,
                    interval: nil, strike: nil, from_date: nil, to_date: nil, volatility: nil,
                    underlying_price: nil, interest_rate: nil, days_to_expiration: nil,
                    entitlement: nil, max_delta: nil, min_delta: nil, max_strike: nil,
                    min_strike: nil, expiration_date: nil, server_context:)
        log_info("Getting option chain for symbol: #{symbol}")

        begin
          client = SchwabRb::Auth.init_client_easy(
            ENV['SCHWAB_API_KEY'],
            ENV['SCHWAB_APP_SECRET'],
            ENV['SCHWAB_CALLBACK_URI'],
            ENV['TOKEN_PATH']
          )

          unless client
            log_error("Failed to initialize Schwab client")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Failed to initialize Schwab client. Check your credentials."
            }])
          end

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
          response = client.get_option_chain(symbol.upcase, **params)

          if response&.body
            log_info("Successfully retrieved option chain for #{symbol}")

            if max_delta || min_delta || max_strike || min_strike
              begin
                parsed_response = JSON.parse(response.body, symbolize_names: true)

                log_debug("Applying option chain filtering")

                filter = SchwabMCP::OptionChainFilter.new(
                  expiration_date: Date.parse(expiration_date),
                  max_delta: max_delta || 1.0,
                  min_delta: min_delta || 0.0,
                  max_strike: max_strike,
                  min_strike: min_strike
                )

                filtered_response = parsed_response.dup

                if parsed_response[:callExpDateMap]
                  filtered_calls = filter.select(parsed_response[:callExpDateMap])
                  log_debug("Filtered #{filtered_calls.size} call options")

                  filtered_response[:callExpDateMap] = reconstruct_exp_date_map(
                    filtered_calls, expiration_date
                  )
                end

                if parsed_response[:putExpDateMap]
                  filtered_puts = filter.select(parsed_response[:putExpDateMap])
                  log_debug("Filtered #{filtered_puts.size} put options")

                  filtered_response[:putExpDateMap] = reconstruct_exp_date_map(
                    filtered_puts, expiration_date)
                end

                File.open("filtered_option_chain_#{symbol}_#{expiration_date}.json", "w") do |f|
                  f.write(JSON.pretty_generate(filtered_response))
                end

                return MCP::Tool::Response.new([{
                  type: "text",
                  text: "#{JSON.pretty_generate(filtered_response)}\n"
                }])
              rescue JSON::ParserError => e
                log_error("Failed to parse response for filtering: #{e.message}")
              rescue => e
                log_error("Error applying option chain filter: #{e.message}")
              end
            else
              log_debug("No filtering applied, returning full response")
              return MCP::Tool::Response.new([{
                type: "text",
                text: "#{JSON.pretty_generate(response.body)}\n"
              }])
            end
          else
            log_warn("Empty response from Schwab API for option chain: #{symbol}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for option chain: #{symbol}"
            }])
          end

        rescue => e
          log_error("Error retrieving option chain for #{symbol}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving option chain for #{symbol}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private

      def self.reconstruct_exp_date_map(filtered_options, target_expiration_date)
        return {} if filtered_options.empty?

        grouped = {}

        filtered_options.each do |option|
          exp_date_key = "#{target_expiration_date}:#{option[:daysToExpiration] || 0}"
          strike_key = "#{option[:strikePrice]}"

          grouped[exp_date_key] ||= {}
          grouped[exp_date_key][strike_key] ||= []
          grouped[exp_date_key][strike_key] << option
        end

        grouped
      end
    end
  end
end
