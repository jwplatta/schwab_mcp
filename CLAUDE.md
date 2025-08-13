# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Testing
- Run all tests: `bundle exec rspec`
- Run specific test: `bundle exec rspec spec/tools/specific_tool_spec.rb`
- NEVER use `-v` flag with RSpec - it clutters output unnecessarily
- Reference @.github/instructions/ruby-testing.instructions.md when writing unit tests

### Code Quality
- Run RuboCop linter: `bundle exec rubocop`
- Default rake task (tests + linting): `rake`

### Server Operations
- Start MCP server: `bundle exec exe/schwab_mcp`
- Alternative server start: `./start_mcp_server.sh`
- Token refresh: `bundle exec exe/schwab_token_refresh`
- Token reset: `bundle exec exe/schwab_token_reset`

### Development Setup
- Initial setup: `bin/setup`
- Install dependencies: `bundle install`
- Interactive console: `bin/console`

## Architecture Overview

### Core Structure
This is a Ruby gem providing a Model Context Protocol (MCP) server for Schwab brokerage API integration. The architecture follows these key patterns:

- **MCP Tools Pattern**: All functionality is exposed through MCP tools extending `MCP::Tool`
- **Data Objects Migration**: Currently migrating from JSON parsing to schwab_rb data objects (see `doc/DATA_OBJECTS_MIGRATION_TODO.md`)
- **Shared Logging**: Uses singleton logger pattern with `Loggable` module across all components

### Key Components
- `lib/schwab_mcp.rb` - Main server class and tool registration
- `lib/schwab_mcp/tools/` - All MCP tools (17 tools total)
- `lib/schwab_mcp/orders/` - Order construction utilities (Iron Condor, Vertical spreads)
- `lib/schwab_mcp/loggable.rb` - Shared logging functionality
- `lib/schwab_mcp/redactor.rb` - Sensitive data redaction for logs

### Tool Categories
- **Account Tools**: `schwab_account_details_tool`, `list_schwab_accounts_tool`
- **Order Tools**: `list_account_orders_tool`, `get_order_tool`, `cancel_order_tool`, `preview_order_tool`, `place_order_tool`, `replace_order_tool`
- **Market Data Tools**: `quote_tool`, `quotes_tool`, `option_chain_tool`, `list_movers_tool`, `get_market_hours_tool`, `get_price_history_tool`
- **Transaction Tools**: `list_account_transactions_tool`
- **Utility Tools**: `help_tool`

## Data Objects Migration

**CRITICAL**: This codebase is currently migrating from manual JSON parsing to schwab_rb data objects. Progress is tracked in `doc/DATA_OBJECTS_MIGRATION_TODO.md` (6/17 tools completed as of July 2025).

### Migration Pattern
When working on tools, follow this pattern:
1. Replace `JSON.parse(response.body)` with direct data object usage
2. Change hash access `data['key']` to object methods `object.key`
3. Remove `JSON::ParserError` rescue blocks
4. Update formatting to use data object attributes
5. Write comprehensive RSpec tests with proper mocking

### Completed Migrations
Tools using data objects (safe to follow as examples):
- `schwab_account_details_tool.rb` - Uses `Account` and `AccountNumbers`
- `list_schwab_accounts_tool.rb` - Uses `AccountNumbers`
- `list_account_orders_tool.rb` - Uses `Order` and `AccountNumbers`
- `get_order_tool.rb` - Uses `Order`
- `cancel_order_tool.rb` - Uses `Order`
- `preview_order_tool.rb` - Uses `OrderPreview`

## Development Conventions

### Ruby Style
- Use `frozen_string_literal: true` in all files
- Follow snake_case/PascalCase conventions
- Use `require_relative` for local dependencies
- Prefer keyword arguments for multi-parameter methods
- Always use descriptive variable names

### Tool Development
- All tools extend `MCP::Tool` and include `Loggable`
- Use proper JSON Schema validation in `input_schema`
- Return `MCP::Tool::Response` objects with structured content
- Include descriptive annotations (title, read_only_hint, etc.)

### Testing Strategy
- Mock environment variables globally in `spec/spec_helper.rb`
- Test both success and error scenarios
- Mock schwab_rb client and data objects appropriately
- File naming: `*_spec.rb` for corresponding `*.rb`

### Environment Variables
Required for operation:
- `SCHWAB_API_KEY`, `SCHWAB_APP_SECRET`, `SCHWAB_CALLBACK_URI`, `TOKEN_PATH`
- Account mappings: `*_ACCOUNT` (e.g., `TRADING_BROKERAGE_ACCOUNT`)
- Optional: `LOG_LEVEL`, `LOGFILE`

### Git Workflow
- Stage specific files, never use `git add .`
- Write descriptive commits with progress tracking
- Include 1-3 bullet points for detailed changes
- Commit only relevant files, exclude temporary/log files

## Dependencies

### Core Dependencies
- `schwab_rb` - Schwab API client with data objects (prefer `return_data_objects: true`)
- `mcp` - Model Context Protocol framework
- `rspec` - Testing framework
- `rubocop` - Code style enforcement

### External Integrations
- Schwab Trading API for all brokerage operations
- OAuth token management for authentication
- MCP protocol for AI assistant integration

## Important Notes

- **Security**: Never commit real credentials or account numbers
- **Logging**: Use `Redactor` class for sensitive data in debug output
- **Data Objects**: Always prefer schwab_rb data objects over JSON parsing
- **Testing**: All tests must pass before committing changes
- **Tool Design**: Tools should be read-only unless explicitly destructive