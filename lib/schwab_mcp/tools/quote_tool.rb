
# frozen_string_literal: true

require "mcp"
require "schwab_rb"
require_relative "../loggable"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class QuoteTool < MCP::Tool
      extend Loggable
      description "Get a real-time quote for a single instrument symbol using Schwab API"

      input_schema(
        properties: {
          symbol: {
            type: "string",
            description: "Instrument symbol (e.g., 'AAPL', 'TSLA', '$SPX')",
            pattern: '^[\$\^]?[A-Za-z0-9]{1,5}$'
          }
        },
        required: ["symbol"]
      )

      annotations(
        title: "Get Financial Instrument Quote",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(symbol:, server_context:)
        log_info("Getting quote for symbol: #{symbol}")

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          log_debug("Making API request for symbol: #{symbol}")
          quote_obj = client.get_quote(symbol.upcase)

          unless quote_obj
            log_warn("No quote data object returned for symbol: #{symbol}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: No quote data returned for symbol: #{symbol}"
            }])
          end

          formatted = format_quote_object(quote_obj)
          log_info("Successfully retrieved quote for #{symbol}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Quote for #{symbol.upcase}:**\n\n#{formatted}"
          }])

        rescue => e
          log_error("Error retrieving quote for #{symbol}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving quote for #{symbol}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      def self.format_quote_object(obj)
        case obj
        when SchwabRb::DataObjects::OptionQuote
          "Option: #{obj.symbol}\nLast: #{obj.last_price}  Bid: #{obj.bid_price}  Ask: #{obj.ask_price}  Mark: #{obj.mark}  Delta: #{obj.delta}  Gamma: #{obj.gamma}  Vol: #{obj.volatility}  OI: #{obj.open_interest}  Exp: #{obj.expiration_month}/#{obj.expiration_day}/#{obj.expiration_year}  Strike: #{obj.strike_price}"
        when SchwabRb::DataObjects::EquityQuote
          "Equity: #{obj.symbol}\nLast: #{obj.last_price}  Bid: #{obj.bid_price}  Ask: #{obj.ask_price}  Mark: #{obj.mark}  Net Chg: #{obj.net_change}  %Chg: #{obj.net_percent_change}  Vol: #{obj.total_volume}"
        when SchwabRb::DataObjects::IndexQuote
          "Index: #{obj.symbol}\nLast: #{obj.last_price}  Bid: N/A  Ask: N/A  Mark: #{obj.mark}  Net Chg: #{obj.net_change}  %Chg: #{obj.net_percent_change}  Vol: #{obj.total_volume}"
        else
          obj.respond_to?(:to_h) ? obj.to_h.inspect : obj.inspect
        end
      end
    end
  end
end
