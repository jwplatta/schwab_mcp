# frozen_string_literal: true

require_relative "loggable"

module SchwabMCP
  class OptionChainFilter
    include Loggable

    attr_reader :expiration_date, :underlying_price, :expiration_type,
                :settlement_type, :option_root, :max_delta, :max_spread,
                :min_credit, :min_open_interest, :dist_from_strike, :quantity,
                :min_delta, :min_strike, :max_strike

    def initialize(
      expiration_date:,
      underlying_price: nil,
      expiration_type: nil,
      settlement_type: nil,
      option_root: nil,
      min_delta: 0.0,
      max_delta: 0.15,
      max_spread: 20.0,
      min_credit: 0.0,
      min_open_interest: 0,
      dist_from_strike: 0.0,
      quantity: 1,
      max_strike: nil,
      min_strike: nil
    )
      @expiration_date = expiration_date
      @underlying_price = underlying_price
      @expiration_type = expiration_type
      @settlement_type = settlement_type
      @option_root = option_root
      @max_spread = max_spread
      @min_credit = min_credit
      @min_open_interest = min_open_interest
      @dist_from_strike = dist_from_strike
      @quantity = quantity
      @max_delta = max_delta
      @min_delta = min_delta
      @max_strike = max_strike
      @min_strike = min_strike
    end

    def select(options_array)
      filtered_options = []
      exp_date_str = expiration_date.strftime("%Y-%m-%d")

      options_array.each do |option|
        next unless option_matches_date?(option, exp_date_str)
        next unless passes_delta_filter?(option)
        next unless passes_strike_range_filter?(option)

        filtered_options << option
      end

      log_debug("Found #{filtered_options.size} filtered options")
      filtered_options
    end

    def find_spreads(options_array, option_type)
      spreads = []
      exp_date_str = expiration_date.strftime("%Y-%m-%d")

      # Filter options for the target expiration date
      date_filtered_options = options_array.select { |opt| option_matches_date?(opt, exp_date_str) }
      log_debug("Processing #{date_filtered_options.size} options for date filter")

      short_cnt = 0

      date_filtered_options.each do |short_option|
        next unless passes_short_option_filters?(short_option)

        log_debug("Found short option: #{short_option.symbol} at strike #{short_option.strike}")

        short_cnt += 1

        long_options = find_long_option_candidates(date_filtered_options, short_option, option_type)

        long_options.each do |long_option|
          spread = build_spread(short_option, long_option)
          spreads << spread if spread
        end
      end

      log_debug("Found #{spreads.size} #{option_type} spreads for #{short_cnt} short options")

      spreads
    end

    def passes_short_option_filters?(option)
      return false unless passes_delta_filter?(option)
      return false unless passes_open_interest_filter?(option)
      return false unless passes_distance_filter?(option)
      return false unless passes_optional_filters?(option)

      true
    end

    private

    def option_matches_date?(option, exp_date_str)
      option.expiration_date.strftime("%Y-%m-%d") == exp_date_str
    end


    def passes_delta_filter?(option)
      delta = option.delta&.abs || 0.0
      delta <= max_delta && delta >= min_delta
    end

    def passes_open_interest_filter?(option)
      open_interest = option.open_interest || 0
      open_interest >= min_open_interest
    end

    def passes_distance_filter?(option)
      raise "Underlying price must be set for distance filter" unless underlying_price

      strike = option.strike
      return false unless strike

      distance = ((underlying_price - strike) / underlying_price).abs
      distance >= dist_from_strike
    end

    def passes_optional_filters?(option)
      return false if expiration_type && option.expiration_type != expiration_type
      return false if settlement_type && option.settlement_type != settlement_type
      return false if option_root && option.option_root != option_root

      true
    end

    def passes_strike_range_filter?(option)
      strike = option.strike
      return false unless strike

      return false if @min_strike && strike < @min_strike
      return false if @max_strike && strike > @max_strike

      true
    end

    def find_long_option_candidates(options_array, short_option, option_type)
      short_strike = short_option.strike
      candidates = []

      options_array.each do |long_option|
        long_strike = long_option.strike
        long_mark = long_option.mark

        next unless long_mark.positive?
        next unless valid_spread_structure?(short_strike, long_strike, option_type)
        next unless passes_min_credit?(short_option, long_option)
        next unless passes_optional_filters?(long_option)
        next unless passes_open_interest_filter?(long_option)

        candidates << long_option
      end

      candidates
    end

    def valid_spread_structure?(short_strike, long_strike, option_type)
      case option_type
      when "call"
        long_strike > short_strike && (long_strike - short_strike) <= max_spread

      when "put"
        long_strike < short_strike && (short_strike - long_strike) <= max_spread
      else
        false
      end
    end

    def passes_min_credit?(short_option, long_option)
      return true if min_credit <= 0

      short_mark = short_option.mark
      long_mark = long_option.mark
      credit = short_mark - long_mark

      credit * 100 >= min_credit
    end

    def build_spread(short_option, long_option)
      short_mark = short_option.mark
      long_mark = long_option.mark
      credit = short_mark - long_mark
      short_strike = short_option.strike
      long_strike = long_option.strike

      # Convert data objects to hash for compatibility with existing code
      short_hash = option_to_hash(short_option)
      long_hash = option_to_hash(long_option)

      {
        short_option: short_hash,
        long_option: long_hash,
        credit: credit,
        delta: short_option.delta || 0,
        spread_width: (short_strike - long_strike).abs,
        quantity: quantity
      }
    end

    def option_to_hash(option)
      {
        symbol: option.symbol,
        strikePrice: option.strike,
        mark: option.mark,
        bid: option.bid,
        ask: option.ask,
        delta: option.delta,
        openInterest: option.open_interest
      }
    end
  end
end
