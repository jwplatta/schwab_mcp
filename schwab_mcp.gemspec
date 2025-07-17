# frozen_string_literal: true

require_relative "lib/schwab_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "schwab_mcp"
  spec.version = SchwabMCP::VERSION
  spec.authors = ["Joseph Platta"]
  spec.email = ["jwplatta@gmail.com"]

  spec.summary = "MCP server for Schwab API integration"
  spec.description = "A Model Context Protocol server that provides Claude with access to Schwab trading API for quotes and market data"
  spec.homepage = "https://github.com/jwplatta/schwab_mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  # Comment out to allow pushing to RubyGems.org
  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jwplatta/schwab_mcp"
  spec.metadata["changelog_uri"] = "https://github.com/jwplatta/schwab_mcp/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_uri"] = "https://rubygems.org/gems/schwab_mcp"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/schwab_mcp"
  spec.metadata["bug_tracker_uri"] = "https://github.com/jwplatta/schwab_mcp/issues"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "mcp"
  spec.add_dependency "schwab_rb"
end
