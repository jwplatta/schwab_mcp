require "mcp"
require "schwab_rb"
require "date"
require_relative "../loggable"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class GetPriceHistoryTool < MCP::Tool
      extend Loggable
      description "Get price history data for an instrument symbol using Schwab API"

      input_schema(
        properties: {
          symbol: {
            type: "string",
            description: "Instrument symbol (e.g., 'AAPL', 'TSLA', '$SPX')",
            pattern: "^[\\$A-Za-z]{1,6}$"
          },
          period_type: {
            type: "string",
            description: "Type of period for the price history",
            enum: ["day", "month", "year", "ytd"]
          },
          period: {
            type: "integer",
            description: "Number of periods to retrieve. Valid values depend on period_type: day(1-10), month(1,2,3,6), year(1,2,3,5,10,15,20), ytd(1)"
          },
          frequency_type: {
            type: "string",
            description: "Type of frequency for the price history",
            enum: ["minute", "daily", "weekly", "monthly"]
          },
          frequency: {
            type: "integer",
            description: "Frequency of data points. Valid values depend on frequency_type: minute(1,5,10,15,30), daily(1), weekly(1), monthly(1)"
          },
          start_datetime: {
            type: "string",
            description: "Start date/time in ISO format (e.g., '2024-01-01T00:00:00Z'). Cannot be used with period/period_type."
          },
          end_datetime: {
            type: "string",
            description: "End date/time in ISO format (e.g., '2024-01-31T23:59:59Z'). Cannot be used with period/period_type."
          },
          need_extended_hours_data: {
            type: "boolean",
            description: "Include extended hours data (pre-market and after-hours)"
          },
          need_previous_close: {
            type: "boolean",
            description: "Include previous day's closing price"
          }
        },
        required: ["symbol"]
      )

      annotations(
        title: "Get Price History",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(symbol:, period_type: nil, period: nil, frequency_type: nil, frequency: nil,
                   start_datetime: nil, end_datetime: nil, need_extended_hours_data: nil,
                   need_previous_close: nil, server_context:)
        log_info("Getting price history for symbol: #{symbol}")

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          parsed_start = nil
          parsed_end = nil

          if start_datetime
            begin
              parsed_start = DateTime.parse(start_datetime)
            rescue ArgumentError
              return MCP::Tool::Response.new([{
                type: "text",
                text: "**Error**: Invalid start_datetime format. Use ISO format like '2024-01-01T00:00:00Z'"
              }])
            end
          end

          if end_datetime
            begin
              parsed_end = DateTime.parse(end_datetime)
            rescue ArgumentError
              return MCP::Tool::Response.new([{
                type: "text",
                text: "**Error**: Invalid end_datetime format. Use ISO format like '2024-01-31T23:59:59Z'"
              }])
            end
          end

          if (start_datetime || end_datetime) && (period_type || period)
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Cannot use start_datetime/end_datetime with period_type/period. Choose one approach."
            }])
          end

          period_type_enum = nil
          frequency_type_enum = nil

          if period_type
            case period_type
            when "day"
              period_type_enum = SchwabRb::PriceHistory::PeriodTypes::DAY
            when "month"
              period_type_enum = SchwabRb::PriceHistory::PeriodTypes::MONTH
            when "year"
              period_type_enum = SchwabRb::PriceHistory::PeriodTypes::YEAR
            when "ytd"
              period_type_enum = SchwabRb::PriceHistory::PeriodTypes::YEAR_TO_DATE
            end
          end

          if frequency_type
            case frequency_type
            when "minute"
              frequency_type_enum = SchwabRb::PriceHistory::FrequencyTypes::MINUTE
            when "daily"
              frequency_type_enum = SchwabRb::PriceHistory::FrequencyTypes::DAILY
            when "weekly"
              frequency_type_enum = SchwabRb::PriceHistory::FrequencyTypes::WEEKLY
            when "monthly"
              frequency_type_enum = SchwabRb::PriceHistory::FrequencyTypes::MONTHLY
            end
          end

          log_debug("Making price history API request for symbol: #{symbol}")

          price_history = client.get_price_history(
            symbol.upcase,
            period_type: period_type_enum,
            period: period,
            frequency_type: frequency_type_enum,
            frequency: frequency,
            start_datetime: parsed_start,
            end_datetime: parsed_end,
            need_extended_hours_data: need_extended_hours_data,
            need_previous_close: need_previous_close
          )

          if price_history
            log_info("Successfully retrieved price history for #{symbol}")

            summary = if price_history.empty?
              "No price data available for the specified parameters"
            else
              "Retrieved #{price_history.count} price candles\n" \
              "First candle: #{price_history.first_candle&.to_h}\n" \
              "Last candle: #{price_history.last_candle&.to_h}"
            end

            # Show a compact JSON representation for advanced users
            json_preview = begin
              require "json"
              JSON.pretty_generate(price_history.to_h)
            rescue
              price_history.to_h.inspect
            end

            MCP::Tool::Response.new([{
              type: "text",
              text: "**Price History for #{symbol.upcase}:**\n\n#{summary}\n\n```json\n#{json_preview}\n```"
            }])
          else
            log_warn("Empty response from Schwab API for symbol: #{symbol}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for symbol: #{symbol}"
            }])
          end

        rescue => e
          log_error("Error retrieving price history for #{symbol}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving price history for #{symbol}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end
    end
  end
end
