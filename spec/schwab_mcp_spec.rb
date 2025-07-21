# frozen_string_literal: true

RSpec.describe SchwabMCP do
  it "has a version number" do
    expect(SchwabMCP::VERSION).not_to be nil
  end

  it "loads successfully" do
    expect { SchwabMCP::Server.new }.not_to raise_error
  end

  # TODO: Re-enable when prompts are implemented
  # it "loads successfully with prompts" do
  #   expect { SchwabMCP::Server.new }.not_to raise_error
  #   expect(SchwabMCP::Prompts::FormatMarkdownTable).to be_a(Class)
  #   expect(SchwabMCP::Prompts::FormatMarkdownTable.name_value).to eq("format_markdown_table")
  # end
end
