# frozen_string_literal: true

require "mcp"
require "schwab_rb"
require_relative "../loggable"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class QuotesTool < MCP::Tool
      extend Loggable

      description "Get real-time quotes for multiple instrument symbols using Schwab API formatted as JSON"

      input_schema(
        properties: {
          symbols: {
            type: "array",
            items: {
              type: "string",
              pattern: "^[A-Za-z0-9/.$-]{1,12}$"
            },
            description: "Array of instrument symbols (e.g., ['AAPL', 'TSLA', '/ES']) - supports futures and other special symbols",
            minItems: 1,
            maxItems: 500
          },
          fields: {
            type: "array",
            items: {
              type: "string"
            },
            description: "Optional array of specific quote fields to return. If not specified, returns all available data."
          },
          indicative: {
            type: "boolean",
            description: "Optional flag to fetch indicative quotes (true/false). If not specified, returns standard quotes."
          }
        },
        required: ["symbols"]
      )

      annotations(
        title: "Get Financial Instrument Quotes",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(symbols:, server_context:, fields: ["quote"], indicative: false)
        symbols = [symbols] if symbols.is_a?(String)

        log_info("Getting quotes for #{symbols.length} symbols: #{symbols.join(", ")}")

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          log_debug("Making API request for symbols: #{symbols.join(", ")}")
          log_debug("Fields: #{fields || "all"}")
          log_debug("Indicative: #{indicative || "not specified"}")

          normalized_symbols = symbols.map(&:upcase)

          quotes_data = client.get_quotes(
            normalized_symbols,
            fields: fields,
            indicative: indicative,
            return_data_objects: true
          )

          unless quotes_data
            log_warn("No quote data objects returned for symbols: #{symbols.join(", ")}")
            return MCP::Tool::Response.new([{
                                             type: "text",
                                             text: "**No Data**: No quote data returned for symbols: " \
                                                   "#{symbols.join(", ")}"
                                           }])
          end

          # Format quotes output
          formatted_quotes = format_quotes_data(quotes_data, normalized_symbols)
          log_info("Successfully retrieved quotes for #{symbols.length} symbols")

          symbol_list = normalized_symbols.join(", ")
          field_info = fields ? " (fields: #{fields.join(", ")})" : " (all fields)"
          indicative_info = indicative.nil? ? "" : " (indicative: #{indicative})"

          MCP::Tool::Response.new([{
                                    type: "text",
                                    text: "**Quotes for #{symbol_list}:**#{field_info}#{indicative_info}\n\n" \
                                          "#{formatted_quotes}"
                                  }])
        rescue StandardError => e
          log_error("Error retrieving quotes for #{symbols.join(", ")}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join("\n")}")
          MCP::Tool::Response.new([{
                                    type: "text",
                                    text: "**Error** retrieving quotes for #{symbols.join(", ")}: #{e.message}\n\n" \
                                          "#{e.backtrace.first(3).join("\n")}"
                                  }])
        end
      end

      # Format the quotes data for display
      def self.format_quotes_data(quotes_data, symbols)
        return "No quotes available" unless quotes_data

        case quotes_data
        when Hash
          format_hash_quotes(quotes_data, symbols)
        when Array
          quotes_data.map { |quote_obj| format_single_quote(quote_obj) }.join("\n\n")
        else
          format_single_quote(quotes_data)
        end
      end

      # Format hash of quotes (symbol => quote_object)
      def self.format_hash_quotes(quotes_data, symbols)
        formatted_lines = symbols.map do |symbol|
          quote_obj = quotes_data[symbol] || quotes_data[symbol.to_sym]
          quote_obj ? format_single_quote(quote_obj) : "#{symbol}: No data available"
        end
        formatted_lines.join("\n\n")
      end

      # Format a single quote object for display (reused from quote_tool.rb)
      def self.format_single_quote(obj)
        case obj
        when SchwabRb::DataObjects::OptionQuote
          format_option_quote(obj)
        when SchwabRb::DataObjects::EquityQuote
          format_equity_quote(obj)
        when SchwabRb::DataObjects::IndexQuote
          format_index_quote(obj)
        else
          obj.respond_to?(:to_h) ? obj.to_h.inspect : obj.inspect
        end
      end

      # Format option quote
      def self.format_option_quote(obj)
        "Option: #{obj.symbol}\nLast: #{obj.last_price}  Bid: #{obj.bid_price}  Ask: #{obj.ask_price}  " \
        "Mark: #{obj.mark}  Delta: #{obj.delta}  Gamma: #{obj.gamma}  Vol: #{obj.volatility}  " \
        "OI: #{obj.open_interest}  Exp: #{obj.expiration_month}/#{obj.expiration_day}/#{obj.expiration_year}  " \
        "Strike: #{obj.strike_price}"
      end

      # Format equity quote
      def self.format_equity_quote(obj)
        "Equity: #{obj.symbol}\nLast: #{obj.last_price}  Bid: #{obj.bid_price}  Ask: #{obj.ask_price}  " \
        "Mark: #{obj.mark}  Net Chg: #{obj.net_change}  %Chg: #{obj.net_percent_change}  Vol: #{obj.total_volume}"
      end

      # Format index quote
      def self.format_index_quote(obj)
        "Index: #{obj.symbol}\nLast: #{obj.last_price}  Bid: N/A  Ask: N/A  Mark: #{obj.mark}  " \
        "Net Chg: #{obj.net_change}  %Chg: #{obj.net_percent_change}  Vol: #{obj.total_volume}"
      end
    end
  end
end
