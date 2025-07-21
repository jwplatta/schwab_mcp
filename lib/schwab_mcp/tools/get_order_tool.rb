require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"
require_relative "../redactor"

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

          account_id = ENV[account_name]
          unless account_id
            available_accounts = ENV.keys.select { |key| key.end_with?('_ACCOUNT') }
            log_error("Account name '#{account_name}' not found in environment variables")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Account name '#{account_name}' not found in environment variables.\n\nAvailable accounts: #{available_accounts.join(', ')}\n\nTo configure: Set ENV['#{account_name}'] to your account ID."
            }])
          end

          log_debug("Found account ID: [REDACTED] for account name: #{account_name}")
          log_debug("Fetching account numbers mapping")


          account_numbers = client.get_account_numbers # returns SchwabRb::DataObjects::AccountNumbers
          unless account_numbers && account_numbers.respond_to?(:accounts)
            log_error("Failed to retrieve account numbers")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Failed to retrieve account numbers from Schwab API"
            }])
          end

          account_hash = nil
          account_numbers.accounts.each do |acct|
            if acct.account_number.to_s == account_id.to_s
              account_hash = acct.hash_value
              break
            end
          end

          unless account_hash
            log_error("Account ID not found in available accounts")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Account ID not found in available accounts. #{account_numbers.accounts.length} accounts available."
            }])
          end

          log_debug("Found account hash for account ID: #{account_name}")
          log_debug("Fetching order details for order ID: #{order_id}")

          order = client.get_order(order_id, account_hash) # returns SchwabRb::DataObjects::Order
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
