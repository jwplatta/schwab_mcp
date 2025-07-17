require "mcp"
require "schwab_rb"
require "json"
require "date"
require_relative "../loggable"
require_relative "../option_chain_filter"

module SchwabMCP
  module Tools
    class OptionStrategyFinderTool < MCP::Tool
      extend Loggable
      description "Find option strategies (iron condor, call spread, put spread) using Schwab API"

      input_schema(
        properties: {
          strategy_type: {
            type: "string",
            description: "Type of option strategy to find",
            enum: ["ironcondor", "callspread", "putspread"]
          },
          underlying_symbol: {
            type: "string",
            description: "Underlying symbol for the options (e.g., '$SPX', 'SPY')",
            pattern: "^[A-Za-z$]{1,6}$"
          },
          expiration_date: {
            type: "string",
            description: "Target expiration date for options (YYYY-MM-DD format)"
          },
          expiration_type: {
            type: "string",
            description: "Type of expiration (e.g., 'W' for weekly, 'M' for monthly)",
            enum: ["W", "M", "Q"]
          },
          settlement_type: {
            type: "string",
            description: "Settlement type (e.g., 'P' for PM settled, 'A' for AM settled)",
            enum: ["P", "A"]
          },
          option_root: {
            type: "string",
            description: "Option root symbol (e.g., 'SPXW' for weekly SPX options)"
          },
          max_delta: {
            type: "number",
            description: "Maximum absolute delta for short legs (default: 0.15)",
            minimum: 0.01,
            maximum: 1.0
          },
          max_spread: {
            type: "number",
            description: "Maximum spread width in dollars (default: 20.0)",
            minimum: 1.0
          },
          min_credit: {
            type: "number",
            description: "Minimum credit received in dollars (default: 100.0)",
            minimum: 0.01
          },
          min_open_interest: {
            type: "integer",
            description: "Minimum open interest for options (default: 0)",
            minimum: 0
          },
          dist_from_strike: {
            type: "number",
            description: "Minimum distance from current price as percentage (default: 0.07)",
            minimum: 0.0,
            maximum: 1.0
          },
          quantity: {
            type: "integer",
            description: "Number of contracts per leg (default: 1)",
            minimum: 1
          },
          from_date: {
            type: "string",
            description: "Start date for expiration search (YYYY-MM-DD format)"
          },
          to_date: {
            type: "string",
            description: "End date for expiration search (YYYY-MM-DD format)"
          }
        },
        required: ["strategy_type", "underlying_symbol", "expiration_date"]
      )

      annotations(
        title: "Find Option Strategy",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(strategy_type:, underlying_symbol:, expiration_date:,
                    expiration_type: nil, settlement_type: nil, option_root: nil,
                    max_delta: 0.15, max_spread: 20.0, min_credit: 0.0,
                    min_open_interest: 0, dist_from_strike: 0.0, quantity: 1,
                    from_date: nil, to_date: nil, server_context:)

        log_info("Finding #{strategy_type} strategy for #{underlying_symbol} expiring #{expiration_date}")

        begin
          unless %w[ironcondor callspread putspread].include?(strategy_type.downcase)
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Invalid strategy type '#{strategy_type}'. Must be one of: ironcondor, callspread, putspread"
            }])
          end

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

          exp_date = Date.parse(expiration_date)
          from_dt = from_date ? Date.parse(from_date) : exp_date
          to_dt = to_date ? Date.parse(to_date) : exp_date

          contract_type = strategy_type.downcase == 'callspread' ? 'CALL' :
                         strategy_type.downcase == 'putspread' ? 'PUT' : 'ALL'

          log_debug("Fetching option chain for #{underlying_symbol} (#{contract_type})")

          response = client.get_option_chain(
            underlying_symbol.upcase,
            contract_type: contract_type,
            from_date: from_dt,
            to_date: to_dt,
            include_underlying_quote: true
          )

          unless response&.body
            log_warn("Empty response from Schwab API for #{underlying_symbol}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Could not retrieve option chain for #{underlying_symbol}"
            }])
          end

          option_data = JSON.parse(response.body, symbolize_names: true)

          result = find_strategy(
            strategy_type: strategy_type.downcase,
            option_data: option_data,
            underlying_symbol: underlying_symbol,
            expiration_date: exp_date,
            expiration_type: expiration_type,
            settlement_type: settlement_type,
            option_root: option_root,
            max_delta: max_delta,
            max_spread: max_spread,
            min_credit: min_credit,
            min_open_interest: min_open_interest,
            dist_from_strike: dist_from_strike,
            quantity: quantity
          )

          if result.nil? || result[:status] == 'not_found'
            log_info("No suitable #{strategy_type} found for #{underlying_symbol}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**No Strategy Found**: Could not find a suitable #{strategy_type} for #{underlying_symbol} with the specified criteria."
            }])
          else
            log_info("Found #{strategy_type} strategy for #{underlying_symbol}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: format_strategy_result(result, strategy_type)
            }])
          end
        rescue Date::Error => e
          log_error("Invalid date format: #{e.message}")
          return MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Invalid date format. Use YYYY-MM-DD format."
          }])
        rescue JSON::ParserError => e
          log_error("Failed to parse option chain data: #{e.message}")
          return MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Failed to parse option chain data from Schwab API."
          }])
        rescue => e
          log_error("Error finding #{strategy_type} for #{underlying_symbol}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          return MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** finding #{strategy_type} for #{underlying_symbol}: #{e.message}"
          }])
        end
      end

      private

      def self.find_strategy(strategy_type:, option_data:, underlying_symbol:, expiration_date:,
                            expiration_type:, settlement_type:, option_root:, max_delta:,
                            max_spread:, min_credit:, min_open_interest:, dist_from_strike:, quantity:)

        case strategy_type
        when 'ironcondor'
          find_iron_condor(option_data, underlying_symbol, expiration_date, expiration_type,
                          settlement_type, option_root, max_delta, max_spread, min_credit / 2.0,
                          min_open_interest, dist_from_strike, quantity)
        when 'callspread'
          find_spread(option_data, 'call', underlying_symbol, expiration_date, expiration_type,
                     settlement_type, option_root, max_delta, max_spread, min_credit,
                     min_open_interest, dist_from_strike, quantity)
        when 'putspread'
          find_spread(option_data, 'put', underlying_symbol, expiration_date, expiration_type,
                     settlement_type, option_root, max_delta, max_spread, min_credit,
                     min_open_interest, dist_from_strike, quantity)
        end
      end

      def self.find_iron_condor(option_data, underlying_symbol, expiration_date, expiration_type,
                               settlement_type, option_root, max_delta, max_spread, min_credit,
                               min_open_interest, dist_from_strike, quantity)

        underlying_price = option_data.dig(:underlyingPrice) || 0.0
        call_options = option_data.dig(:callExpDateMap) || {}
        put_options = option_data.dig(:putExpDateMap) || {}

        filter = SchwabMCP::OptionChainFilter.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          expiration_type: expiration_type,
          settlement_type: settlement_type,
          option_root: option_root,
          max_delta: max_delta,
          max_spread: max_spread,
          min_credit: min_credit,
          min_open_interest: min_open_interest,
          dist_from_strike: dist_from_strike,
          quantity: quantity
        )

        call_spreads = filter.find_spreads(call_options, 'call')
        put_spreads = filter.find_spreads(put_options, 'put')

        return { status: 'not_found' } if call_spreads.empty? || put_spreads.empty?

        best_combo = nil
        best_ratio = 0

        call_spreads.each do |call_spread|
          put_spreads.each do |put_spread|
            total_credit = call_spread[:credit] + put_spread[:credit]
            next if total_credit < min_credit / 100.0

            total_delta = call_spread[:delta].abs + put_spread[:delta].abs
            ratio = total_credit / total_delta if total_delta > 0

            if ratio > best_ratio
              best_ratio = ratio
              best_combo = {
                type: 'iron_condor',
                call_spread: call_spread,
                put_spread: put_spread,
                total_credit: total_credit,
                total_delta: total_delta,
                underlying_price: underlying_price
              }
            end
          end
        end

        best_combo || { status: 'not_found' }
      end

      def self.find_spread(option_data, spread_type, underlying_symbol, expiration_date, expiration_type,
                          settlement_type, option_root, max_delta, max_spread, min_credit,
                          min_open_interest, dist_from_strike, quantity)

        underlying_price = option_data.dig(:underlyingPrice) || 0.0
        options_map = case spread_type
                     when 'call'
                       option_data.dig(:callExpDateMap) || {}
                     when 'put'
                       option_data.dig(:putExpDateMap) || {}
                     else
                       return { status: 'not_found' }
                     end

        filter = SchwabMCP::OptionChainFilter.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          expiration_type: expiration_type,
          settlement_type: settlement_type,
          option_root: option_root,
          max_delta: max_delta,
          max_spread: max_spread,
          min_credit: min_credit,
          min_open_interest: min_open_interest,
          dist_from_strike: dist_from_strike,
          quantity: quantity
        )

        spreads = filter.find_spreads(options_map, spread_type)

        return { status: 'not_found' } if spreads.empty?

        best_spread = spreads.max_by { |spread| spread[:credit] }
        best_spread.merge(type: "#{spread_type}_spread", underlying_price: underlying_price)
      end

      def self.format_strategy_result(result, strategy_type)
        case result[:type]
        when 'iron_condor'
          format_iron_condor(result)
        when 'call_spread', 'put_spread'
          format_spread(result, result[:type])
        else
          "**Found Strategy**: #{strategy_type.upcase}\n\n#{result.to_json}"
        end
      end

      def self.format_iron_condor(result)
        call_spread = result[:call_spread]
        put_spread = result[:put_spread]

        <<~TEXT
          **IRON CONDOR FOUND**

          **Underlying Price**: $#{result[:underlying_price].round(2)}
          **Total Credit**: $#{(result[:total_credit] * 100).round(2)}

          **Call Spread (Short)**:
          - Short: #{call_spread[:short_option][:symbol]} $#{call_spread[:short_option][:strikePrice]} Call @ $#{call_spread[:short_option][:mark].round(2)}
          - Long:  #{call_spread[:long_option][:symbol]} $#{call_spread[:long_option][:strikePrice]} Call @ $#{call_spread[:long_option][:mark].round(2)}
          - Credit: $#{(call_spread[:credit] * 100).round(2)}
          - Width: $#{call_spread[:spread_width].round(2)}
          - Delta: #{call_spread[:delta].round(2)}

          **Put Spread (Short)**:
          - Short: #{put_spread[:short_option][:symbol]} $#{put_spread[:short_option][:strikePrice]} Put @ $#{put_spread[:short_option][:mark].round(2)}
          - Long:  #{put_spread[:long_option][:symbol]} $#{put_spread[:long_option][:strikePrice]} Put @ $#{put_spread[:long_option][:mark].round(2)}
          - Credit: $#{(put_spread[:credit] * 100).round(2)}
          - Width: $#{put_spread[:spread_width].round(2)}
          - Delta: #{put_spread[:delta].round(2)}
        TEXT
      end

      def self.format_spread(result, spread_type)
        short_opt = result[:short_option]
        long_opt = result[:long_option]
        option_type = spread_type == 'call_spread' ? 'Call' : 'Put'

        <<~TEXT
          **#{option_type.upcase} SPREAD FOUND**

          **Underlying Price**: $#{result[:underlying_price].round(2)}
          **Credit**: $#{(result[:credit] * 100).round(2)}
          **Spread Width**: $#{result[:spread_width].round(2)}
          **Delta**: #{result[:delta].round(4)}

          **Short**: #{short_opt[:symbol]} $#{short_opt[:strikePrice]} #{option_type} @ $#{short_opt[:mark].round(2)}
          - Delta: #{short_opt[:delta]&.round(4)}
          - Open Interest: #{short_opt[:openInterest]}

          **Long**: #{long_opt[:symbol]} $#{long_opt[:strikePrice]} #{option_type} @ $#{long_opt[:mark].round(2)}
          - Delta: #{long_opt[:delta]&.round(4)}
          - Open Interest: #{long_opt[:openInterest]}
        TEXT
      end
    end
  end
end
