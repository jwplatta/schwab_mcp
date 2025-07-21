require "mcp"
require "schwab_rb"
require "json"
require "date"
require_relative "../loggable"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class GetMarketHoursTool < MCP::Tool
      extend Loggable
      description "Get market hours for specified markets using Schwab API"

      input_schema(
        properties: {
          markets: {
            type: "array",
            description: "Markets for which to return trading hours",
            items: {
              type: "string",
              enum: ["equity", "option", "bond", "future", "forex"]
            },
            minItems: 1
          },
          date: {
            type: "string",
            description: "Date for market hours in YYYY-MM-DD format (optional, defaults to today). Accepts values up to one year from today.",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$"
          }
        },
        required: ["markets"]
      )

      annotations(
        title: "Get Market Hours",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(markets:, date: nil, server_context:)
        log_info("Getting market hours for markets: #{markets.join(', ')}")
        log_debug("Date parameter: #{date || 'today'}")

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          parsed_date = nil
          if date
            begin
              parsed_date = Date.parse(date)
              log_debug("Parsed date: #{parsed_date}")
            rescue ArgumentError => e
              log_error("Invalid date format: #{date}")
              return MCP::Tool::Response.new([{
                type: "text",
                text: "**Error**: Invalid date format '#{date}'. Please use YYYY-MM-DD format."
              }])
            end
          end

          log_debug("Making API request for markets: #{markets.join(', ')}")
          response = client.get_market_hours(markets, date: parsed_date)

          if response&.body
            log_info("Successfully retrieved market hours for #{markets.join(', ')}")
            date_info = date ? " for #{date}" : " for today"
            MCP::Tool::Response.new([{
              type: "text",
              text: "**Market Hours#{date_info}:**\n\n```json\n#{response.body}\n```"
            }])
          else
            log_warn("Empty response from Schwab API for markets: #{markets.join(', ')}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for markets: #{markets.join(', ')}"
            }])
          end

        rescue => e
          log_error("Error retrieving market hours for #{markets.join(', ')}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving market hours for #{markets.join(', ')}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end
    end
  end
end
