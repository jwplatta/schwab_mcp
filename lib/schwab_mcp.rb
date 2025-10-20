# frozen_string_literal: true

require "mcp"
require "mcp/transports/stdio"
require "tmpdir"
require "schwab_rb"
require_relative "schwab_mcp/version"
require_relative "schwab_mcp/redactor"
require_relative "schwab_mcp/tools/quote_tool"
require_relative "schwab_mcp/tools/quotes_tool"
require_relative "schwab_mcp/tools/option_chain_tool"
require_relative "schwab_mcp/tools/help_tool"
require_relative "schwab_mcp/tools/schwab_account_details_tool"
require_relative "schwab_mcp/tools/list_account_orders_tool"
require_relative "schwab_mcp/tools/list_account_transactions_tool"
require_relative "schwab_mcp/tools/get_order_tool"
require_relative "schwab_mcp/tools/cancel_order_tool"
require_relative "schwab_mcp/tools/preview_order_tool"
require_relative "schwab_mcp/tools/place_order_tool"
require_relative "schwab_mcp/tools/replace_order_tool"
require_relative "schwab_mcp/tools/list_movers_tool"
require_relative "schwab_mcp/tools/get_market_hours_tool"
require_relative "schwab_mcp/tools/get_price_history_tool"
require_relative "schwab_mcp/tools/get_account_names_tool"
require_relative "schwab_mcp/loggable"
require_relative "schwab_mcp/schwab_client_factory"


module SchwabMCP
  class Error < StandardError; end

  TOOLS = [
    Tools::QuoteTool,
    Tools::QuotesTool,
    Tools::OptionChainTool,
    Tools::HelpTool,
    Tools::SchwabAccountDetailsTool,
    Tools::ListAccountOrdersTool,
    Tools::ListAccountTransactionsTool,
    Tools::GetOrderTool,
    Tools::CancelOrderTool,
    Tools::PreviewOrderTool,
    Tools::PlaceOrderTool,
    Tools::ReplaceOrderTool,
    Tools::ListMoversTool,
    Tools::GetMarketHoursTool,
    Tools::GetPriceHistoryTool,
    Tools::GetAccountNamesTool
  ].freeze

  class Server
    include Loggable

    def initialize
      configure_schwab_rb

      @server = MCP::Server.new(
        name: "schwab_mcp_server",
        version: SchwabMCP::VERSION,
        tools: TOOLS,
        server_context: { user: "foobar" }
      )
    end

    def start
      configure_mcp
      log_info("Starting Schwab MCP Server #{SchwabMCP::VERSION}")
      log_info("Available tools: #{TOOLS.map { |tool| tool.name.split('::').last }.join(', ')}")
      log_info("Logs will be written to: #{log_file_path}")
      transport = MCP::Transports::StdioTransport.new(@server)
      transport.open
    end

    private

    def configure_schwab_rb
      SchwabRb.configure do |config|
        config.schwab_home = ENV['SCHWAB_HOME']
        config.logger = SchwabMCP::Logger.instance
        config.log_level = ENV.fetch('LOG_LEVEL', 'INFO').upcase
      end

      log_info("Configured schwab_rb to use shared logger")
    end

    def log_file_path
      if ENV['LOGFILE'] && !ENV['LOGFILE'].empty?
        ENV['LOGFILE']
      else
        File.join(Dir.tmpdir, 'schwab_mcp.log')
      end
    end

    def configure_mcp
      MCP.configure do |config|
        config.exception_reporter = ->(exception, server_context) do
          log_error("MCP Error: #{exception.class.name} - #{exception.message}")
          log_debug(exception.backtrace.first(3).join("\n"))
        end

        config.instrumentation_callback = ->(data) do
          duration = data[:duration] ? " - #{data[:duration].round(3)}s" : ""
          log_debug("MCP: #{data[:method]}#{data[:tool_name] ? " (#{data[:tool_name]})" : ""}#{duration}")
        end
      end
    end
  end
end
