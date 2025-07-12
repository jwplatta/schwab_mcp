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
          # 📊 Schwab MCP Server

          ## Available Tools:
          - **quote_tool**: Get real-time quote for a single symbol
          - **quotes_tool**: Get real-time quotes for multiple symbols
          - **help_tool**: This help system

          ## Usage Examples:
          ```
          quote_tool(symbol: "AAPL")
          quotes_tool(symbols: ["AAPL", "TSLA", "MSFT"])
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
          # 🔧 Available Tools

          ## quote_tool
          Get real-time quote for a single symbol.
          **Parameters**: `symbol` (required) - e.g., "AAPL", "TSLA"
          **Example**: `quote_tool(symbol: "AAPL")`

          ## quotes_tool
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

          ## help_tool
          Get help and documentation.
          **Parameters**: `topic` (optional) - "tools" or "setup"
          **Example**: `help_tool(topic: "setup")`

          **Supported symbols**: Stocks (AAPL), Futures (/ES), ETFs, etc.
          **Limits**: Max 500 symbols per quotes_tool request
        HELP
      end

      def self.get_setup_help
        <<~HELP
          # 🚀 Setup Guide

          ## 1. Environment Variables
          Set these required environment variables:
          ```bash
          export SCHWAB_API_KEY="your_app_key"
          export SCHWAB_APP_SECRET="your_app_secret"
          export SCHWAB_CALLBACK_URI="https://localhost:8443/callback"
          export TOKEN_PATH="./token.json"
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
