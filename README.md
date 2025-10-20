# SchwabMCP

A Model Context Protocol (MCP) server that provides AI assistants like Claude with secure access to Schwab's trading API. This gem enables natural language interactions with your Schwab brokerage account for retrieving market data, quotes, option chains, account information, and managing trades.

This gem is built on top of the [schwab_rb](https://github.com/jwplatta/schwab_rb) Ruby gem, which provides the underlying Schwab API client functionality.

## Installation

Add this gem to your application's Gemfile:

```bash
bundle add schwab_mcp
```

Or install it directly:

```bash
gem install schwab_mcp
```

### Prerequisites

Before using this gem, you'll need:

1. A Schwab Developer account and API credentials
2. Environment variables configured (see Usage section)
3. Valid Schwab API tokens

**Dependencies:**
- This gem depends on [schwab_rb](https://github.com/jwplatta/schwab_rb) for Schwab API communication
- Ruby 3.1.0 or higher

## Usage

### Environment Setup

Create a `.env` file in your project root with the following required variables:

```bash
SCHWAB_API_KEY=your_schwab_api_key
SCHWAB_APP_SECRET=your_schwab_app_secret
SCHWAB_CALLBACK_URI=your_callback_uri
SCHWAB_TOKEN_PATH=path/to/your/token.json
```

### Running the MCP Server

Start the server using the provided executable:

```bash
bundle exec exe/schwab_mcp
```

### Token Management

The gem includes utility scripts for managing Schwab API authentication tokens:

#### Refresh Tokens

To refresh your existing authentication tokens:

```bash
bundle exec exe/schwab_token_refresh
```

This script will automatically refresh your tokens using the existing token file specified in your `TOKEN_PATH` environment variable.

#### Reset Tokens

To delete existing tokens and start the authentication process fresh:

```bash
bundle exec exe/schwab_token_reset
```

This script will:
1. Delete your existing token file
2. Guide you through the OAuth authentication flow to obtain new tokens

### Available Tools

The MCP server provides the following tools for AI assistants:

- **Market Data**: Get quotes, option chains, price history, and market hours
- **Account Management**: View account details, balances, and positions
- **Order Management**: Preview, place, cancel, and replace orders
- **Transaction History**: Retrieve account transactions and order history
- **Market Analysis**: Find option strategies and view market movers

### Integration with Claude Desktop

Configure Claude Desktop to use this MCP server by adding it to your `claude_desktop_config.json`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

### Setting up for Development

1. Clone the repository
2. Run `bundle install` to install dependencies
3. Copy `.env.example` to `.env` and configure your Schwab API credentials
4. Run tests with `bundle exec rspec`
5. Start the development server with `bundle exec exe/schwab_mcp`

### Testing

Run the test suite:

```bash
bundle exec rspec
```

### Code Quality

The project uses RuboCop for code style enforcement:

```bash
bundle exec rubocop
```

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jwplatta/schwab_mcp. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jwplatta/schwab_mcp/blob/master/CODE_OF_CONDUCT.md).

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b my-new-feature`)
3. Make your changes and add tests
4. Ensure all tests pass (`bundle exec rspec`)
5. Run RuboCop to check code style (`bundle exec rubocop`)
6. Commit your changes (`git commit -am 'Add some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create a new Pull Request

Please ensure your contributions:
- Include appropriate tests
- Follow the existing code style
- Update documentation as needed
- Respect the security considerations for financial API integration

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the SchwabMcp project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/schwab_mcp/blob/master/CODE_OF_CONDUCT.md).
