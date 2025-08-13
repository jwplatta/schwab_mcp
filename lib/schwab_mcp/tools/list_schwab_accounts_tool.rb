require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"
require_relative "../redactor"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class ListSchwabAccountsTool < MCP::Tool
      extend Loggable
      description "List all configured Schwab accounts with their friendly names and basic info"

      input_schema(
        properties: {},
        required: []
      )

      annotations(
        title: "List Schwab Accounts",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(server_context:)
        log_info("Listing all configured Schwab accounts")

        begin
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          log_debug("Fetching account numbers from Schwab API")
          account_numbers = client.get_account_numbers

          unless account_numbers
            log_error("Failed to retrieve account numbers")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Failed to retrieve account numbers from Schwab API"
            }])
          end

          log_debug("Retrieved #{account_numbers.size} accounts from Schwab API")

          configured_accounts = find_configured_accounts(account_numbers)

          if configured_accounts.empty?
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**No Configured Accounts Found**\n\nNo environment variables found ending with '_ACCOUNT'.\n\nTo configure accounts, set environment variables like:\n- TRADING_BROKERAGE_ACCOUNT=123456789\n- RETIREMENT_IRA_ACCOUNT=987654321\n- INCOME_BROKERAGE_ACCOUNT=555666777"
            }])
          end

          formatted_response = format_accounts_list(configured_accounts, account_numbers)

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
          log_error("Error listing accounts: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** listing accounts: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private

      def self.find_configured_accounts(account_numbers)
        # Get all account IDs from Schwab API data object
        schwab_account_ids = account_numbers.account_numbers

        # Find environment variables ending with "_ACCOUNT"
        configured = []
        ENV.each do |key, value|
          next unless key.end_with?('_ACCOUNT')

          if schwab_account_ids.include?(value)
            account = account_numbers.find_by_account_number(value)
            configured << {
              name: key,
              friendly_name: friendly_name_from_env_key(key),
              account_id: value,
              account: account
            }
          end
        end

        configured.sort_by { |account| account[:name] }
      end

      def self.friendly_name_from_env_key(env_key)
        # Convert "TRADING_BROKERAGE_ACCOUNT" to "Trading Brokerage"
        env_key.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')
      end

      def self.format_accounts_list(configured_accounts, account_numbers)
        response = "**Configured Schwab Accounts:**\n\n"

        configured_accounts.each_with_index do |account, index|
          response += "#{index + 1}. **#{account[:friendly_name]}** (`#{account[:name]}`)\n"
          response += "   - Status: ✅ Configured\n\n"
        end

        # Show unconfigured accounts (if any)
        unconfigured_accounts = account_numbers.accounts.reject do |account_obj|
          configured_accounts.any? { |config| config[:account_id] == account_obj.account_number }
        end

        if unconfigured_accounts.any?
          response += "**Unconfigured Accounts Available:**\n\n"
          unconfigured_accounts.each_with_index do |account_obj, index|
            response += "   - To configure: Set `YOUR_NAME_ACCOUNT=#{Redactor::REDACTED_ACCOUNT_PLACEHOLDER}` in your .env file\n\n"
          end
        end

        response += "**Usage:**\n"
        response += "To get account information, use the `schwab_account` tool with one of these account names:\n"
        configured_accounts.each do |account|
          response += "- `#{account[:name]}`\n"
        end

        if configured_accounts.any?
          response += "\n**Example:**\n"
          first_account = configured_accounts.first
          response += "```\n"
          response += "Tool: schwab_account\n"
          response += "Parameters: {\n"
          response += "  \"account_name\": \"#{first_account[:name]}\"\n"
          response += "}\n"
          response += "```"
        end

        response
      end
    end
  end
end
