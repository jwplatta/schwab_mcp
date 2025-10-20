# frozen_string_literal: true

require "mcp"
require_relative "../loggable"
require "schwab_rb"

module SchwabMCP
  module Tools
    class GetAccountNamesTool < MCP::Tool
      extend Loggable
      description "Get a list of configured Schwab account names"

      input_schema(
        properties: {
          topic: {
            type: "string",
            description: "Asking about a specific topic related to account names (optional)"
          }
        },
        required: []
      )

      annotations(
        title: "Get Account Names",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true
      )

      def self.call(topic: nil, server_context:)
        account_names = SchwabRb::AccountHashManager.new.available_account_names
        acct_names_content = if account_names && !account_names.empty?
          formatted_names = account_names.map { |name| "- #{name}" }.join("\n")
          "Configured Schwab Account Names:\n\n#{formatted_names}"
        else
          <<~NO_ACCOUNTS
            No Schwab Account Names Configured

            You need to configure your Schwab account names in the account_names.json file.

            This file should be located in your schwab_home directory (typically ~/.schwab_rb/).

            For detailed setup instructions, please refer to:
            https://github.com/jwplatta/schwab_rb/blob/main/doc/ACCOUNT_MANAGEMENT.md

            The account_names.json file should map friendly names to your Schwab account hashes.
          NO_ACCOUNTS
        end

        MCP::Tool::Response.new([{
          type: "text",
          text: acct_names_content
        }])
      end

    end
  end
end
