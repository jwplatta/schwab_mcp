#!/usr/bin/env ruby

# Test script to debug environment variables and client initialization

puts "=== Environment Variables ==="
puts "SCHWAB_API_KEY: #{ENV['SCHWAB_API_KEY'] ? '[SET]' : '[NOT SET]'}"
puts "SCHWAB_APP_SECRET: #{ENV['SCHWAB_APP_SECRET'] ? '[SET]' : '[NOT SET]'}"
puts "APP_CALLBACK_URL: #{ENV['APP_CALLBACK_URL'] ? '[SET]' : '[NOT SET]'}"
puts "TOKEN_PATH: #{ENV['TOKEN_PATH'] ? '[SET]' : '[NOT SET]'}"

puts "\n=== Testing Token File ==="
token_path = ENV['TOKEN_PATH'] || './token.json'
puts "Checking token file at: #{token_path}"
puts "Token file exists: #{File.exist?(token_path)}"

if File.exist?(token_path)
  begin
    content = File.read(token_path)
    require 'json'
    data = JSON.parse(content)
    puts "Token file valid JSON: true"
    puts "Token has access_token: #{data.dig('token', 'access_token') ? '[YES]' : '[NO]'}"
    puts "Token has refresh_token: #{data.dig('token', 'refresh_token') ? '[YES]' : '[NO]'}"
  rescue => e
    puts "Token file JSON error: #{e.message}"
  end
end

puts "\n=== Testing Client Initialization ==="
begin
  require 'schwab_rb'
  require_relative 'lib/schwab_mcp/schwab_client_factory'

  client = SchwabMCP::SchwabClientFactory.create_client

  if client
    puts "Client initialized: SUCCESS"
    puts "Client class: #{client.class}"
  else
    puts "Client initialized: FAILED (nil returned)"
  end
rescue => e
  puts "Client initialization error: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
end
