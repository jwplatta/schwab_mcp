require "mcp"
require "schwab_rb"
require "json"
require "date"
require_relative "../loggable"
require_relative "../redactor"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class ListAccountTransactionsTool < MCP::Tool
      extend Loggable
      description "List transactions for a specific account using account name mapping"

      input_schema(
        properties: {
          account_name: {
            type: "string",
            description: "Account name mapped to environment variable ending with '_ACCOUNT' (e.g., 'TRADING_BROKERAGE_ACCOUNT')",
            pattern: "^[A-Z_]+_ACCOUNT$"
          },
          start_date: {
            type: "string",
            description: "Start date for transactions in YYYY-MM-DD format (default: 60 days ago)",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$"
          },
          end_date: {
            type: "string",
            description: "End date for transactions in YYYY-MM-DD format (default: today)",
            pattern: "^\\d{4}-\\d{2}-\\d{2}$"
          },
          transaction_types: {
            type: "array",
            description: "Array of transaction types to filter by (optional, if not provided all types will be included)",
            items: {
              type: "string",
              enum: [
                "TRADE",
                "RECEIVE_AND_DELIVER",
                "DIVIDEND_OR_INTEREST",
                "ACH_RECEIPT",
                "ACH_DISBURSEMENT",
                "CASH_RECEIPT",
                "CASH_DISBURSEMENT",
                "ELECTRONIC_FUND",
                "WIRE_OUT",
                "WIRE_IN",
                "JOURNAL",
                "MEMORANDUM",
                "MARGIN_CALL",
                "MONEY_MARKET",
                "SMA_ADJUSTMENT"
              ]
            }
          },
          symbol: {
            type: "string",
            description: "Filter transactions by the specified symbol (optional)"
          }
        },
        required: ["account_name"]
      )

      annotations(
        title: "List Account Transactions",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(account_name:, start_date: nil, end_date: nil, transaction_types: nil, symbol: nil, server_context:)
        log_info("Listing transactions for account name: #{account_name}")

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

          start_date_obj = nil
          end_date_obj = nil

          if start_date
            begin
              start_date_obj = DateTime.parse("#{start_date}T00:00:00Z")
            rescue Date::Error => e
              log_error("Invalid start_date format: #{start_date}")
              return MCP::Tool::Response.new([{
                type: "text",
                text: "**Error**: Invalid start_date format. Use YYYY-MM-DD format."
              }])
            end
          end

          if end_date
            begin
              end_date_obj = DateTime.parse("#{end_date}T23:59:59Z")
            rescue Date::Error => e
              log_error("Invalid end_date format: #{end_date}")
              return MCP::Tool::Response.new([{
                type: "text",
                text: "**Error**: Invalid end_date format. Use YYYY-MM-DD format."
              }])
            end
          end

          log_debug("Fetching transactions with params - start_date: #{start_date_obj}, end_date: #{end_date_obj}, transaction_types: #{transaction_types}, symbol: #{symbol}")

          transactions_response = client.get_transactions(
            account_hash,
            start_date: start_date_obj,
            end_date: end_date_obj,
            transaction_types: transaction_types,
            symbol: symbol
          )

          if transactions_response&.body
            log_info("Successfully retrieved transactions for #{account_name}")
            # Use schwab_rb Transaction data objects
            transactions = if transactions_response.body.is_a?(Array)
              transactions_response.body.map { |t| SchwabRb::DataObjects::Transaction.build(t) }
            else
              [SchwabRb::DataObjects::Transaction.build(transactions_response.body)]
            end

            formatted_response = format_transactions_data(transactions, account_name, {
              start_date: start_date,
              end_date: end_date,
              transaction_types: transaction_types,
              symbol: symbol
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

        rescue JSON::ParserError => e
          log_error("JSON parsing error: #{e.message}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error**: Failed to parse API response: #{e.message}"
          }])
        rescue => e
          log_error("Error retrieving transactions for #{account_name}: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
          MCP::Tool::Response.new([{
            type: "text",
            text: "**Error** retrieving transactions for #{account_name}: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
          }])
        end
      end

      private

      def self.format_transactions_data(transactions, account_name, filters)
        friendly_name = account_name.gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

        formatted = "**Transactions for #{friendly_name} (#{account_name}):**\n\n"

        if filters.any? { |k, v| v }
          formatted += "**Filters Applied:**\n"
          formatted += "- Start Date: #{filters[:start_date]}\n" if filters[:start_date]
          formatted += "- End Date: #{filters[:end_date]}\n" if filters[:end_date]
          formatted += "- Transaction Types: #{filters[:transaction_types].join(', ')}\n" if filters[:transaction_types]&.any?
          formatted += "- Symbol: #{filters[:symbol]}\n" if filters[:symbol]
          formatted += "\n"
        end

        formatted += "**Transactions Summary:**\n"
        formatted += "- Total Transactions: #{transactions.length}\n\n"

        if transactions.length > 0
          transactions_by_type = transactions.group_by { |t| t.type }
          formatted += "**Transactions by Type:**\n"
          transactions_by_type.each do |type, type_transactions|
            formatted += "- #{type}: #{type_transactions.length} transactions\n"
          end
          formatted += "\n"

          formatted += "**Transaction Details:**\n"
          transactions.each_with_index do |transaction, index|
            formatted += format_single_transaction(transaction, index + 1)
            formatted += "\n" unless index == transactions.length - 1
          end
        else
          formatted += "No transactions found matching the specified criteria.\n"
        end

        # Redact using to_h for data objects
        redacted_data = Redactor.redact(transactions.map(&:to_h))
        formatted += "\n**Full Response (Redacted):**\n"
        formatted += "```json\n#{JSON.pretty_generate(redacted_data)}\n```"
        formatted
      end

      def self.format_single_transaction(transaction, transaction_num)
        formatted = "**Transaction #{transaction_num}:**\n"
        formatted += "- Activity ID: #{transaction.activity_id}\n" if transaction.activity_id
        formatted += "- Type: #{transaction.type}\n" if transaction.type
        formatted += "- Status: #{transaction.status}\n" if transaction.status
        formatted += "- Trade Date: #{transaction.trade_date}\n" if transaction.trade_date
        formatted += "- Net Amount: $#{format_currency(transaction.net_amount)}\n" if transaction.net_amount
        formatted += "- Sub Account: #{transaction.sub_account}\n" if transaction.sub_account
        formatted += "- Order ID: #{transaction.order_id}\n" if transaction.order_id
        formatted += "- Position ID: #{transaction.position_id}\n" if transaction.position_id

        if transaction.transfer_items && transaction.transfer_items.any?
          formatted += "- Transfer Items:\n"
          transaction.transfer_items.each_with_index do |item, i|
            formatted += "  * Item #{i + 1}:\n"
            formatted += "    - Amount: $#{format_currency(item.amount)}\n" if item.amount
            formatted += "    - Cost: $#{format_currency(item.cost)}\n" if item.cost
            formatted += "    - Fee Type: #{item.fee_type}\n" if item.fee_type
            formatted += "    - Position Effect: #{item.position_effect}\n" if item.position_effect

            if item.instrument
              formatted += "    - Instrument:\n"
              formatted += "      * Symbol: #{item.instrument.symbol}\n" if item.instrument.symbol
              formatted += "      * Asset Type: #{item.instrument.respond_to?(:asset_type) ? item.instrument.asset_type : nil}\n" if item.instrument.respond_to?(:asset_type) && item.instrument.asset_type
              formatted += "      * Description: #{item.instrument.description}\n" if item.instrument.description
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
