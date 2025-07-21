# frozen_string_literal: true

require "date"
require "spec_helper"
require_relative "../lib/schwab_mcp/option_chain_filter"

RSpec.describe SchwabMCP::OptionChainFilter do
  let(:expiration_date) { Date.new(2025, 1, 17) }
  let(:underlying_price) { 5800.0 }

  let(:filter) do
    described_class.new(
      expiration_date: expiration_date,
      underlying_price: underlying_price,
      max_delta: 0.15,
      max_spread: 20.0,
      min_credit: 100.0,
      min_open_interest: 10,
      dist_from_strike: 0.05
    )
  end

  describe "#initialize" do
    it "creates a filter with the given parameters" do
      expect(filter.expiration_date).to eq(expiration_date)
      expect(filter.underlying_price).to eq(underlying_price)
      expect(filter.max_delta).to eq(0.15)
      expect(filter.max_spread).to eq(20.0)
      expect(filter.min_credit).to eq(100.0)
      expect(filter.min_open_interest).to eq(10)
      expect(filter.dist_from_strike).to eq(0.05)
    end
  end

  describe "#passes_short_option_filters?" do
    let(:base_option) do
      {
        delta: -0.10,
        openInterest: 50,
        strikePrice: 5500.0,
        mark: 5.50
      }
    end

    context "with valid option parameters" do
      it "returns true for an option that meets all criteria" do
        expect(filter.passes_short_option_filters?(base_option)).to be true
      end
    end

    context "with invalid delta" do
      it "returns false when delta is too high (absolute value)" do
        high_delta_option = base_option.merge(delta: -0.25)
        expect(filter.passes_short_option_filters?(high_delta_option)).to be false
      end

      it "returns true for positive delta (delta filter only checks absolute value)" do
        positive_delta_option = base_option.merge(delta: 0.10)
        expect(filter.passes_short_option_filters?(positive_delta_option)).to be true
      end
    end

    context "with insufficient open interest" do
      it "returns false when open interest is below minimum" do
        low_oi_option = base_option.merge(openInterest: 5)
        expect(filter.passes_short_option_filters?(low_oi_option)).to be false
      end
    end

    context "with strike price too close to underlying" do
      it "returns false when strike is within distance threshold" do
        close_strike_option = base_option.merge(strikePrice: 5790.0)
        expect(filter.passes_short_option_filters?(close_strike_option)).to be false
      end

      it "returns true when strike is far enough from underlying" do
        far_strike_option = base_option.merge(strikePrice: 5500.0)
        expect(filter.passes_short_option_filters?(far_strike_option)).to be true
      end
    end
  end

  describe "#find_spreads" do
    let(:sample_options_array) do
      [
        double("Option",
               delta: -0.10,
               open_interest: 50,
               strike: 5500.0,
               mark: 5.50,
               symbol: "SPX250117P05500000",
               expiration_date: Date.new(2025, 1, 17),
               bid: 5.45,
               ask: 5.55,
               respond_to?: lambda { |method|
                 %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
               }),
        double("Option",
               delta: -0.08,
               open_interest: 30,
               strike: 5490.0,
               mark: 4.25,
               symbol: "SPX250117P05490000",
               expiration_date: Date.new(2025, 1, 17),
               bid: 5.45,
               ask: 5.55,
               respond_to?: lambda { |method|
                 %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
               }),
        double("Option",
               delta: -0.06,
               open_interest: 25,
               strike: 5480.0,
               mark: 3.75,
               symbol: "SPX250117P05480000",
               expiration_date: Date.new(2025, 1, 17),
               bid: 5.45,
               ask: 5.55,
               respond_to?: lambda { |method|
                 %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
               }),
        double("Option",
               delta: -0.04,
               open_interest: 15,
               strike: 5470.0,
               mark: 2.50,
               symbol: "SPX250117P05470000",
               expiration_date: Date.new(2025, 1, 17),
               bid: 5.45,
               ask: 5.55,
               respond_to?: lambda { |method|
                 %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
               })
      ]
    end

    context "with put spreads" do
      it "finds valid put spread combinations" do
        put_filter = described_class.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          max_delta: 0.15,
          max_spread: 20.0,
          min_credit: 1.0, # Lower minimum for testing
          min_open_interest: 10,
          dist_from_strike: 0.05
        )

        spreads = put_filter.find_spreads(sample_options_array, "put")

        expect(spreads).not_to be_empty
        expect(spreads.length).to be >= 1

        # Check first spread structure
        first_spread = spreads.first
        expect(first_spread).to have_key(:short_option)
        expect(first_spread).to have_key(:long_option)
        expect(first_spread).to have_key(:credit)
        expect(first_spread).to have_key(:spread_width)

        # Verify it's a proper put spread (short strike > long strike)
        expect(first_spread[:short_option][:strikePrice]).to be > first_spread[:long_option][:strikePrice]

        # Verify credit is positive
        expect(first_spread[:credit]).to be > 0
      end

      it "calculates correct credit for spreads" do
        # Create filter with lower min_credit for testing
        put_filter = described_class.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          max_delta: 0.15,
          max_spread: 20.0,
          min_credit: 1.0, # Lower minimum for testing
          min_open_interest: 10,
          dist_from_strike: 0.05
        )

        spreads = put_filter.find_spreads(sample_options_array, "put")

        # Find the 5500/5490 spread
        spread_5500_5490 = spreads.find do |spread|
          spread[:short_option][:strikePrice] == 5500.0 &&
            spread[:long_option][:strikePrice] == 5490.0
        end

        expect(spread_5500_5490).not_to be_nil
        expect(spread_5500_5490[:credit]).to eq(1.25) # 5.50 - 4.25
        expect(spread_5500_5490[:spread_width]).to eq(10.0) # 5500 - 5490
      end
    end

    context "with call spreads" do
      let(:call_options_array) do
        [
          double("Option",
                 delta: 0.10,
                 open_interest: 50,
                 strike: 6100.0,
                 mark: 5.50,
                 symbol: "SPX250117C06100000",
                 expiration_date: Date.new(2025, 1, 17),
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 }),
          double("Option",
                 delta: 0.08,
                 open_interest: 30,
                 strike: 6110.0,
                 mark: 4.25,
                 symbol: "SPX250117C06110000",
                 expiration_date: Date.new(2025, 1, 17),
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 }),
          double("Option",
                 delta: 0.06,
                 open_interest: 25,
                 strike: 6120.0,
                 mark: 3.75,
                 symbol: "SPX250117C06120000",
                 expiration_date: Date.new(2025, 1, 17),
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 })
        ]
      end

      it "finds valid call spread combinations" do
        # Create filter with lower min_credit and dist_from_strike for call spreads
        call_filter = described_class.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          max_delta: 0.15,
          max_spread: 20.0,
          min_credit: 1.0, # Lower minimum for call spread test
          min_open_interest: 10,
          dist_from_strike: 0.04 # Lower distance requirement
        )

        spreads = call_filter.find_spreads(call_options_array, "call")

        expect(spreads).not_to be_empty

        # Verify it's a proper call spread (short strike < long strike)
        first_spread = spreads.first
        expect(first_spread[:short_option][:strikePrice]).to be < first_spread[:long_option][:strikePrice]
      end
    end

    context "with no valid options" do
      let(:invalid_options_array) do
        [
          double("Option",
                 delta: -0.10,
                 open_interest: 5, # Too low open interest
                 strike: 5790.0, # Too close to underlying
                 mark: 5.50,
                 symbol: "SPX250117P05790000",
                 expiration_date: Date.new(2025, 1, 17),
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 })
        ]
      end

      it "returns empty array when no options pass filters" do
        spreads = filter.find_spreads(invalid_options_array, "put")
        expect(spreads).to be_empty
      end
    end
  end

  describe "filtering behavior" do
    context "delta filtering" do
      it "accepts options with delta within threshold" do
        valid_option = { delta: 0.10, openInterest: 50, strikePrice: 5500.0, mark: 5.50 }
        expect(filter.passes_short_option_filters?(valid_option)).to be true
      end

      it "rejects options with delta exceeding threshold" do
        high_delta_option = { delta: 0.20, openInterest: 50, strikePrice: 5500.0, mark: 5.50 }
        expect(filter.passes_short_option_filters?(high_delta_option)).to be false
      end

      it "handles negative delta correctly" do
        negative_delta_option = { delta: -0.10, openInterest: 50, strikePrice: 5500.0, mark: 5.50 }
        expect(filter.passes_short_option_filters?(negative_delta_option)).to be true
      end
    end

    context "minimum credit filtering" do
      let(:high_credit_filter) do
        described_class.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          max_delta: 0.15,
          max_spread: 20.0,
          min_credit: 200.0, # High minimum credit
          min_open_interest: 10,
          dist_from_strike: 0.05
        )
      end

      it "accepts spreads that meet minimum credit requirement" do
        short_option = { mark: 6.00, strikePrice: 5500.0, delta: -0.10 }
        long_option = { mark: 4.00, strikePrice: 5490.0, delta: -0.08 }

        expect(high_credit_filter.send(:passes_min_credit?, short_option, long_option)).to be true
      end

      it "rejects spreads below minimum credit requirement" do
        short_option = { mark: 5.50, strikePrice: 5500.0, delta: -0.10 }
        long_option = { mark: 4.25, strikePrice: 5490.0, delta: -0.08 }

        expect(high_credit_filter.send(:passes_min_credit?, short_option, long_option)).to be false
      end

      it "allows all spreads when min_credit is 0" do
        zero_credit_filter = described_class.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          max_delta: 0.15,
          max_spread: 20.0,
          min_credit: 0.0,
          min_open_interest: 10,
          dist_from_strike: 0.05
        )

        short_option = { mark: 1.00, strikePrice: 5500.0, delta: -0.10 }
        long_option = { mark: 0.90, strikePrice: 5490.0, delta: -0.08 }

        expect(zero_credit_filter.send(:passes_min_credit?, short_option, long_option)).to be true
      end
    end

    context "date matching" do
      it "finds spreads for matching expiration dates" do
        matching_options = [
          double("Option",
                 delta: -0.10,
                 open_interest: 50,
                 strike: 5500.0,
                 mark: 5.50,
                 symbol: "SPX250117P05500000",
                 expiration_date: Date.new(2025, 1, 17),
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 }),
          double("Option",
                 delta: -0.08,
                 open_interest: 30,
                 strike: 5490.0,
                 mark: 4.25,
                 symbol: "SPX250117P05490000",
                 expiration_date: Date.new(2025, 1, 17),
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 })
        ]

        test_filter = described_class.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          max_delta: 0.15,
          max_spread: 20.0,
          min_credit: 1.0,
          min_open_interest: 10,
          dist_from_strike: 0.05
        )

        spreads = test_filter.find_spreads(matching_options, "put")
        expect(spreads).not_to be_empty
      end

      it "ignores options with non-matching expiration dates" do
        non_matching_options = [
          double("Option",
                 delta: -0.10,
                 open_interest: 50,
                 strike: 5500.0,
                 mark: 5.50,
                 symbol: "SPX250124P05500000",
                 expiration_date: Date.new(2025, 1, 24), # Different date
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 }),
          double("Option",
                 delta: -0.08,
                 open_interest: 30,
                 strike: 5490.0,
                 mark: 4.25,
                 symbol: "SPX250124P05490000",
                 expiration_date: Date.new(2025, 1, 24), # Different date
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 })
        ]

        spreads = filter.find_spreads(non_matching_options, "put")
        expect(spreads).to be_empty
      end

      it "filters options by expiration date correctly" do
        mixed_date_options = [
          double("Option",
                 delta: -0.10,
                 open_interest: 50,
                 strike: 5500.0,
                 mark: 5.50,
                 symbol: "SPX250117P05500000",
                 expiration_date: Date.new(2025, 1, 17), # Matching date
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 }),
          double("Option",
                 delta: -0.08,
                 open_interest: 30,
                 strike: 5490.0,
                 mark: 4.25,
                 symbol: "SPX250117P05490000",
                 expiration_date: Date.new(2025, 1, 17), # Matching date
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 }),
          double("Option",
                 delta: -0.06,
                 open_interest: 25,
                 strike: 5480.0,
                 mark: 3.75,
                 symbol: "SPX250124P05480000",
                 expiration_date: Date.new(2025, 1, 24), # Non-matching date
                 bid: 5.45,
                 ask: 5.55,
                 respond_to?: lambda { |method|
                   %i[delta open_interest strike mark symbol expiration_date bid ask].include?(method)
                 })
        ]

        test_filter = described_class.new(
          expiration_date: expiration_date,
          underlying_price: underlying_price,
          max_delta: 0.15,
          max_spread: 20.0,
          min_credit: 1.0,
          min_open_interest: 10,
          dist_from_strike: 0.05
        )

        spreads = test_filter.find_spreads(mixed_date_options, "put")
        expect(spreads).not_to be_empty
        # Should only use the matching date options
        expect(spreads.length).to be >= 1
      end
    end
  end
end
