# frozen_string_literal: true

require "mcp"
require "mcp/transports/stdio"
require_relative "schwab_mcp/version"
require_relative "schwab_mcp/tools/quote_tool"
require_relative "schwab_mcp/loggable"


module SchwabMCP
  class Error < StandardError; end

  class Server
    include Loggable

    def initialize
      @server = MCP::Server.new(
        name: "schwab_mcp_server",
        version: SchwabMCP::VERSION,
        tools: [
          Tools::QuoteTool
        ]
      )
    end

    def start
      configure_mcp
      log_info("🚀 Starting Schwab MCP Server #{SchwabMCP::VERSION}")
      log_info("📊 Available tools: QuoteTool")
      transport = MCP::Transports::StdioTransport.new(@server)
      transport.open
    end

    private

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
