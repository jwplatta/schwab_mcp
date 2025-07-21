# frozen_string_literal: true

require "schwab_mcp"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Global setup for ENV mocking - reduces duplication across test files
  config.before(:each) do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SCHWAB_API_KEY").and_return("test_api_key")
    allow(ENV).to receive(:[]).with("SCHWAB_APP_SECRET").and_return("test_app_secret")
    allow(ENV).to receive(:[]).with("SCHWAB_CALLBACK_URI").and_return("https://test.callback.com")
    allow(ENV).to receive(:[]).with("TOKEN_PATH").and_return("/tmp/test_token.json")
    allow(ENV).to receive(:[]).with("LOGFILE").and_return(nil)
    allow(ENV).to receive(:[]).with("LOG_LEVEL").and_return("INFO")
    allow(ENV).to receive(:[]).with("TMPDIR").and_return("/tmp")
  end
end
