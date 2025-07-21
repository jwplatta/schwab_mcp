
# frozen_string_literal: true

require "mcp"
require "schwab_rb"
require_relative "../loggable"

module SchwabMCP
  module Tools
    class QuoteTool < MCP::Tool
      extend Loggable
      description "Get a real-time quote for a single instrument symbol using Schwab API"

      input_schema(
        properties: {
          symbol: {
            type: "string",
            description: "Instrument symbol (e.g., 'AAPL', 'TSLA')",
            pattern: "^[A-Za-z]{1,5}$"
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

          log_debug("Making API request for symbol: #{symbol}")
          quote_obj = client.get_quote(symbol.upcase, return_data_objects: true)

          unless quote_obj
            log_warn("No quote data object returned for symbol: #{symbol}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: No quote data returned for symbol: #{symbol}"
            }])
          end

          # Format output based on quote type
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

      # Format the quote object for display
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
