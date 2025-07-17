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
          log_debug("Fetching order details for order ID: #{order_id}")

          order_response = client.get_order(order_id, account_hash)

          if order_response&.body
            log_info("Successfully retrieved order details for order ID: #{order_id}")
            order_data = JSON.parse(order_response.body)

            formatted_response = format_order_data(order_data, order_id, account_name)

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

        rescue JSON::ParserError => e
          log_error("JSON parsing error: #{e.message}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Failed to parse API response: #{e.message}"
          }])
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

      def self.format_order_data(order_data, order_id, account_name)
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

        formatted = "**Order Details for Order ID #{order_id}:**\n\n"
        formatted += "**Account:** #{friendly_name} (#{account_name})\n\n"

        formatted += "**Order Information:**\n"
        formatted += "- Order ID: #{order_data['orderId']}\n" if order_data['orderId']
        formatted += "- Status: #{order_data['status']}\n" if order_data['status']
        formatted += "- Order Type: #{order_data['orderType']}\n" if order_data['orderType']
        formatted += "- Session: #{order_data['session']}\n" if order_data['session']
        formatted += "- Duration: #{order_data['duration']}\n" if order_data['duration']
        formatted += "- Complex Order Strategy Type: #{order_data['complexOrderStrategyType']}\n" if order_data['complexOrderStrategyType']
        formatted += "- Cancelable: #{order_data['cancelable']}\n" if order_data.key?('cancelable')
        formatted += "- Editable: #{order_data['editable']}\n" if order_data.key?('editable')

        formatted += "\n**Timing:**\n"
        formatted += "- Entered Time: #{order_data['enteredTime']}\n" if order_data['enteredTime']
        formatted += "- Close Time: #{order_data['closeTime']}\n" if order_data['closeTime']

        formatted += "\n**Quantity & Pricing:**\n"
        formatted += "- Quantity: #{order_data['quantity']}\n" if order_data['quantity']
        formatted += "- Filled Quantity: #{order_data['filledQuantity']}\n" if order_data['filledQuantity']
        formatted += "- Remaining Quantity: #{order_data['remainingQuantity']}\n" if order_data['remainingQuantity']
        formatted += "- Requested Destination: #{order_data['requestedDestination']}\n" if order_data['requestedDestination']
        formatted += "- Destination Link Name: #{order_data['destinationLinkName']}\n" if order_data['destinationLinkName']
        formatted += "- Price: $#{format_currency(order_data['price'])}\n" if order_data['price']
        formatted += "- Stop Price: $#{format_currency(order_data['stopPrice'])}\n" if order_data['stopPrice']
        formatted += "- Stop Price Link Basis: #{order_data['stopPriceLinkBasis']}\n" if order_data['stopPriceLinkBasis']
        formatted += "- Stop Price Link Type: #{order_data['stopPriceLinkType']}\n" if order_data['stopPriceLinkType']
        formatted += "- Stop Price Offset: $#{format_currency(order_data['stopPriceOffset'])}\n" if order_data['stopPriceOffset']
        formatted += "- Stop Type: #{order_data['stopType']}\n" if order_data['stopType']

        if order_data['orderLegCollection'] && order_data['orderLegCollection'].any?
          formatted += "\n**Order Legs:**\n"
          order_data['orderLegCollection'].each_with_index do |leg, index|
            formatted += "**Leg #{index + 1}:**\n"
            formatted += "- Instruction: #{leg['instruction']}\n" if leg['instruction']
            formatted += "- Quantity: #{leg['quantity']}\n" if leg['quantity']
            formatted += "- Position Effect: #{leg['positionEffect']}\n" if leg['positionEffect']
            formatted += "- Quantity Type: #{leg['quantityType']}\n" if leg['quantityType']

            if leg['instrument']
              instrument = leg['instrument']
              formatted += "- **Instrument:**\n"
              formatted += "  * Asset Type: #{instrument['assetType']}\n" if instrument['assetType']
              formatted += "  * Symbol: #{instrument['symbol']}\n" if instrument['symbol']
              formatted += "  * Description: #{instrument['description']}\n" if instrument['description']
              formatted += "  * CUSIP: #{instrument['cusip']}\n" if instrument['cusip']
              formatted += "  * Net Change: #{instrument['netChange']}\n" if instrument['netChange']

              if instrument['putCall']
                formatted += "  * Option Type: #{instrument['putCall']}\n"
                formatted += "  * Strike Price: $#{format_currency(instrument['strikePrice'])}\n" if instrument['strikePrice']
                formatted += "  * Expiration Date: #{instrument['expirationDate']}\n" if instrument['expirationDate']
                formatted += "  * Days to Expiration: #{instrument['daysToExpiration']}\n" if instrument['daysToExpiration']
                formatted += "  * Expiration Type: #{instrument['expirationType']}\n" if instrument['expirationType']
                formatted += "  * Exercise Type: #{instrument['exerciseType']}\n" if instrument['exerciseType']
                formatted += "  * Settlement Type: #{instrument['settlementType']}\n" if instrument['settlementType']
                formatted += "  * Deliverables: #{instrument['deliverables']}\n" if instrument['deliverables']
              end
            end
            formatted += "\n" unless index == order_data['orderLegCollection'].length - 1
          end
        end

        if order_data['childOrderStrategies'] && order_data['childOrderStrategies'].any?
          formatted += "\n**Child Order Strategies:**\n"
          formatted += "- Number of Child Orders: #{order_data['childOrderStrategies'].length}\n"
          order_data['childOrderStrategies'].each_with_index do |child, index|
            formatted += "- Child Order #{index + 1}: #{child['orderId']} (Status: #{child['status']})\n" if child['orderId'] && child['status']
          end
        end

        if order_data['orderActivityCollection'] && order_data['orderActivityCollection'].any?
          formatted += "\n**Order Activities:**\n"
          order_data['orderActivityCollection'].each_with_index do |activity, index|
            formatted += "**Activity #{index + 1}:**\n"
            formatted += "- Activity Type: #{activity['activityType']}\n" if activity['activityType']
            formatted += "- Execution Type: #{activity['executionType']}\n" if activity['executionType']
            formatted += "- Quantity: #{activity['quantity']}\n" if activity['quantity']
            formatted += "- Order Remaining Quantity: #{activity['orderRemainingQuantity']}\n" if activity['orderRemainingQuantity']

            if activity['executionLegs'] && activity['executionLegs'].any?
              activity['executionLegs'].each_with_index do |exec_leg, leg_index|
                formatted += "- **Execution Leg #{leg_index + 1}:**\n"
                formatted += "  * Leg ID: #{exec_leg['legId']}\n" if exec_leg['legId']
                formatted += "  * Price: $#{format_currency(exec_leg['price'])}\n" if exec_leg['price']
                formatted += "  * Quantity: #{exec_leg['quantity']}\n" if exec_leg['quantity']
                formatted += "  * Mismarked Quantity: #{exec_leg['mismarkedQuantity']}\n" if exec_leg['mismarkedQuantity']
                formatted += "  * Time: #{exec_leg['time']}\n" if exec_leg['time']
              end
            end
            formatted += "\n" unless index == order_data['orderActivityCollection'].length - 1
          end
        end

        redacted_data = Redactor.redact(order_data)
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
