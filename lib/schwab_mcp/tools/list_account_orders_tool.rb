require "mcp"
require "schwab_rb"
require "json"
require "date"
require_relative "../loggable"
require_relative "../redactor"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class ListAccountOrdersTool < MCP::Tool
      extend Loggable
      description "List orders for a specific account using account name mapping"

      input_schema(
        properties: {
          account_name: {
            type: "string",
            description: "Account name mapped to environment variable ending with '_ACCOUNT' (e.g., 'TRADING_BROKERAGE_ACCOUNT')",
            pattern: "^[A-Z_]+_ACCOUNT$"
          },
          max_results: {
            type: "integer",
            description: "Maximum number of orders to retrieve (optional)",
            minimum: 1
          },
          from_date: {
            type: "string",
            description: "Start date for orders in YYYY-MM-DD format",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$"
          },
          to_date: {
            type: "string",
            description: "End date for orders in YYYY-MM-DD format",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$"
          },
          status: {
            type: "string",
            description: "Filter orders by status (AWAITING_PARENT_ORDER, AWAITING_CONDITION, AWAITING_STOP_CONDITION, AWAITING_MANUAL_REVIEW, ACCEPTED, AWAITING_UR_OUT, PENDING_ACTIVATION, QUEUED, WORKING, REJECTED, PENDING_CANCEL, CANCELED, PENDING_REPLACE, REPLACED, FILLED, EXPIRED, NEW, AWAITING_RELEASE_TIME, PENDING_ACKNOWLEDGEMENT, PENDING_RECALL, UNKNOWN)",
            enum: [
              "AWAITING_PARENT_ORDER",
              "AWAITING_CONDITION",
              "AWAITING_STOP_CONDITION",
              "AWAITING_MANUAL_REVIEW",
              "ACCEPTED",
              "AWAITING_UR_OUT",
              "PENDING_ACTIVATION",
              "QUEUED",
              "WORKING",
              "REJECTED",
              "PENDING_CANCEL",
              "CANCELED",
              "PENDING_REPLACE",
              "REPLACED",
              "FILLED",
              "EXPIRED",
              "NEW",
              "AWAITING_RELEASE_TIME",
              "PENDING_ACKNOWLEDGEMENT",
              "PENDING_RECALL",
              "UNKNOWN"
            ]
          }
        },
        required: ["account_name", "from_date", "to_date"]
      )

      annotations(
        title: "List Account Orders",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(account_name:, max_results: nil, from_date: nil, to_date: nil, status: nil, server_context:)
        log_info("Listing orders for account name: #{account_name}")

        unless account_name.end_with?('_ACCOUNT')
          log_error("Invalid account name format: #{account_name}")
          return MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Account name must end with '_ACCOUNT'. Example: 'TRADING_BROKERAGE_ACCOUNT'"
          }])
        end

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

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

          account_numbers = client.get_account_numbers

          unless account_numbers
            log_error("Failed to retrieve account numbers")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Failed to retrieve account numbers from Schwab API"
            }])
          end

          log_debug("Account numbers retrieved (#{account_numbers.size} accounts found)")

          account_hash = account_numbers.find_hash_value(account_id)

          unless account_hash
            log_error("Account ID not found in available accounts")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Account ID not found in available accounts. #{account_numbers.size} accounts available."
            }])
          end

          log_debug("Found account hash for account ID: #{account_name}")

          from_datetime = nil
          to_datetime = nil

          if from_date
            begin
              from_datetime = DateTime.parse("#{from_date}T00:00:00Z")
            rescue Date::Error => e
              log_error("Invalid from_date format: #{from_date}")
              return MCP::Tool::Response.new([{
                type: "text",
                text: "**Error**: Invalid from_date format. Use YYYY-MM-DD format."
              }])
            end
          end

          if to_date
            begin
              to_datetime = DateTime.parse("#{to_date}T23:59:59Z")
            rescue Date::Error => e
              log_error("Invalid to_date format: #{to_date}")
              return MCP::Tool::Response.new([{
                type: "text",
                text: "**Error**: Invalid to_date format. Use YYYY-MM-DD format."
              }])
            end
          end

          log_debug("Fetching orders with params - max_results: #{max_results}, from_datetime: #{from_datetime}, to_datetime: #{to_datetime}, status: #{status}")

          orders = client.get_account_orders(
            account_hash,
            max_results: max_results,
            from_entered_datetime: from_datetime,
            to_entered_datetime: to_datetime,
            status: status
          )

          if orders
            log_info("Successfully retrieved orders for #{account_name}")

            formatted_response = format_orders_data(orders, account_name, {
              max_results: max_results,
              from_date: from_date,
              to_date: to_date,
              status: status
            })

            MCP::Tool::Response.new([{
              type: "text",
              text: formatted_response
            }])
          else
            log_warn("Empty response from Schwab API for account: #{account_name}")
            MCP::Tool::Response.new([{
              type: "text",
              text: "**No Data**: Empty response from Schwab API for account: #{account_name}"
            }])
          end

        rescue => e
          log_error("Error retrieving orders for #{account_name}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving orders for #{account_name}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private

      def self.format_orders_data(orders, account_name, filters)
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

        formatted = "**Orders for #{friendly_name} (#{account_name}):**\n\n"

        if filters.any? { |k, v| v }
          formatted += "**Filters Applied:**\n"
          formatted += "- Max Results: #{filters[:max_results]}\n" if filters[:max_results]
          formatted += "- From Date: #{filters[:from_date]}\n" if filters[:from_date]
          formatted += "- To Date: #{filters[:to_date]}\n" if filters[:to_date]
          formatted += "- Status: #{filters[:status]}\n" if filters[:status]
          formatted += "\n"
        end

        orders_array = orders.is_a?(Array) ? orders : [orders]

        formatted += "**Orders Summary:**\n"
        formatted += "- Total Orders: #{orders_array.length}\n\n"

        if orders_array.length > 0
          formatted += "**Order Details:**\n"
          orders_array.each_with_index do |order, index|
            formatted += format_single_order(order, index + 1)
            formatted += "\n" unless index == orders_array.length - 1
          end
        else
          formatted += "No orders found matching the specified criteria.\n"
        end

        # Convert data objects to hash for redaction and display
        orders_hash = orders_array.map(&:to_h)
        redacted_data = Redactor.redact(orders_hash)
        formatted += "\n**Full Response (Redacted):**\n"
        formatted += "```json\n#{JSON.pretty_generate(redacted_data)}\n```"
        formatted
      end

      def self.format_single_order(order, order_num)
        formatted = "**Order #{order_num}:**\n"
        formatted += "- Order ID: #{order.order_id}\n" if order.order_id
        formatted += "- Status: #{order.status}\n" if order.status
        formatted += "- Order Type: #{order.order_type}\n" if order.order_type
        formatted += "- Duration: #{order.duration}\n" if order.duration
        formatted += "- Entered Time: #{order.entered_time}\n" if order.entered_time
        formatted += "- Close Time: #{order.close_time}\n" if order.close_time
        formatted += "- Quantity: #{order.quantity}\n" if order.quantity
        formatted += "- Filled Quantity: #{order.filled_quantity}\n" if order.filled_quantity
        formatted += "- Price: $#{format_currency(order.price)}\n" if order.price

        if order.order_leg_collection && order.order_leg_collection.any?
          formatted += "- Instruments:\n"
          order.order_leg_collection.each do |leg|
            if leg.instrument
              symbol = leg.instrument.symbol
              instruction = leg.instruction
              formatted += "  * #{symbol} - #{instruction}\n"
            end
          end
        end

        formatted
      end

      def self.format_currency(amount)
        return "0.00" if amount.nil?
        "%.2f" % amount.to_f
      end
    end
  end
end
