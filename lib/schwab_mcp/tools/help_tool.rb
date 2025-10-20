require "mcp"
require_relative "../loggable"

module SchwabMCP
  module Tools
    class HelpTool < MCP::Tool
      extend Loggable
      description "Get comprehensive help and documentation for the Schwab MCP server tools and capabilities"

      input_schema(
        properties: {
          topic: {
            type: "string",
            description: "Optional specific topic to get help for. Available: 'tools', 'setup'",
            enum: ["tools", "setup"]
          }
        },
        required: []
      )

      annotations(
        title: "Get Help and Documentation",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(topic: nil, server_context:)
        log_info("Help requested for topic: #{topic || 'general'}")

        help_content = if topic
          get_topic_help(topic)
        else
          get_general_help
        end

        MCP::Tool::Response.new([{
          type: "text",
          text: help_content
        }])
      end

      private

      def self.get_general_help
        <<~HELP
          # Schwab MCP Server

          ## Available Tools:

          ### Market Data & Analysis:
          - **quote_tool**: Get real-time quote for a single symbol
          - **quotes_tool**: Get real-time quotes for multiple symbols
          - **option_chain_tool**: Get option chain data for a symbol
          - **get_price_history_tool**: Get historical price data for an instrument
          - **get_market_hours_tool**: Get market hours for specified markets
          - **list_movers_tool**: Get top ten movers for a given index

          ### Option Order Tools:
          - **preview_order_tool**: Preview an options order before placing (SAFE PREVIEW)
          - **place_order_tool**: Place an options order for execution (DESTRUCTIVE)
          - **replace_order_tool**: Replace an existing order with a new one (DESTRUCTIVE)

          ### Account Management:
          - **schwab_account_details_tool**: Get account information using account name mapping
          - **list_schwab_accounts_tool**: List all available Schwab accounts
          - **list_account_orders_tool**: List orders for a specific account using account name mapping
          - **list_account_transactions_tool**: List transactions for a specific account
          - **get_order_tool**: Get detailed information for a specific order by order ID
          - **cancel_order_tool**: Cancel a specific order by order ID (DESTRUCTIVE)

          ### Documentation:
          - **help_tool**: This help system

          ## Usage Examples:
          ```
          # Market Data
          quote_tool(symbol: "AAPL")
          quotes_tool(symbols: ["AAPL", "TSLA", "MSFT"])
          get_price_history_tool(symbol: "SPX", period_type: "day", period: 5, frequency_type: "minute", frequency: 5)
          get_market_hours_tool(markets: ["equity", "option"])
          list_movers_tool(index: "$SPX", sort_order: "PERCENT_CHANGE_UP")

          # Options
          option_chain_tool(symbol: "SPX", contract_type: "ALL")
          preview_order_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", strategy_type: "ironcondor", price: 1.50, quantity: 1)

          # Account Management
          schwab_account_details_tool(account_name: "TRADING_BROKERAGE_ACCOUNT")
          list_schwab_accounts_tool()
          list_account_orders_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", status: "WORKING")
          list_account_transactions_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", start_date: "2025-01-01")
          get_order_tool(order_id: "123456789", account_name: "TRADING_BROKERAGE_ACCOUNT")
          cancel_order_tool(order_id: "123456789", account_name: "TRADING_BROKERAGE_ACCOUNT")

          # Help
          help_tool(topic: "setup")
          ```

          ## Help Topics:
          - `tools` - Detailed tool documentation
          - `setup` - Configuration and authentication setup

          Use `help_tool(topic: "setup")` for initial configuration.
        HELP
      end

      def self.get_topic_help(topic)
        case topic
        when "tools"
          get_tools_help
        when "setup"
          get_setup_help
        else
          "**Error**: Unknown topic '#{topic}'. Available topics: tools, setup"
        end
      end

      def self.get_tools_help
        <<~HELP
          # Available Tools

          ## Market Data & Analysis Tools

          ### quote_tool
          Get real-time quote for a single symbol.
          **Parameters**: `symbol` (required) - e.g., "AAPL", "TSLA"
          **Example**: `quote_tool(symbol: "AAPL")`

          ### quotes_tool
          Get real-time quotes for multiple symbols.
          **Parameters**:
          - `symbols` (required) - Array of symbols, e.g., ["AAPL", "TSLA"]
          - `fields` (optional) - Specific fields to return
          - `indicative` (optional) - Boolean for indicative quotes

          **Examples**:
          ```
          quotes_tool(symbols: ["AAPL", "TSLA", "MSFT"])
          quotes_tool(symbols: ["/ES"], indicative: true)
          ```

          ### get_price_history_tool
          Get historical price data for an instrument symbol.
          **Parameters**:
          - `symbol` (required) - Instrument symbol (e.g., "AAPL", "$SPX")
          - `period_type` (optional) - "day", "month", "year", "ytd"
          - `period` (optional) - Number of periods based on period_type
          - `frequency_type` (optional) - "minute", "daily", "weekly", "monthly"
          - `frequency` (optional) - Frequency of data points
          - `start_datetime`, `end_datetime` (optional) - ISO format date range
          - `need_extended_hours_data` (optional) - Include pre/post market data
          - `need_previous_close` (optional) - Include previous close

          **Examples**:
          ```
          get_price_history_tool(symbol: "SPX", period_type: "day", period: 5, frequency_type: "minute", frequency: 5)
          get_price_history_tool(symbol: "AAPL", start_datetime: "2025-01-01T00:00:00Z", end_datetime: "2025-01-15T23:59:59Z")
          ```

          ### get_market_hours_tool
          Get market hours for specified markets.
          **Parameters**:
          - `markets` (required) - Array of markets: ["equity", "option", "bond", "future", "forex"]
          - `date` (optional) - Date in YYYY-MM-DD format (defaults to today)

          **Examples**:
          ```
          get_market_hours_tool(markets: ["equity", "option"])
          get_market_hours_tool(markets: ["future"], date: "2025-01-17")
          ```

          ### list_movers_tool
          Get top ten movers for a given index.
          **Parameters**:
          - `index` (required) - "$DJI", "$COMPX", "$SPX", "NYSE", "NASDAQ", etc.
          - `sort_order` (optional) - "VOLUME", "TRADES", "PERCENT_CHANGE_UP", "PERCENT_CHANGE_DOWN"
          - `frequency` (optional) - Magnitude filter: 0, 1, 5, 10, 30, 60

          **Examples**:
          ```
          list_movers_tool(index: "$SPX", sort_order: "PERCENT_CHANGE_UP")
          list_movers_tool(index: "NASDAQ", frequency: 5)
          ```

          ## Option Tools

          ### option_chain_tool
          Get option chain data for an optionable symbol.
          **Parameters**:
          - `symbol` (required) - Underlying symbol, e.g., "SPX", "AAPL"
          - `contract_type` (optional) - "CALL", "PUT", or "ALL"
          - `from_date`, `to_date` (optional) - Date range for expirations
          - Many other optional parameters for filtering

          **Example**: `option_chain_tool(symbol: "SPX", contract_type: "ALL")`

          ## Order Management Tools

          ### preview_order_tool SAFE PREVIEW
          Preview an options order before placing to validate structure and see estimated costs.
          **Parameters**:
          - `account_name` (required) - Account name ending with '_ACCOUNT'
          - `strategy_type` (required) - "ironcondor", "callspread", "putspread"
          - `price` (required) - Net price for the order
          - `quantity` (optional) - Number of contracts (default: 1)
          - `order_instruction` (optional) - "open" or "exit" (default: "open")
          - Strategy-specific symbol parameters (e.g., put_short_symbol, call_long_symbol)

          **Examples**:
          ```
          preview_order_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", strategy_type: "ironcondor", price: 1.50, quantity: 1)
          preview_order_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", strategy_type: "callspread", short_symbol: "SPY250117C00600000", long_symbol: "SPY250117C00610000", price: 2.50)
          ```

          ### place_order_tool DESTRUCTIVE OPERATION
          Place an options order for execution. **WARNING**: This places real orders with real money.
          **Parameters**: Same as preview_order_tool
          **Safety Features**:
          - Validates order structure before placing
          - Returns order ID for tracking
          - Provides detailed confirmation

          **Examples**:
          ```
          place_order_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", strategy_type: "ironcondor", price: 1.50, quantity: 1)
          ```

          ### replace_order_tool DESTRUCTIVE OPERATION
          Replace an existing order with a new one. **WARNING**: Cancels existing order and places new one.
          **Parameters**:
          - `order_id` (required) - ID of existing order to replace
          - All other parameters same as place_order_tool

          **Examples**:
          ```
          replace_order_tool(order_id: "123456789", account_name: "TRADING_BROKERAGE_ACCOUNT", strategy_type: "ironcondor", price: 1.75, quantity: 1)
          ```

          ## Account Management Tools

          ### schwab_account_details_tool
          Get detailed account information using account name mapping.
          **Parameters**:
          - `account_name` (required) - Account name ending with '_ACCOUNT' (e.g., "TRADING_BROKERAGE_ACCOUNT")
          - `fields` (optional) - Array of specific fields to retrieve ["balances", "positions", "orders"]

          **Examples**:
          ```
          schwab_account_details_tool(account_name: "TRADING_BROKERAGE_ACCOUNT")
          schwab_account_details_tool(account_name: "IRA_ACCOUNT", fields: ["balances", "positions"])
          ```

          ### list_schwab_accounts_tool
          List all available Schwab accounts with their details.
          **Parameters**: None required
          **Example**: `list_schwab_accounts_tool()`

          ### list_account_orders_tool
          List orders for a specific account using account name mapping.
          **Parameters**:
          - `account_name` (required) - Account name ending with '_ACCOUNT'
          - `max_results` (optional) - Maximum number of orders to retrieve
          - `from_date` (optional) - Start date in YYYY-MM-DD format (default: 60 days ago)
          - `to_date` (optional) - End date in YYYY-MM-DD format (default: today)
          - `status` (optional) - Filter by order status (WORKING, FILLED, CANCELED, etc.)

          **Examples**:
          ```
          list_account_orders_tool(account_name: "TRADING_BROKERAGE_ACCOUNT")
          list_account_orders_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", status: "WORKING")
          list_account_orders_tool(account_name: "IRA_ACCOUNT", from_date: "2025-01-01", to_date: "2025-01-15", max_results: 50)
          ```

          ### list_account_transactions_tool
          List transactions for a specific account using account name mapping.
          **Parameters**:
          - `account_name` (required) - Account name ending with '_ACCOUNT'
          - `start_date` (optional) - Start date in YYYY-MM-DD format (default: 60 days ago)
          - `end_date` (optional) - End date in YYYY-MM-DD format (default: today)
          - `transaction_types` (optional) - Array of transaction types to filter by

          **Examples**:
          ```
          list_account_transactions_tool(account_name: "TRADING_BROKERAGE_ACCOUNT")
          list_account_transactions_tool(account_name: "TRADING_BROKERAGE_ACCOUNT", start_date: "2025-01-01", transaction_types: ["TRADE", "DIVIDEND_OR_INTEREST"])
          ```

          ### get_order_tool
          Get detailed information for a specific order by order ID.
          **Parameters**:
          - `order_id` (required) - The numeric order ID to retrieve details for
          - `account_name` (required) - Account name ending with '_ACCOUNT'

          **Examples**:
          ```
          get_order_tool(order_id: "123456789", account_name: "TRADING_BROKERAGE_ACCOUNT")
          get_order_tool(order_id: "987654321", account_name: "IRA_ACCOUNT")
          ```

          ### cancel_order_tool DESTRUCTIVE OPERATION
          Cancel a specific order by order ID. **WARNING**: This action cannot be undone.
          **Parameters**:
          - `order_id` (required) - The numeric order ID to cancel
          - `account_name` (required) - Account name ending with '_ACCOUNT'

          **Safety Features**:
          - Verifies order exists before attempting cancellation
          - Checks if order is cancelable (based on status)
          - Provides detailed confirmation when successful
          - Returns helpful error messages for invalid requests

          **Examples**:
          ```
          cancel_order_tool(order_id: "123456789", account_name: "TRADING_BROKERAGE_ACCOUNT")
          cancel_order_tool(order_id: "987654321", account_name: "IRA_ACCOUNT")
          ```

          **Important Notes**:
          - Only working orders can typically be cancelled
          - Filled, expired, or already cancelled orders cannot be cancelled
          - Always verify cancellation using get_order_tool or list_account_orders_tool

          ## Documentation

          ### help_tool
          Get help and documentation.
          **Parameters**: `topic` (optional) - "tools" or "setup"
          **Example**: `help_tool(topic: "setup")`

          **Supported symbols**: Stocks (AAPL), Futures (/ES), ETFs, etc.
          **Limits**: Max 500 symbols per quotes_tool request
        HELP
      end

      def self.get_setup_help
        <<~HELP
          # Setup Guide

          ## 1. Environment Variables
          Set these required environment variables:
          ```bash
          export SCHWAB_API_KEY="your_app_key"
          export SCHWAB_APP_SECRET="your_app_secret"
          export SCHWAB_CALLBACK_URI="https://localhost:8443/callback"
          export TOKEN_PATH="./token.json"
          ```

          **Account Environment Variables** (for account-specific tools):
          ```bash
          export TRADING_BROKERAGE_ACCOUNT="your_account_number"
          export IRA_ACCOUNT="your_ira_account_number"
          # Add more accounts as needed, always ending with '_ACCOUNT'
          ```

          ## 2. Initial Authentication
          Run the token refresh script to authenticate:
          ```bash
          ./exe/schwab_token_refresh
          ```

          This will:
          - Open a browser for Schwab login
          - Complete OAuth2 flow
          - Save tokens to TOKEN_PATH

          ## 3. Start Server
          ```bash
          ./exe/schwab_mcp
          ```

          ## Prerequisites:
          - Schwab brokerage account
          - Approved Schwab developer account (developer.schwab.com)
          - Ruby 3.0+

          ## Troubleshooting:
          - Ensure callback URL matches exactly in your Schwab app settings
          - Check token file permissions
          - Verify environment variables are set correctly
        HELP
      end
    end
  end
end
