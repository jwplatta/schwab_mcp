require "mcp"
require "schwab_rb"
require "json"
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
          response = client.get_quote(symbol.upcase)

          if response&.body
            log_info("Successfully retrieved quote for #{symbol}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**Quote for #{symbol.upcase}:**\n\n```json\n#{response.body}\n```"
            }])
          else
            log_warn("Empty response from Schwab API for symbol: #{symbol}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for symbol: #{symbol}"
            }])
          end

        rescue => e
          log_error("Error retrieving quote for #{symbol}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving quote for #{symbol}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end
    end
  end
end
