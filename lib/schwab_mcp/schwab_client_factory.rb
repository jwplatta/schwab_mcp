# frozen_string_literal: true

require_relative "loggable"

module SchwabMCP
  module SchwabClientFactory
    extend Loggable

    def self.create_client
      begin
        log_debug("Initializing Schwab client")
        client = SchwabRb::Auth.init_client_easy(
          ENV['SCHWAB_API_KEY'],
          ENV['SCHWAB_APP_SECRET'],
          ENV['SCHWAB_CALLBACK_URI'],
          ENV['TOKEN_PATH']
        )

        unless client
          log_error("Failed to initialize Schwab client - check credentials")
          return nil
        end

        log_debug("Schwab client initialized successfully")
        client
      rescue => e
        log_error("Error initializing Schwab client: #{e.message}")
        log_debug("Backtrace: #{e.backtrace.first(3).join('\n')}")
        nil
      end
    end

    def self.cached_client
      @client ||= create_client
    end

    def self.client_error_response
      MCP::Tool::Response.new([{
        type: "text",
        text: "**Error**: Failed to initialize Schwab client. Check your credentials."
      }])
    end
  end
end