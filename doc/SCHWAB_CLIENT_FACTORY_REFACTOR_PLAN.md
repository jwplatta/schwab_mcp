# Schwab Client Factory Refactor Plan

## Problem Statement

Every tool in the schwab_mcp codebase has identical client initialization code repeated 17 times across the project:

```ruby
client = SchwabRb::Auth.init_client_easy(
  ENV['SCHWAB_API_KEY'],
  ENV['SCHWAB_APP_SECRET'], 
  ENV['SCHWAB_CALLBACK_URI'],
  ENV['TOKEN_PATH']
)

unless client
  log_error("Failed to initialize Schwab client")
  return MCP::Tool::Response.new([{
    type: "text",
    text: "**Error**: Failed to initialize Schwab client. Check your credentials."
  }])
end
```

**Files affected (18 total):**
- All 17 tools in `lib/schwab_mcp/tools/`
- `exe/schwab_token_refresh`
- `debug_env.rb`

This creates ~170 lines of duplicated code and makes maintenance difficult.

## Proposed Solution: SchwabClientFactory Module

### Design Goals
1. **Centralize client creation** - Single location for all client initialization logic
2. **Handle error scenarios** - Consistent error handling and logging across tools
3. **Support caching** - Optional client caching to avoid repeated auth calls
4. **Integrate with existing patterns** - Uses existing `Loggable` module
5. **Maintain compatibility** - Drop-in replacement requiring minimal tool changes

### Implementation

#### Step 1: Create SchwabClientFactory Module

**File**: `lib/schwab_mcp/schwab_client_factory.rb`

```ruby
# frozen_string_literal: true

require_relative "loggable"

module SchwabMCP
  module SchwabClientFactory
    extend Loggable

    # Creates a new Schwab client with standard error handling
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

    # Optional: Cached client for performance (use with caution for token expiry)
    def self.cached_client
      @client ||= create_client
    end

    # Helper method for consistent error responses
    def self.client_error_response
      MCP::Tool::Response.new([{
        type: "text",
        text: "**Error**: Failed to initialize Schwab client. Check your credentials."
      }])
    end
  end
end
```

#### Step 2: Update Main Module

Add to `lib/schwab_mcp.rb`:
```ruby
require_relative "schwab_mcp/schwab_client_factory"
```

#### Step 3: Refactor Tool Pattern

**Before (10+ lines per tool):**
```ruby
begin
  client = SchwabRb::Auth.init_client_easy(
    ENV['SCHWAB_API_KEY'],
    ENV['SCHWAB_APP_SECRET'],
    ENV['SCHWAB_CALLBACK_URI'],
    ENV['TOKEN_PATH']
  )

  unless client
    log_error("Failed to initialize Schwab client")
    return MCP::Tool::Response.new([{
      type: "text",
      text: "**Error**: Failed to initialize Schwab client. Check your credentials."
    }])
  end

  # tool logic here...
end
```

**After (3 lines per tool):**
```ruby
client = SchwabClientFactory.create_client
return SchwabClientFactory.client_error_response unless client

# tool logic here...
```

#### Step 4: Update Tool Imports

Add to each tool file:
```ruby
require_relative "../schwab_client_factory"
```

### Migration Strategy

1. **Create the factory module** first
2. **Update one tool** as a proof of concept 
3. **Test thoroughly** to ensure no regression
4. **Batch update remaining tools** (can be done efficiently with MultiEdit)
5. **Update executable files** (`exe/schwab_token_refresh`, `debug_env.rb`)
6. **Remove old client initialization code**

### Benefits

1. **Code Reduction**: ~170 lines of duplicated code → 1 centralized module
2. **Consistent Error Handling**: All tools handle auth failures identically
3. **Easier Maintenance**: Auth logic changes in one place
4. **Better Testing**: Mock client creation in one place
5. **Performance Options**: Can add client caching if needed
6. **Future Extensibility**: Easy to add retry logic, connection pooling, etc.

### Risks and Considerations

1. **Token Caching**: Cached clients may hold expired tokens - use with caution
2. **Environment Variables**: Factory assumes same env vars for all tools (currently true)
3. **Error Handling**: Must ensure all tools properly check for nil client response
4. **Testing**: All tool tests will need to mock `SchwabClientFactory.create_client`

### Testing Strategy

1. **Unit tests** for SchwabClientFactory module
2. **Integration tests** to ensure tools still work correctly
3. **Mock the factory** in existing tool tests rather than individual client creation
4. **Verify error scenarios** are handled consistently

### Files to Modify

**New files:**
- `lib/schwab_mcp/schwab_client_factory.rb`

**Modified files:**
- `lib/schwab_mcp.rb` (add require)
- All 17 tool files in `lib/schwab_mcp/tools/`
- `exe/schwab_token_refresh`
- `debug_env.rb`

**Total impact:** 20 files modified, ~150 lines of code removed, 1 new module added

This refactor will significantly improve code maintainability while preserving all existing functionality.