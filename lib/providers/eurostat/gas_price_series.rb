require 'date'

require 'providers/country'
require 'providers/eurostat/client'
require 'providers/eurostat/json_stat'
require 'providers/series'

module Providers
  module Eurostat
    # Reads what households pay for natural gas in one country.
    #
    # This is the price a gas heating costs its owner, which a market price
    # cannot answer. It carries every part of the bill: the energy, the grid
    # fee, the levies, the taxes and the standing charge.
    #
    # The standing charge is the reason to take this number and not an
    # advertised price per kWh. Eurostat reports an average price per kWh for
    # a whole consumption band, so the monthly charge is already spread over
    # the kWh of that band. A comparison that adds the charge again counts it
    # twice, and one that leaves it out makes gas look cheaper than it is.
    #
    # Two datasets build the answer, because one alone is either exact or
    # current, never both:
    #
    #   nrg_pc_202     the price itself, twice a year, about six months late
    #   prc_hicp_minr  how that price moved since, every month
    #
    # The collector writes every half year into each of its six months, and
    # carries the newest one forward with the index. That turns a value up
    # to fifteen months old into one about three weeks old.
    class GasPriceSeries < Series
      PRICE_DATASET = 'nrg_pc_202'.freeze

      # Band D2: 20 to 199 gigajoule a year, which is 5556 to 55556 kWh. That
      # covers the house that a heat pump heats. The smaller band D1 is for a
      # flat that cooks with gas, the larger D3 for an apartment building.
      CONSUMPTION_BAND = 'GJ20-199'.freeze

      # Level 3 of the three price levels: every tax and levy included, which
      # is what the owner pays.
      TAX_LEVEL = 'I_TAX'.freeze

      # Eurostat reports in euro or in the national currency. The collector
      # asks for euro, so that the number matches the euro prices of the
      # other sources.
      CURRENCY = 'EUR'.freeze

      # Eurostat reports a price per kWh already.
      UNIT = 'KWH'.freeze

      # The harmonised index of consumer prices, monthly. The dimension is
      # named coicop18 and not coicop, and the category is natural gas
      # through networks, which is gas from the grid and not a bottle.
      INDEX_DATASET = 'prc_hicp_minr'.freeze
      INDEX_CATEGORY = 'CP04521'.freeze
      INDEX_UNIT = 'I15'.freeze

      # One price for one period. `starts_at` is the first day of that period,
      # `amount` is the price in euro per kWh.
      Price = Data.define(:starts_at, :amount)

      # After the history, a read writes the last eighteen months. A new
      # half year arrives about six months after its end and replaces the
      # carried values of its six months, the oldest of them then about a
      # year old. The rest is a margin for a late publication.
      WINDOW = 548

      def label = 'gas prices'

      # The field name is fixed. There is no other collector whose field
      # this would have to match, so a setting for it would be ballast.
      def fields = { amount: 'price' }

      def window = WINDOW

      # One value per month: the measured price for every month of every
      # half year the dataset holds, and the carried price for every month
      # after the newest of them. The first read writes them from the start
      # of the history on, see Series#since.
      def records
        half_years = half_year_prices

        half_years.flat_map { |half_year| months_of(half_year) } + months_after(half_years.last)
      end

      private

      def client
        @client ||= Client.new
      end

      def half_year_prices
        JsonStat.series(client.get(PRICE_DATASET, **price_query)).filter_map do |period, amount|
          starts_at = half_year_start(period)
          starts_at && Price.new(starts_at, amount.to_f.round(5))
        end.sort_by(&:starts_at)
      end

      # The measured price holds for all six months of its half year. A
      # point for each month overwrites the carried points that earlier
      # reads wrote there, before Eurostat published that half year.
      def months_of(half_year)
        start = half_year.starts_at

        (0...6).map { |offset| Price.new(Time.new(start.year, start.month + offset, 1), half_year.amount) }
      end

      # Carries the newest half year forward, one point per month of the
      # index that follows it. The index of that half year is the average of
      # its own months, so the first carried month continues where the
      # measured price ends.
      #
      # A failed index request costs the carrying, not the prices, so it is
      # a warning and not an error.
      def months_after(anchor)
        return [] unless anchor

        index = index_series
        return [] if index.empty?

        base = average_index(index, anchor.starts_at)
        return [] unless base&.positive?

        index.filter_map do |month, value|
          next unless month > last_month_of(anchor.starts_at)

          Price.new(month, (anchor.amount * value / base).round(5))
        end
      end

      def index_series
        json = client.get(INDEX_DATASET, geo:, coicop18: INDEX_CATEGORY, unit: INDEX_UNIT)

        JsonStat.series(json).filter_map do |period, value|
          starts_at = month_start(period)
          starts_at && [starts_at, value.to_f]
        end.sort.to_h
      rescue FetchError => e
        puts "    ! #{e.message}, the newest gas price is not carried forward"
        {}
      end

      # The average index over the six months of one half year.
      def average_index(index, starts_at)
        months = index.select { |month, _| month.between?(starts_at, last_month_of(starts_at)) }.values
        return if months.empty?

        months.sum / months.size
      end

      def last_month_of(half_year_start)
        Time.new(half_year_start.year, half_year_start.month + 5, 1)
      end

      # Eurostat names a half year "2025-S1" or "2025-S2". S1 starts on the
      # first of January, S2 on the first of July.
      def half_year_start(period)
        year, half = period.to_s.split('-S')
        return unless %w[1 2].include?(half)

        year = Integer(year, 10, exception: false)
        year && Time.new(year, half == '1' ? 1 : 7, 1)
      end

      # A month reads "2026-08". The base 10 matters: without it, Integer
      # reads "08" and "09" as octal numbers and rejects them.
      def month_start(period)
        year, month = period.to_s.split('-')
        year = Integer(year.to_s, 10, exception: false)
        month = Integer(month.to_s, 10, exception: false)
        return unless year && month&.between?(1, 12)

        Time.new(year, month, 1)
      end

      # Eurostat follows the convention of the European Union, which writes
      # Greece as EL.
      def geo
        Country.eu(settings.country)
      end

      def price_query
        {
          geo:,
          nrg_cons: CONSUMPTION_BAND,
          tax: TAX_LEVEL,
          currency: CURRENCY,
          unit: UNIT,
        }
      end

      def nothing_found
        "no prices for country #{settings.country.inspect}"
      end

      def summary(prices)
        latest = prices.max_by(&:starts_at)

        "#{prices.size} values, latest #{(latest.amount * 100).round(2)} ct/kWh " \
          "for #{latest.starts_at.strftime('%Y-%m')}"
      end
    end
  end
end
