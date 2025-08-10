require "mcp"
require "schwab_rb"
require "json"
require_relative "../loggable"
require_relative "../redactor"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class PreviewOrderTool < MCP::Tool
      extend Loggable
      description "Preview an options order (iron condor, call spread, put spread) to validate the order structure and see estimated costs/proceeds before placing"

      input_schema(
        properties: {
          account_name: {
            type: "string",
            description: "Account name mapped to environment variable ending with '_ACCOUNT' (e.g., 'TRADING_BROKERAGE_ACCOUNT')",
            pattern: "^[A-Z_]+_ACCOUNT$"
          },
          strategy_type: {
            type: "string",
            enum: ["ironcondor", "vertical", "single"],
            description: "Type of options strategy to preview"
          },
          price: {
            type: "number",
            description: "Net price for the order (credit for selling strategies, debit for buying strategies)"
          },
          quantity: {
            type: "integer",
            description: "Number of contracts (default: 1)",
            default: 1
          },
          order_instruction: {
            type: "string",
            enum: ["open", "exit"],
            description: "Whether to open a new position or exit an existing one (default: open)",
            default: "open"
          },
          credit_debit: {
            type: "string",
            enum: %w[credit debit],
            description: "Whether the order is a credit or debit (default: credit)",
            default: "credit"
          },
          # Iron Condor specific fields
          put_short_symbol: {
            type: "string",
            description: "Option symbol for the short put leg (required for iron condor)"
          },
          put_long_symbol: {
            type: "string",
            description: "Option symbol for the long put leg (required for iron condor)"
          },
          call_short_symbol: {
            type: "string",
            description: "Option symbol for the short call leg (required for iron condor)"
          },
          call_long_symbol: {
            type: "string",
            description: "Option symbol for the long call leg (required for iron condor)"
          },
          # Vertical spread specific fields
          short_leg_symbol: {
            type: "string",
            description: "Option symbol for the short leg (required for call/put spreads)"
          },
          long_leg_symbol: {
            type: "string",
            description: "Option symbol for the long leg (required for call/put spreads)"
          },
          # Single option specific field
          symbol: {
            type: "string",
            description: "Single option symbol to place an order for (required for single options)"
          }
        },
        required: ["account_name", "strategy_type", "price"]
      )

      annotations(
        title: "Preview Options Order",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(server_context:, **params)
        log_info("Previewing #{params[:strategy_type]} order for account name: #{params[:account_name]}")

        unless params[:account_name].end_with?('_ACCOUNT')
          log_error("Invalid account name format: #{params[:account_name]}")
          error_msg = "**Error**: Account name must end with '_ACCOUNT'. Example: 'TRADING_BROKERAGE_ACCOUNT'"
          return MCP::Tool::Response.new([{
            type: "text",
            text: Redactor.redact_formatted_text(error_msg)
          }])
        end

        begin
          validate_strategy_params(params)
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          account_result = resolve_account_details(client, params[:account_name])
          return account_result if account_result.is_a?(MCP::Tool::Response)

          account_id, account_hash = account_result

          order_builder = SchwabRb::Orders::OrderFactory.build(
            strategy_type: params[:strategy_type],
            account_number: account_id,
            price: params[:price],
            quantity: params[:quantity] || 1,
            order_instruction: (params[:order_instruction] || "open").to_sym,
            credit_debit: (params[:credit_debit] || "credit").to_sym,
            # Iron Condor params
            put_short_symbol: params[:put_short_symbol],
            put_long_symbol: params[:put_long_symbol],
            call_short_symbol: params[:call_short_symbol],
            call_long_symbol: params[:call_long_symbol],
            # Vertical spread params
            short_leg_symbol: params[:short_leg_symbol],
            long_leg_symbol: params[:long_leg_symbol],
            # Single option params
            symbol: params[:symbol],
          )

          log_debug("Making preview order API request")
          response = client.preview_order(account_hash, order_builder, return_data_objects: true)

          if response
            log_info("Successfully previewed #{params[:strategy_type]} order")
            formatted_response = format_preview_response(response, params)
            MCP::Tool::Response.new([{
              type: "text",
              text: formatted_response
            }])
          else
            log_warn("Empty response from Schwab API for order preview")
            error_msg = "**No Data**: Empty response from Schwab API for order preview"
            MCP::Tool::Response.new([{
              type: "text",
              text: Redactor.redact_formatted_text(error_msg)
            }])
          end

        rescue => e
          log_error("Error previewing #{params[:strategy_type]} order: #{e.message}")
          error_msg = "**Error** previewing #{params[:strategy_type]} order: #{e.message}\n\n#{e.backtrace.first(3).join('\\n')}"
          MCP::Tool::Response.new([{
            type: "text",
            text: Redactor.redact_formatted_text(error_msg)
          }])
        end
      end

      private

      def self.resolve_account_details(client, account_name)
        account_id = ENV[account_name]
        unless account_id
          available_accounts = ENV.keys.select { |key| key.end_with?('_ACCOUNT') }
          log_error("Account name '#{account_name}' not found in environment variables")
          error_msg = "**Error**: Account name '#{account_name}' not found in environment variables.\n\nAvailable accounts: #{available_accounts.join(', ')}\n\nTo configure: Set ENV['#{account_name}'] to your account ID."
          return MCP::Tool::Response.new([{
            type: "text",
            text: Redactor.redact_formatted_text(error_msg)
          }])
        end

        log_debug("Found account ID: [REDACTED] for account name: #{account_name}")
        log_debug("Fetching account numbers mapping")

        account_numbers = client.get_account_numbers(return_data_objects: true)
        unless account_numbers && !account_numbers.empty?
          log_error("Failed to retrieve account numbers or no accounts returned")
          error_msg = "**Error**: Failed to retrieve account numbers from Schwab API or no accounts returned"
          return MCP::Tool::Response.new([{
            type: "text",
            text: Redactor.redact_formatted_text(error_msg)
          }])
        end

        mapping = account_numbers.accounts.find { |acct| acct.account_number == account_id }
        unless mapping
          log_error("Account ID not found in available accounts")
          error_msg = "**Error**: Account ID not found in available accounts. #{account_numbers.size} accounts available."
          return MCP::Tool::Response.new([{
            type: "text",
            text: Redactor.redact_formatted_text(error_msg)
          }])
        end

        log_debug("Found account hash for account name: #{account_name}")
        [account_id, mapping.hash_value]
      end

      def self.validate_strategy_params(params)
        case params[:strategy_type]
        when 'ironcondor'
          required_fields = [:put_short_symbol, :put_long_symbol, :call_short_symbol, :call_long_symbol]
          missing_fields = required_fields.select { |field| params[field].nil? || params[field].empty? }
          unless missing_fields.empty?
            raise ArgumentError, "Iron condor strategy requires: #{missing_fields.join(', ')}"
          end
        when 'vertical'
          required_fields = [:short_leg_symbol, :long_leg_symbol]
          missing_fields = required_fields.select { |field| params[field].nil? || params[field].empty? }
          unless missing_fields.empty?
            raise ArgumentError, "#{params[:strategy_type]} strategy requires: #{missing_fields.join(', ')}"
          end
        when 'single'
          required_fields = [:symbol]
          missing_fields = required_fields.select { |field| params[field].nil? || params[field].empty? }
          unless missing_fields.empty?
            raise ArgumentError, "#{params[:strategy_type]} strategy requires: #{missing_fields.join(', ')}"
          end
        else
          raise ArgumentError, "Unsupported strategy type: #{params[:strategy_type]}"
        end
      end

      def self.format_preview_response(response_body, params)
        parsed = JSON.parse(response_body)
        redacted_data = Redactor.redact(parsed)

        begin
          strategy_summary = case params[:strategy_type]
          when 'ironcondor'
            "**Iron Condor Preview**\n" \
            "- Put Short: #{params[:put_short_symbol]}\n" \
            "- Put Long: #{params[:put_long_symbol]}\n" \
            "- Call Short: #{params[:call_short_symbol]}\n" \
            "- Call Long: #{params[:call_long_symbol]}\n"
          when 'vertical'
            "**Vertical Preview**\n" \
            "- Short Leg: #{params[:short_leg_symbol]}\n" \
            "- Long Leg: #{params[:long_leg_symbol]}\n"
          when 'single'
            "**Single Option Preview**\n" \
            "- Symbol: #{params[:symbol]}\n"
          end

          friendly_name = params[:account_name].gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

          order_details = "**Order Details:**\n" \
                         "- Strategy: #{params[:strategy_type]}\n" \
                         "- Action: #{params[:order_instruction] || 'open'}\n" \
                         "- Quantity: #{params[:quantity] || 1}\n" \
                         "- Price: $#{params[:price]}\n" \
                         "- Account: #{friendly_name} (#{params[:account_name]})\n\n"

          full_response = "**Schwab API Preview Response:**\n\n```json\n#{JSON.pretty_generate(redacted_data)}\n```"

          "#{strategy_summary}\n#{order_details}#{full_response}"
        rescue JSON::ParserError
          "**Order Preview Response:**\n\n```\n#{JSON.pretty_generate(redacted_data)}\n```"
        end
      end
      def self.format_preview_response(order_preview, params)
        # order_preview is a SchwabRb::DataObjects::OrderPreview
        begin
          strategy_summary = case params[:strategy_type]
          when 'ironcondor'
            "**Iron Condor Preview**\n" \
            "- Put Short: #{params[:put_short_symbol]}\n" \
            "- Put Long: #{params[:put_long_symbol]}\n" \
            "- Call Short: #{params[:call_short_symbol]}\n" \
            "- Call Long: #{params[:call_long_symbol]}\n"
          when 'vertical'
            "**Vertical Preview**\n" \
            "- Short Leg: #{params[:short_leg_symbol]}\n" \
            "- Long Leg: #{params[:long_leg_symbol]}\n"
          when 'single'
            "**Single Option Preview**\n" \
            "- Symbol: #{params[:symbol]}\n"
          end

          friendly_name = params[:account_name].gsub('_ACCOUNT', '').split('_').map(&:capitalize).join(' ')

          order_details = "**Order Details:**\n" \
                         "- Strategy: #{params[:strategy_type]}\n" \
                         "- Action: #{params[:order_instruction] || 'open'}\n" \
                         "- Quantity: #{params[:quantity] || 1}\n" \
                         "- Price: $#{params[:price]}\n" \
                         "- Account: #{friendly_name} (#{params[:account_name]})\n\n"

          # Use OrderPreview data object for summary
          op = order_preview
          summary = "**Preview Result:**\n" \
                    "- Status: #{op.status || 'N/A'}\n" \
                    "- Price: $#{op.price || 'N/A'}\n" \
                    "- Quantity: #{op.quantity || 'N/A'}\n" \
                    "- Commission: $#{op.commission}\n" \
                    "- Fees: $#{op.fees}\n" \
                    "- Accepted?: #{op.accepted? ? 'Yes' : 'No'}\n"

          # Redact and pretty print the full data object as JSON
          redacted_data = Redactor.redact(op.to_h)
          full_response = "**Schwab API Preview Response:**\n\n```json\n#{JSON.pretty_generate(redacted_data)}\n```"

          "#{strategy_summary}\n#{order_details}#{summary}\n#{full_response}"
        rescue => e
          "**Order Preview Response:**\n\nError formatting preview: #{e.message}"
        end
      end
    end
  end
end
