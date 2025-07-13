require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"

module SchwabMCP
  module Tools
    class SchwabAccountDetailsTool < MCP::Tool
      extend Loggable
      description "Get account information for a specific account using account name mapping"

      input_schema(
        properties: {
          account_name: {
            type: "string",
            description: "Account name mapped to environment variable ending with '_ACCOUNT' (e.g., 'TRADING_BROKERAGE_ACCOUNT')",
            pattern: "^[A-Z_]+_ACCOUNT$"
          },
          fields: {
            type: "array",
            description: "Optional account fields to retrieve (balances, positions, orders)",
            items: {
              type: "string"
            }
          }
        },
        required: ["account_name"]
      )

      annotations(
        title: "Get Schwab Account Information",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(account_name:, fields: nil, server_context:)
        log_info("Getting account information for account name: #{account_name}")

        unless account_name.end_with?('_ACCOUNT')
          log_error("Invalid account name format: #{account_name}")
          return MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Account name must end with '_ACCOUNT'. Example: 'TRADING_BROKERAGE_ACCOUNT'"
          }])
        end

        begin
          client = SchwabRb::Auth.init_client_easy(
            ENV['SCHWAB_API_KEY'],
            ENV['SCHWAB_APP_SECRET'],
            ENV['APP_CALLBACK_URL'],
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
            available_accounts = account_mappings.map { |m| "[REDACTED]" }.join(", ")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Account ID not found in available accounts. #{account_mappings.length} accounts available."
            }])
          end

          log_debug("Found account hash for account ID: #{account_name}")

          log_debug("Fetching account information with fields: #{fields}")
          account_response = client.get_account(account_hash, fields: fields)

          if account_response&.body
            log_info("Successfully retrieved account information for #{account_name}")
            account_data = JSON.parse(account_response.body)

            formatted_response = format_account_data(account_data, account_name, account_id)

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

        rescue JSON::ParserError => e
          log_error("JSON parsing error: #{e.message}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Failed to parse API response: #{e.message}"
          }])
        rescue => e
          log_error("Error retrieving account information for #{account_name}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving account information for #{account_name}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private

      def self.format_account_data(account_data, account_name, account_id)
        account = account_data["securitiesAccount"]
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

        formatted = "**Account Information for #{friendly_name} (#{account_name}):**\n\n"

        if account
          formatted += "**Account Number:** [REDACTED]\n"
          formatted += "**Account Type:** #{account['type']}\n"

          if current_balances = account['currentBalances']
            formatted += "\n**Current Balances:**\n"
            formatted += "- Cash Balance: $#{format_currency(current_balances['cashBalance'])}\n"
            formatted += "- Buying Power: $#{format_currency(current_balances['buyingPower'])}\n"
            formatted += "- Total Cash: $#{format_currency(current_balances['totalCash'])}\n"
            formatted += "- Liquidation Value: $#{format_currency(current_balances['liquidationValue'])}\n"
            formatted += "- Long Market Value: $#{format_currency(current_balances['longMarketValue'])}\n"
            formatted += "- Short Market Value: $#{format_currency(current_balances['shortMarketValue'])}\n"
          end

          # Positions summary
          if positions = account['positions']
            formatted += "\n**Positions Summary:**\n"
            formatted += "- Total Positions: #{positions.length}\n"

            if positions.length > 0
              formatted += "\n**Position Details:**\n"
              positions.each do |position|
                symbol = position.dig('instrument', 'symbol')
                qty = position['longQuantity'].to_f - position['shortQuantity'].to_f
                market_value = position['marketValue']
                formatted += "- #{symbol}: #{qty} shares, Market Value: $#{format_currency(market_value)}\n"
              end
            end
          end

          if orders = account['orderStrategies']
            formatted += "\n**Active Orders:**\n"
            formatted += "- Total Orders: #{orders.length}\n"

            orders.each do |order|
              status = order['status']
              symbol = order.dig('orderLegCollection', 0, 'instrument', 'symbol')
              formatted += "- #{symbol}: #{status}\n"
            end
          end        end

        redacted_data = redact_account_data(account_data)
        formatted += "\n```json\n#{JSON.pretty_generate(redacted_data)}\n```"
        formatted
      end

      def self.redact_account_data(data)
        redacted = JSON.parse(JSON.generate(data))

        if redacted.dig("securitiesAccount", "accountNumber")
          redacted["securitiesAccount"]["accountNumber"] = "[REDACTED]"
        end

        redacted_json = JSON.generate(redacted)
        redacted_json.gsub!(/\b\d{8,9}\b/, '[REDACTED]')

        JSON.parse(redacted_json)
      end

      def self.format_currency(amount)
        return "0.00" if amount.nil?
        "%.2f" % amount.to_f
      end
    end
  end
end

