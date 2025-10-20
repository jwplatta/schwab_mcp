require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"
require_relative "../redactor"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class GetOrderTool < MCP::Tool
      extend Loggable
      description "Get details for a specific order by order ID using account name mapping"

      input_schema(
        properties: {
          order_id: {
            type: "string",
            description: "The order ID to retrieve details for",
            pattern: "^\\d+$"
          },
          account_name: {
            type: "string",
            description: "Account name mapped to environment variable ending with '_ACCOUNT' (e.g., 'TRADING_BROKERAGE_ACCOUNT')",
            pattern: "^[A-Z_]+_ACCOUNT$"
          }
        },
        required: ["order_id", "account_name"]
      )

      annotations(
        title: "Get Order Details",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(order_id:, account_name:, server_context:)
        log_info("Getting order details for order ID: #{order_id} in account: #{account_name}")

        unless account_name.end_with?('_ACCOUNT')
          log_error("Invalid account name format: #{account_name}")
          return MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Account name must end with '_ACCOUNT'. Example: 'TRADING_BROKERAGE_ACCOUNT'"
          }])
        end

        unless order_id.match?(/^\d+$/)
          log_error("Invalid order ID format: #{order_id}")
          return MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Order ID must be numeric. Example: '123456789'"
          }])
        end

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          available_accounts = client.available_account_names
          unless available_accounts.include?(account_name)
            log_error("Account name '#{account_name}' not found in configured accounts")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Account name '#{account_name}' not found in configured accounts.\n\nAvailable accounts: #{available_accounts.join(', ')}\n\nTo configure: Add the account to your schwab_rb configuration file."
            }])
          end

          log_debug("Using account name: #{account_name}")
          log_debug("Fetching order details for order ID: #{order_id}")

          order = client.get_order(order_id, account_name: account_name) # returns SchwabRb::DataObjects::Order
          if order
            log_info("Successfully retrieved order details for order ID: #{order_id}")
            formatted_response = format_order_object(order, order_id, account_name)
            MCP::Tool::Response.new([{
              type: "text",
              text: formatted_response
            }])
          else
            log_warn("Empty response from Schwab API for order ID: #{order_id}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for order ID: #{order_id}. Order may not exist or may be in a different account."
            }])
          end
        rescue => e
          log_error("Error retrieving order details for order ID #{order_id}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving order details for order ID #{order_id}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private


      def self.format_order_object(order, order_id, account_name)
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')
        formatted = "**Order Details for Order ID #{order_id}:**\n\n"
        formatted += "**Account:** #{friendly_name} (#{account_name})\n\n"

        formatted += "**Order Information:**\n"
        formatted += "- Order ID: #{order.order_id}\n" if order.order_id
        formatted += "- Status: #{order.status}\n" if order.status
        formatted += "- Order Type: #{order.order_type}\n" if order.order_type
        formatted += "- Duration: #{order.duration}\n" if order.duration
        formatted += "- Complex Order Strategy Type: #{order.complex_order_strategy_type}\n" if order.complex_order_strategy_type

        formatted += "\n**Timing:**\n"
        formatted += "- Entered Time: #{order.entered_time}\n" if order.entered_time
        formatted += "- Close Time: #{order.close_time}\n" if order.close_time

        formatted += "\n**Quantity & Pricing:**\n"
        formatted += "- Quantity: #{order.quantity}\n" if order.quantity
        formatted += "- Filled Quantity: #{order.filled_quantity}\n" if order.filled_quantity
        formatted += "- Remaining Quantity: #{order.remaining_quantity}\n" if order.remaining_quantity
        formatted += "- Price: $#{format_currency(order.price)}\n" if order.price

        if order.order_leg_collection && order.order_leg_collection.any?
          formatted += "\n**Order Legs:**\n"
          order.order_leg_collection.each_with_index do |leg, index|
            formatted += "**Leg #{index + 1}:**\n"
            formatted += "- Instruction: #{leg.instruction}\n" if leg.instruction
            formatted += "- Quantity: #{leg.quantity}\n" if leg.quantity
            formatted += "- Position Effect: #{leg.position_effect}\n" if leg.position_effect

            if leg.instrument
              instrument = leg.instrument
              formatted += "- **Instrument:**\n"
              formatted += "  * Asset Type: #{instrument.asset_type}\n" if instrument.asset_type
              formatted += "  * Symbol: #{instrument.symbol}\n" if instrument.symbol
              formatted += "  * Description: #{instrument.description}\n" if instrument.description
            end
            formatted += "\n" unless index == order.order_leg_collection.length - 1
          end
        end

        if order.order_activity_collection && order.order_activity_collection.any?
          formatted += "\n**Order Activities:**\n"
          order.order_activity_collection.each_with_index do |activity, index|
            formatted += "**Activity #{index + 1}:**\n"
            formatted += "- Activity Type: #{activity.activity_type}\n" if activity.activity_type
            formatted += "- Execution Type: #{activity.execution_type}\n" if activity.execution_type
            formatted += "- Quantity: #{activity.quantity}\n" if activity.quantity
            formatted += "- Order Remaining Quantity: #{activity.order_remaining_quantity}\n" if activity.order_remaining_quantity

            if activity.execution_legs && activity.execution_legs.any?
              activity.execution_legs.each_with_index do |exec_leg, leg_index|
                formatted += "- **Execution Leg #{leg_index + 1}:**\n"
                formatted += "  * Leg ID: #{exec_leg.leg_id}\n" if exec_leg.leg_id
                formatted += "  * Price: $#{format_currency(exec_leg.price)}\n" if exec_leg.price
                formatted += "  * Quantity: #{exec_leg.quantity}\n" if exec_leg.quantity
                formatted += "  * Mismarked Quantity: #{exec_leg.mismarked_quantity}\n" if exec_leg.mismarked_quantity
                formatted += "  * Time: #{exec_leg.time}\n" if exec_leg.time
              end
            end
            formatted += "\n" unless index == order.order_activity_collection.length - 1
          end
        end

        redacted_data = Redactor.redact(order.to_h)
        formatted += "\n**Full Response (Redacted):**\n"
        formatted += "```json\n#{JSON.pretty_generate(redacted_data)}\n```"
        formatted
      end

      def self.format_currency(amount)
        return "0.00" if amount.nil?
        "%.2f" % amount.to_f
      end
    end
  end
end
