require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"

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

      def self.call(symbols:, fields: ["quote"], indicative: false, server_context:)
        symbols = [symbols] if symbols.is_a?(String)

        log_info("Getting quotes for #{symbols.length} symbols: #{symbols.join(', ')}")

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

          log_debug("Making API request for symbols: #{symbols.join(', ')}")
          log_debug("Fields: #{fields || 'all'}")
          log_debug("Indicative: #{indicative || 'not specified'}")

          normalized_symbols = symbols.map(&:upcase)

          response = client.get_quotes(
            normalized_symbols,
            fields: fields,
            indicative: indicative
          )

          if response&.body
            log_info("Successfully retrieved quotes for #{symbols.length} symbols")

            symbol_list = normalized_symbols.join(', ')
            field_info = fields ? " (fields: #{fields.join(', ')})" : " (all fields)"
            indicative_info = indicative.nil? ? "" : " (indicative: #{indicative})"

            MCP::Tool::Response.new([{
              type: "text",
              text: "**Quotes for #{symbol_list}:**#{field_info}#{indicative_info}\n\n```json\n#{response.body}\n```"
            }])
          else
            log_warn("Empty response from Schwab API for symbols: #{symbols.join(', ')}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for symbols: #{symbols.join(', ')}"
            }])
          end

        rescue => e
          log_error("Error retrieving quotes for #{symbols.join(', ')}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving quotes for #{symbols.join(', ')}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end
    end
  end
end
