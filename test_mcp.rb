require "mcp"
require "mcp/transports/stdio"

puts "Testing MCP Server and StdioTransport..."

server = MCP::Server.new(name: "my_server")
puts "✅ Server created successfully"

transport = MCP::Transports::StdioTransport.new(server)
puts "✅ StdioTransport created successfully"

# Test tool definition
server.define_tool(name: "test_tool") { |**args| { result: "Tool works!" } }
puts "✅ Tool defined successfully"

puts "🎉 All components working!"
