require "mcp"
require "schwab_rb"
require_relative "../loggable"
require_relative "../redactor"
require_relative "../schwab_client_factory"

module SchwabMCP
  module Tools
    class ReplaceOrderTool < MCP::Tool
      extend Loggable
      description "Replace an existing options order with a new order (iron condor, call spread, put spread). The existing order will be canceled and a new order will be created."

      input_schema(
        properties: {
          account_name: {
            type: "string",
            description: "Account name mapped to environment variable ending with '_ACCOUNT' (e.g., 'TRADING_BROKERAGE_ACCOUNT')",
            pattern: "^[A-Z_]+_ACCOUNT$"
          },
          order_id: {
            type: "string",
            description: "The ID of the existing order to replace"
          },
          strategy_type: {
            type: "string",
            enum: %w[SINGLE VERTICAL IRON_CONDOR],
            description: "Type of options strategy for the replacement order"
          },
          price: {
            type: "number",
            description: "Net price for the replacement order (credit for selling strategies, debit for buying strategies)"
          },
          quantity: {
            type: "integer",
            description: "Number of contracts (default: 1)",
            default: 1
          },
          order_instruction: {
            type: "string",
            enum: %w[open exit],
            description: "Whether to open a new position or exit an existing one (default: open)",
            default: "open"
          },
          credit_debit: {
            type: "string",
            enum: %w[credit debit],
            description: "Whether the order is a credit or debit (default: credit)",
            default: "credit"
          },
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
          short_leg_symbol: {
            type: "string",
            description: "Option symbol for the short leg (required for call/put spreads)"
          },
          long_leg_symbol: {
            type: "string",
            description: "Option symbol for the long leg (required for call/put spreads)"
          },
          symbol: {
            type: "string",
            description: "Single option symbol to place an order for (required for single options)"
          }
        },
        required: %w[account_name order_id strategy_type price]
      )

      annotations(
        title: "Replace Options Order",
        read_only_hint: false,
        destructive_hint: true,
        idempotent_hint: false
      )

      def self.call(server_context:, **params)
        log_info("Replacing order #{params[:order_id]} with #{params[:strategy_type]} order for account name: #{params[:account_name]}")

        unless params[:account_name].end_with?("_ACCOUNT")
          log_error("Invalid account name format: #{params[:account_name]}")
          return MCP::Tool::Response.new([{
                                           type: "text",
                                           text: "**Error**: Account name must end with '_ACCOUNT'. Example: 'TRADING_BROKERAGE_ACCOUNT'"
                                         }])
        end

        begin
          validate_strategy_params(params)
          client = SchwabClientFactory.create_client
          return SchwabClientFactory.client_error_response unless client

          account_result = resolve_account_details(client, params[:account_name])
          return account_result if account_result.is_a?(MCP::Tool::Response)

          order_builder = SchwabRb::Orders::OrderFactory.build(
            strategy_type: params[:strategy_type],
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
            symbol: params[:symbol]
          )

          log_debug("Making replace order API request for order ID: #{params[:order_id]}")
          response = client.replace_order(account_name: params[:account_name], order_id: params[:order_id], order: order_builder)

          if response && (200..299).include?(response.status)
            log_info("Successfully replaced order #{params[:order_id]} with #{params[:strategy_type]} order (HTTP #{response.status})")
            formatted_response = format_replace_order_response(response, params)
            MCP::Tool::Response.new([{
                                      type: "text",
                                      text: formatted_response
                                    }])
          elsif response
            log_error("Order replacement failed with HTTP status #{response.status}")
            error_details = extract_error_details(response)
            MCP::Tool::Response.new([{
                                      type: "text",
                                      text: "**Error**: Order replacement failed (HTTP #{response.status})\n\n#{error_details}"
                                    }])
          else
            log_warn("Empty response from Schwab API for order replacement")
            MCP::Tool::Response.new([{
                                      type: "text",
                                      text: "**No Data**: Empty response from Schwab API for order replacement"
                                    }])
          end
        rescue StandardError => e
          log_error("Error replacing order #{params[:order_id]} with #{params[:strategy_type]} order: #{e.message}")
          log_debug("Backtrace: #{e.backtrace.first(5).join('\n')}")
          MCP::Tool::Response.new([{
                                    type: "text",
                                    text: "**Error** replacing order #{params[:order_id]} with #{params[:strategy_type]} order: #{e.message}\n\n#{e.backtrace.first(3).join('\n')}"
                                  }])
        end
      end

      def self.resolve_account_details(client, account_name)
        available_accounts = client.available_account_names
        unless available_accounts.include?(account_name)
          log_error("Account name '#{account_name}' not found in configured accounts")
          return MCP::Tool::Response.new([{
                                           type: "text",
                                           text: "**Error**: Account name '#{account_name}' not found in configured accounts.\n\nAvailable accounts: #{available_accounts.join(", ")}\n\nTo configure: Add the account to your schwab_rb configuration file."
                                         }])
        end

        log_debug("Using account name: #{account_name}")
        account_name
      end

      def self.validate_strategy_params(params)
        strategy = params[:strategy_type].to_s.upcase
        case strategy
        when 'IRON_CONDOR'
          required_fields = %i[put_short_symbol put_long_symbol call_short_symbol call_long_symbol]
          missing_fields = required_fields.select { |field| params[field].nil? || params[field].empty? }
          unless missing_fields.empty?
            raise ArgumentError, "Iron condor strategy requires: #{missing_fields.join(", ")}"
          end
        when 'VERTICAL'
          required_fields = %i[short_leg_symbol long_leg_symbol]
          missing_fields = required_fields.select { |field| params[field].nil? || params[field].empty? }
          unless missing_fields.empty?
            raise ArgumentError, "#{params[:strategy_type]} strategy requires: #{missing_fields.join(", ")}"
          end
        when 'SINGLE'
          required_fields = %i[symbol]
          missing_fields = required_fields.select { |field| params[field].nil? || params[field].empty? }
          unless missing_fields.empty?
            raise ArgumentError, "#{params[:strategy_type]} strategy requires: #{missing_fields.join(", ")}"
          end
        else
          raise ArgumentError, "Unsupported strategy type: #{params[:strategy_type]}"
        end
      end

      def self.format_replace_order_response(response, params)
        strategy = params[:strategy_type].to_s.upcase
        strategy_summary = case strategy
        when 'IRON_CONDOR'
          "**Iron Condor Order Replaced**\n" \
          "- Put Short: #{params[:put_short_symbol]}\n" \
          "- Put Long: #{params[:put_long_symbol]}\n" \
          "- Call Short: #{params[:call_short_symbol]}\n" \
          "- Call Long: #{params[:call_long_symbol]}\n"
        when 'VERTICAL'
          "**Vertical Spread Order Replaced**\n" \
          "- Short Leg: #{params[:short_leg_symbol]}\n" \
          "- Long Leg: #{params[:long_leg_symbol]}\n"
        when 'SINGLE'
          "**Single Option Order Replaced**\n" \
          "- Symbol: #{params[:symbol]}\n"
        end

        friendly_name = params[:account_name].gsub("_ACCOUNT", "").split("_").map(&:capitalize).join(" ")

        order_details = "**Replacement Order Details:**\n" \
                       "- Original Order ID: #{params[:order_id]}\n" \
                       "- Strategy: #{params[:strategy_type]}\n" \
                       "- Action: #{params[:order_instruction] || "open"}\n" \
                       "- Quantity: #{params[:quantity] || 1}\n" \
                       "- Price: $#{params[:price]}\n" \
                       "- Account: #{friendly_name} (#{params[:account_name]})\n\n"

        new_order_id = extract_order_id_from_response(response)
        order_id_info = new_order_id ? "**New Order ID**: #{new_order_id}\n\n" : ""

        response_info = if response.body && !response.body.empty?
                          begin
                            parsed = JSON.parse(response.body)
                            redacted_data = Redactor.redact(parsed)
                            "**Schwab API Response:**\n\n```json\n#{JSON.pretty_generate(redacted_data)}\n```"
                          rescue JSON::ParserError
                            "**Schwab API Response:**\n\n```\n#{response.body}\n```"
                          end
                        else
                          "**Status**: Order replaced successfully (HTTP #{response.status})\n\n" \
                          "The original order has been canceled and a new order has been created."
                        end

        "#{strategy_summary}\n#{order_details}#{order_id_info}#{response_info}"
      rescue StandardError => e
        log_error("Error formatting response: #{e.message}")
        "**Order Status**: #{response.status}\n\n**Raw Response**: #{response.body}"
      end

      def self.extract_order_id_from_response(response)
        # Schwab API typically returns the new order ID in the Location header
        # Format: https://api.schwabapi.com/trader/v1/accounts/{accountHash}/orders/{orderId}
        location = response.headers["Location"] || response.headers["location"]
        return nil unless location

        # Extract order ID from the URL path
        match = location.match(%r{/orders/(\d+)$})
        match ? match[1] : nil
      rescue StandardError => e
        log_debug("Could not extract order ID from response: #{e.message}")
        nil
      end

      def self.extract_error_details(response)
        if response.body && !response.body.empty?
          begin
            parsed = JSON.parse(response.body)
            redacted_data = Redactor.redact(parsed)
            "**Error Details:**\n\n```json\n#{JSON.pretty_generate(redacted_data)}\n```"
          rescue JSON::ParserError
            "**Error Details:**\n\n```\n#{response.body}\n```"
          end
        else
          "No additional error details provided."
        end
      rescue StandardError => e
        log_debug("Error extracting error details: #{e.message}")
        "Could not extract error details."
      end
    end
  end
end
