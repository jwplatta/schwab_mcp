require "mcp"
require "schwab_rb"
require_relative "../loggable"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class ListMoversTool < MCP::Tool
      extend Loggable
      description "Get a list of the top ten movers for a given index using Schwab API"

      input_schema(
        properties: {
          index: {
            type: "string",
            description: "Category of mover",
            enum: ["$DJI", "$COMPX", "$SPX", "NYSE", "NASDAQ", "OTCBB", "INDEX_ALL", "EQUITY_ALL", "OPTION_ALL", "OPTION_PUT", "OPTION_CALL"]
          },
          sort_order: {
            type: "string",
            description: "Order in which to return values (optional)",
            enum: ["VOLUME", "TRADES", "PERCENT_CHANGE_UP", "PERCENT_CHANGE_DOWN"]
          },
          frequency: {
            type: "integer",
            description: "Only return movers that saw this magnitude or greater (optional)",
            enum: [0, 1, 5, 10, 30, 60]
          }
        },
        required: ["index"]
      )

      annotations(
        title: "List Market Movers",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(index:, sort_order: nil, frequency: nil, server_context:)
        log_info("Getting movers for index: #{index}, sort_order: #{sort_order}, frequency: #{frequency}")

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          log_debug("Making API request for movers - index: #{index}, sort_order: #{sort_order}, frequency: #{frequency}")

          market_movers = client.get_movers(
            index,
            sort_order: sort_order,
            frequency: frequency
          )

          if market_movers && market_movers.count > 0
            log_info("Successfully retrieved #{market_movers.count} movers for index #{index}")

            formatted_output = format_movers_response(market_movers, index, sort_order, frequency)

            MCP::Tool::Response.new([{
              type: "text",
              text: formatted_output
            }])
          else
            log_warn("No movers data returned from Schwab API for index #{index}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: No movers found for index #{index}"
            }])
          end

        rescue => e
          log_error("Error retrieving movers: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving movers: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private

      def self.format_movers_response(market_movers, index, sort_order, frequency)
        header = "**Market Movers for #{index}**"
        header += " (sorted by #{sort_order})" if sort_order
        header += " (frequency filter: #{frequency})" if frequency
        header += "\n\n"

        if market_movers.count > 0
          movers_list = market_movers.movers.map.with_index(1) do |mover, i|
            symbol = mover.symbol || 'N/A'
            description = mover.description || 'N/A'
            change = mover.net_change || 0
            percent_change = mover.net_change_percentage || 0
            volume = mover.volume || 0
            last_price = mover.last_price || 0

            "#{i}. **#{symbol}** - #{description}\n" \
            "   Last: $#{sprintf('%.2f', last_price)}\n" \
            "   Change: #{change >= 0 ? '+' : ''}#{sprintf('%.2f', change)} (#{percent_change >= 0 ? '+' : ''}#{sprintf('%.2f', percent_change)}%)\n" \
            "   Volume: #{volume.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
          end.join("\n\n")

          "#{header}#{movers_list}"
        else
          "#{header}No movers data available."
        end
      end
    end
  end
end
