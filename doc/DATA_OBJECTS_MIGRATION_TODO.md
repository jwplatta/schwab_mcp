# SchwabMCP Data Objects Migration TODO

## Overview
Update all tools in `lib/schwab_mcp/tools/` to use data objects from schwab_rb instead of parsing JSON responses directly.

## Migration Date
July 21, 2025

**Progress: 7/17 tools completed**

## Tools to Update

### ✅ Account-related Tools
- [x] **schwab_account_details_tool.rb** - ✅ COMPLETED - Updated to use Account and AccountNumbers data objects
- [x] **list_schwab_accounts_tool.rb** - ✅ COMPLETED - Updated to use AccountNumbers data object

### ✅ Order-related Tools
- [x] **list_account_orders_tool.rb** - ✅ COMPLETED - Updated to use Order and AccountNumbers data objects
- [x] **get_order_tool.rb** - ✅ COMPLETED - Updated to use Order data object
- [x] **cancel_order_tool.rb** - ✅ COMPLETED - Updated to use Order data object
- [x] **preview_order_tool.rb** - ✅ COMPLETED - Updated to use OrderPreview data object
- [x] **place_order_tool.rb** - ✅ COMPLETED - Updated to use AccountNumbers data object for account resolution
- [ ] **replace_order_tool.rb** - Update to use Order data object (if applicable)

### ✅ Market Data Tools
- [ ] **quote_tool.rb** - Update to use Quote data object
- [ ] **quotes_tool.rb** - Update to use Quote data objects
- [ ] **option_chain_tool.rb** - Update to use OptionChain data object
- [ ] **list_movers_tool.rb** - Update to use appropriate data object (if available)
- [ ] **get_market_hours_tool.rb** - Update to use MarketHours data object
- [ ] **get_price_history_tool.rb** - Update to use PriceHistory data object

### ✅ Transaction Tools
- [ ] **list_account_transactions_tool.rb** - Update to use Transaction data objects

### ✅ Strategy Tools
- [ ] **option_strategy_finder_tool.rb** - Update to use OptionChain and related data objects

### ✅ Utility Tools
- [ ] **help_tool.rb** - No changes needed (utility tool)

## Total Tools Found: 17

## Migration Steps for Each Tool

1. **Remove JSON parsing logic** - Delete manual hash key access
2. **Use data object attributes** - Access data via object methods/attributes
3. **Update error handling** - Ensure proper handling of data object responses
4. **Write minimal unit tests** - Verify tool works with data objects
5. **Test functionality** - Manual testing if needed
6. **Clean commit** - Make focused commit for each tool

## Data Object Mappings

Based on the schwab_rb data objects available:

- **Account data** → `SchwabRb::DataObjects::Account`
- **Account numbers** → `SchwabRb::DataObjects::AccountNumbers`
- **Orders** → `SchwabRb::DataObjects::Order`
- **Order preview** → `SchwabRb::DataObjects::OrderPreview`
- **Quotes** → `SchwabRb::DataObjects::Quote`
- **Option chains** → `SchwabRb::DataObjects::OptionChain`
- **Transactions** → `SchwabRb::DataObjects::Transaction`
- **Positions** → `SchwabRb::DataObjects::Position`
- **Market hours** → `SchwabRb::DataObjects::MarketHours` (if available)
- **Price history** → `SchwabRb::DataObjects::PriceHistory` (if available)

## Notes

- All schwab_rb client methods now default to `return_data_objects: true`
- Maintain backward compatibility where possible
- Focus on cleaner, more maintainable code
- Each tool update should be a separate, focused commit
- Write minimal unit tests for each tool to prevent regressions

## Progress Tracking

- **Total tools to update**: 16 (excluding help_tool.rb)
- **Tools completed**: 5
- **Tools remaining**: 11
