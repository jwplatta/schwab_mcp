---
apply: ****
---

# GitHub Copilot Instructions for SchwabMCP

## Project Overview
This is a Ruby gem that provides a Model Context Protocol (MCP) server for Schwab brokerage API integration. The project uses:
- Ruby with RSpec for testing
- The `schwab_rb` gem for Schwab API interactions with data objects
- MCP (Model Context Protocol) framework for tool definitions

## Development Patterns & Conventions

### Ruby Style & Conventions
- Follow standard Ruby conventions: snake_case for methods/variables, PascalCase for classes
- Use `attr_reader` for read-only attributes
- Prefer keyword arguments for method signatures with multiple parameters
- Use `require_relative` for local file dependencies
- Follow Ruby's principle of least surprise in API design
- Use `frozen_string_literal: true` in all Ruby files

### Testing with RSpec
- **Always run tests without the `-v` option**: Use `bundle exec rspec` or `bundle exec rspec spec/specific_test.rb`
- The `-v` verbose option is unnecessary and clutters output
- All tests should pass before committing changes
- Mock environment variables in `spec/spec_helper.rb` globally rather than in individual test files
- Test file naming: `*_spec.rb` for the corresponding `*.rb` file

### Git Commit Practices
- **Commit only relevant files** - Don't include unrelated changes or temporary files
- Use descriptive and concise commit messages with:
  - Clear subject line describing the change
  - 1-3 bullet points for detailed changes
  - Progress tracking (e.g., "Third tool in data objects migration - 14 remaining")
- Stage specific files using `git add filename1 filename2`. Never use `git add .`

### Data Objects Migration Patterns
When migrating tools from JSON parsing to data objects:

1. **Replace JSON parsing**: Change from `JSON.parse(response.body)` to direct data object usage
2. **Update attribute access**: Change from hash access `data['key']` to object methods `object.key`
3. **Remove JSON error handling**: Remove `JSON::ParserError` rescue blocks
4. **Update formatting methods**: Ensure they use data object attributes
5. **Create comprehensive tests**: Include mocks for all data objects and their methods
6. **Follow existing patterns**: Look at completed migrations like `list_schwab_accounts_tool`

### Tool Development Guidelines
- All tools should extend `MCP::Tool`
- Include `Loggable` module for consistent logging
- Use proper input schema validation with JSON Schema
- Provide clear error messages for user-facing errors
- Include both success and error response handling
- Use the `Redactor` class for sensitive data in debug output

### Environment Variable Management
- Store account mappings and credentials in environment variables
- Use descriptive names ending with `_ACCOUNT` for account identifiers
- Mock all required environment variables in `spec/spec_helper.rb`
- Never commit real credentials or account numbers

### Code Organization
- Keep related functionality in modules under `SchwabMCP::`
- Use `private` methods for internal implementation details
- Group related tools logically (Account tools, Order tools, Market data tools)
- Maintain the existing directory structure: `lib/schwab_mcp/tools/`

### Error Handling Patterns
- Use specific error messages that help users understand what went wrong
- Include suggestions for fixing configuration issues
- Log errors with appropriate levels (error, warn, info, debug)
- Return `MCP::Tool::Response` objects with structured content

### Documentation Standards
- Write and update TODO documents to the /doc directory
- Maintain clear progress tracking in all TODO files
- Include usage examples in tool descriptions

## Key Dependencies
- `schwab_rb` - Schwab API client with data objects (prefer `return_data_objects: true`)
- `mcp` - Model Context Protocol framework
- `rspec` - Testing framework
- Standard Ruby libraries: `json`, `date`, `logger`

## Testing Strategy
- Unit tests for all tools using RSpec
- Mock external dependencies (Schwab API, environment variables)
- Test both success and error scenarios
- Validate tool responses and formatting
- Ensure all tests pass before committing

Follow these patterns to maintain consistency and quality across the codebase.
