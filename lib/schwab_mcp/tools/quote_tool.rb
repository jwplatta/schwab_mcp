require "mcp"
require "schwab_rb"
require "json"

module SchwabMCP
  module Tools
    class QuoteTool < MCP::Tool
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
        begin
          client = SchwabRb::Auth.init_client_easy(
            ENV['SCHWAB_API_KEY'],
            ENV['SCHWAB_APP_SECRET'],
            ENV['APP_CALLBACK_URL'],
            ENV['TOKEN_PATH']
          )

          unless client
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Failed to initialize Schwab client. Check your credentials."
            }])
          end

          response = client.get_quote(symbol.upcase)

          if response&.body
            MCP::Tool::Response.new([{
              type: "text",
              text: "**Quote for #{symbol.upcase}:**\n\n```json\n#{response.body}\n```"
            }])
          else
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for symbol: #{symbol}"
            }])
          end

        rescue => e
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving quote for #{symbol}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end
    end
  end
end
