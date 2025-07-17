require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"

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

          account_numbers_response = client.get_account_numbers

          unless account_numbers_response&.body
            log_error("Failed to retrieve account numbers")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Failed to retrieve account numbers from Schwab API"
            }])
          end

          account_mappings = JSON.parse(account_numbers_response.body, symbolize_names: true)
          log_debug("Account mappings retrieved (#{account_mappings.length} accounts found)")

          account_hash = nil
          account_mappings.each do |mapping|
            if mapping[:accountNumber] == account_id
              account_hash = mapping[:hashValue]
              break
            end
          end

          unless account_hash
            log_error("Account ID not found in available accounts")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Account ID not found in available accounts. #{account_mappings.length} accounts available."
            }])
          end

          log_debug("Found account hash for account ID: #{account_name}")
          log_debug("Verifying order exists before attempting cancellation")

          order_response = client.get_order(order_id, account_hash)

          unless order_response&.body
            log_warn("Order not found or empty response for order ID: #{order_id}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Warning**: Order ID #{order_id} not found or empty response. Order may not exist in the specified account."
            }])
          end

          order_data = JSON.parse(order_response.body)
          order_status = order_data['status']
          cancelable = order_data['cancelable']

          log_debug("Order found - Status: #{order_status}, Cancelable: #{cancelable}")
          if cancelable == false
            log_warn("Order #{order_id} is not cancelable (Status: #{order_status})")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Warning**: Order ID #{order_id} cannot be cancelled.\n\n**Current Status**: #{order_status}\n**Cancelable**: #{cancelable}\n\nOrders that are already filled, cancelled, or expired cannot be cancelled."
            }])
          end

          log_info("Attempting to cancel order ID: #{order_id} (Status: #{order_status})")
          cancel_response = client.cancel_order(order_id, account_hash)

          if cancel_response.respond_to?(:status) && cancel_response.status == 200
            log_info("Successfully cancelled order ID: #{order_id}")
            formatted_response = format_cancellation_success(order_id, account_name, order_data)
          elsif cancel_response.respond_to?(:status) && cancel_response.status == 404
            log_warn("Order not found during cancellation: #{order_id}")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Warning**: Order ID #{order_id} not found during cancellation. It may have already been cancelled or filled."
            }])
          else
            log_info("Order cancellation request submitted for order ID: #{order_id}")
            formatted_response = format_cancellation_success(order_id, account_name, order_data)
          end

          MCP::Tool::Response.new([{
            type: "text",
            text: formatted_response
          }])

        rescue JSON::ParserError => e
          log_error("JSON parsing error: #{e.message}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Failed to parse API response: #{e.message}"
          }])
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

      def self.format_cancellation_success(order_id, account_name, order_data)
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

        formatted = "**✅ Order Cancellation Successful**\n\n"
        formatted += "**Order ID**: #{order_id}\n"
        formatted += "**Account**: #{friendly_name} (#{account_name})\n\n"
        formatted += "**Order Details:**\n"
        formatted += "- Original Status: #{order_data['status']}\n" if order_data['status']
        formatted += "- Order Type: #{order_data['orderType']}\n" if order_data['orderType']
        formatted += "- Session: #{order_data['session']}\n" if order_data['session']
        formatted += "- Duration: #{order_data['duration']}\n" if order_data['duration']
        formatted += "- Quantity: #{order_data['quantity']}\n" if order_data['quantity']
        formatted += "- Price: $#{format_currency(order_data['price'])}\n" if order_data['price']

        if order_data['orderLegCollection'] && order_data['orderLegCollection'].any?
          formatted += "\n**Instruments:**\n"
          order_data['orderLegCollection'].each do |leg|
            if leg['instrument']
              symbol = leg['instrument']['symbol']
              instruction = leg['instruction']
              quantity = leg['quantity']
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
