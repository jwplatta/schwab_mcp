#!/usr/bin/env ruby
# Test script to verify the Schwab MCP server works

require_relative 'lib/schwab_mcp'

begin
  puts "🧪 Testing Schwab MCP Server..."

  # Test server initialization
  server = SchwabMCP::Server.new
  puts "✅ Server initialized successfully"

  # Test transport creation (without starting)
  transport = MCP::Transports::StdioTransport.new(server.instance_variable_get(:@server))
  puts "✅ Transport created successfully"

  puts "All basic components working!"
  puts "The server is ready to start with: server.start"

rescue => e
  puts "Error: #{e.class.name} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
