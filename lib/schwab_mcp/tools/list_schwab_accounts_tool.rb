require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"

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

          log_debug("Fetching account numbers from Schwab API")
          account_numbers_response = client.get_account_numbers

          unless account_numbers_response&.body
            log_error("Failed to retrieve account numbers")
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**Error**: Failed to retrieve account numbers from Schwab API"
            }])
          end

          account_mappings = JSON.parse(account_numbers_response.body)
          log_debug("Retrieved #{account_mappings.length} accounts from Schwab API")

          configured_accounts = find_configured_accounts(account_mappings)

          if configured_accounts.empty?
            return MCP::Tool::Response.new([{
              type: "text",
              text: "**No Configured Accounts Found**\n\nNo environment variables found ending with '_ACCOUNT'.\n\nTo configure accounts, set environment variables like:\n- TRADING_BROKERAGE_ACCOUNT=123456789\n- RETIREMENT_IRA_ACCOUNT=987654321\n- INCOME_BROKERAGE_ACCOUNT=555666777"
            }])
          end

          formatted_response = format_accounts_list(configured_accounts, account_mappings)

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

      def self.find_configured_accounts(account_mappings)
        # Get all account IDs from Schwab API
        schwab_account_ids = account_mappings.map { |mapping| mapping["accountNumber"] }

        # Find environment variables ending with "_ACCOUNT"
        configured = []
        ENV.each do |key, value|
          next unless key.end_with?('_ACCOUNT')

          if schwab_account_ids.include?(value)
            configured << {
              name: key,
              friendly_name: friendly_name_from_env_key(key),
              account_id: value,
              mapping: account_mappings.find { |m| m["accountNumber"] == value }
            }
          end
        end

        configured.sort_by { |account| account[:name] }
      end

      def self.friendly_name_from_env_key(env_key)
        # Convert "TRADING_BROKERAGE_ACCOUNT" to "Trading Brokerage"
        env_key.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')
      end

      def self.format_accounts_list(configured_accounts, all_mappings)
        response = "**Configured Schwab Accounts:**\n\n"

        configured_accounts.each_with_index do |account, index|
          response += "#{index + 1}. **#{account[:friendly_name]}** (`#{account[:name]}`)\n"
          response += "   - Account ID: [REDACTED]\n"
          response += "   - Status: ✅ Configured\n\n"
        end

        # Show unconfigured accounts (if any)
        unconfigured = all_mappings.reject do |mapping|
          configured_accounts.any? { |config| config[:account_id] == mapping["accountNumber"] }
        end

        if unconfigured.any?
          response += "**Unconfigured Accounts Available:**\n\n"
          unconfigured.each_with_index do |mapping, index|
            response += "#{index + 1}. Account ID: [REDACTED]\n"
            response += "   - To configure: Set `YOUR_NAME_ACCOUNT=[REDACTED]` in your .env file\n\n"
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
