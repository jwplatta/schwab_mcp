require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"
require_relative "../redactor"
require_relative "../schwab_client_factory"

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
            description: "Optional account fields to retrieve (positions)",
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
          log_debug("Fetching account information with fields: #{fields}")

          account = client.get_account(account_name: account_name, fields: fields)

          if account
            log_info("Successfully retrieved account information for #{account_name}")

            formatted_response = format_account_data(account, account_name)

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

      def self.format_account_data(account, account_name)
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

        formatted = "**Account Information for #{friendly_name} (#{account_name}):**\n\n"

        formatted += "**Account Number:** #{Redactor::REDACTED_ACCOUNT_PLACEHOLDER}\n"
        formatted += "**Account Type:** #{account.type}\n"

        if current_balances = account.current_balances
          formatted += "\n**Current Balances:**\n"
          formatted += "- Cash Balance: $#{format_currency(current_balances.cash_balance)}\n"
          formatted += "- Buying Power: $#{format_currency(current_balances.buying_power)}\n"
          formatted += "- Liquidation Value: $#{format_currency(current_balances.liquidation_value)}\n"
          formatted += "- Long Market Value: $#{format_currency(current_balances.long_market_value)}\n"
          formatted += "- Short Market Value: $#{format_currency(current_balances.short_market_value)}\n"
        end

        # Positions summary
        if positions = account.positions
          formatted += "\n**Positions Summary:**\n"
          formatted += "- Total Positions: #{positions.length}\n"

          if positions.length > 0
            formatted += "\n**Position Details:**\n"
            positions.each do |position|
              symbol = position.instrument.symbol
              qty = position.long_quantity - position.short_quantity
              market_value = position.market_value
              formatted += "- #{symbol}: #{qty} shares, Market Value: $#{format_currency(market_value)}\n"
            end
          end
        end

        # Note: Orders would need to be fetched separately as they're not part of the Account data object

        # Convert account back to hash for JSON display (redacted)
        account_hash = {
          securitiesAccount: {
            type: account.type,
            accountNumber: account.account_number,
            positions: account.positions.map(&:to_h),
            currentBalances: {
              cashBalance: account.current_balances&.cash_balance,
              buyingPower: account.current_balances&.buying_power,
              liquidationValue: account.current_balances&.liquidation_value,
              longMarketValue: account.current_balances&.long_market_value,
              shortMarketValue: account.current_balances&.short_market_value
            }
          }
        }

        redacted_data = Redactor.redact(account_hash)
        formatted += "\n```json\n#{JSON.pretty_generate(redacted_data)}\n```"
        formatted
      end

      def self.format_currency(amount)
        return "0.00" if amount.nil?
        "%.2f" % amount.to_f
      end
    end
  end
end

