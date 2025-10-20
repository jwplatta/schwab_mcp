require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class CancelOrderTool < MCP::Tool
      extend Loggable
      description "Cancel a specific order by order ID using account name mapping"

      input_schema(
        properties: {
          order_id: {
            type: "string",
            description: "The order ID to cancel",
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
        title: "Cancel Order",
        read_only_hint: false,
        destructive_hint: true,
        idempotent_hint: false
      )

      def self.call(order_id:, account_name:, server_context:)
        log_info("Attempting to cancel order ID: #{order_id} in account: #{account_name}")

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
          log_debug("Verifying order exists before attempting cancellation")

          order = client.get_order(order_id, account_name: account_name) # returns SchwabRb::DataObjects::Order
          unless order
            log_warn("Order not found or empty response for order ID: #{order_id}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Warning**: Order ID #{order_id} not found or empty response. Order may not exist in the specified account."
            }])
          end

          order_status = order.status
          cancelable = order.respond_to?(:cancelable) ? order.cancelable : true # fallback if attribute not present

          log_debug("Order found - Status: #{order_status}, Cancelable: #{cancelable}")
          if cancelable == false
            log_warn("Order #{order_id} is not cancelable (Status: #{order_status})")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Warning**: Order ID #{order_id} cannot be cancelled.\n\n**Current Status**: #{order_status}\n**Cancelable**: #{cancelable}\n\nOrders that are already filled, cancelled, or expired cannot be cancelled."
            }])
          end

          log_info("Attempting to cancel order ID: #{order_id} (Status: #{order_status})")
          cancel_response = client.cancel_order(order_id, account_name: account_name)

          if cancel_response.respond_to?(:status) && cancel_response.status == 200
            log_info("Successfully cancelled order ID: #{order_id}")
            formatted_response = format_cancellation_success(order_id, account_name, order)
          elsif cancel_response.respond_to?(:status) && cancel_response.status == 404
            log_warn("Order not found during cancellation: #{order_id}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Warning**: Order ID #{order_id} not found during cancellation. It may have already been cancelled or filled."
            }])
          else
            log_info("Order cancellation request submitted for order ID: #{order_id}")
            formatted_response = format_cancellation_success(order_id, account_name, order)
          end

          MCP::Tool::Response.new([{
            type: "text",
            text: formatted_response
          }])

        # No JSON::ParserError rescue needed with data objects
        rescue => e
          log_error("Error cancelling order ID #{order_id}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")

          error_message = if e.message.include?("401") || e.message.include?("403")
            "**Error**: Authorization failed. Check your API credentials and permissions for order cancellation."
          elsif e.message.include?("400")
            "**Error**: Bad request. Order ID #{order_id} may be invalid or cannot be cancelled at this time."
          elsif e.message.include?("404")
            "**Error**: Order ID #{order_id} not found in the specified account."
          else
            "**Error** cancelling order ID #{order_id}: #{e.message}"
          end

          MCP::Tool::Response.new([{
            type: "text",
            text: "#{error_message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private

      def self.format_cancellation_success(order_id, account_name, order)
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

        formatted = "**✅ Order Cancellation Successful**\n\n"
        formatted += "**Order ID**: #{order_id}\n"
        formatted += "**Account**: #{friendly_name} (#{account_name})\n\n"
        formatted += "**Order Details:**\n"
        formatted += "- Original Status: #{order.status}\n" if order.status
        formatted += "- Order Type: #{order.order_type}\n" if order.order_type
        formatted += "- Duration: #{order.duration}\n" if order.duration
        formatted += "- Quantity: #{order.quantity}\n" if order.quantity
        formatted += "- Price: $#{format_currency(order.price)}\n" if order.price

        if order.order_leg_collection && order.order_leg_collection.any?
          formatted += "\n**Instruments:**\n"
          order.order_leg_collection.each do |leg|
            if leg.instrument
              symbol = leg.instrument.symbol
              instruction = leg.instruction
              quantity = leg.quantity
              formatted += "- #{symbol}: #{instruction} #{quantity}\n"
            end
          end
        end

        formatted += "\n**Note**: The order cancellation has been submitted. Please verify the cancellation by checking your order status or using the `get_order_tool` or `list_account_orders_tool`."

        formatted
      end

      def self.format_currency(amount)
        return "0.00" if amount.nil?
        "%.2f" % amount.to_f
      end
    end
  end
end
