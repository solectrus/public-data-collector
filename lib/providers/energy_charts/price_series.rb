require 'providers/energy_charts/client'
require 'providers/energy_charts/history'
require 'providers/series'

module Providers
  module EnergyCharts
    # Reads the day-ahead spot market price for one bidding zone.
    class PriceSeries < Series
      include History

      PATH = '/v2/price'.freeze

      # Id of the series that carries the price, as declared by the API.
      SERIES_ID = 'day_ahead_price'.freeze

      # The API quotes the price per megawatt hour. SOLECTRUS stores a
      # price per kilowatt hour, so every value is divided by this factor.
      KWH_PER_MWH = 1000.0

      # One price for one quarter hour. `starts_at` is the start of the
      # interval, `amount` is the price in the currency of the bidding
      # zone, per kWh.
      Price = Data.define(:starts_at, :amount)

      def label = 'day-ahead prices'

      # The day-ahead price asks for a bidding zone, not for a country.
      def subject
        "#{label} for #{settings.bzn}"
      end

      def measurement = MEASUREMENT
      def fields = { amount: 'price' }

      # Prices for today and tomorrow.
      #
      # Tomorrow is part of the answer only after the day-ahead auction is
      # cleared, which happens in the early afternoon. Before that the API
      # returns today alone, which is not an error.
      def records
        prices(today, today + 1)
      end

      private

      # The same endpoint answers for every day it knows. Before October
      # 2025, the auction priced every hour, so the history has one price
      # per hour until then.
      def history_records(first, last) = prices(first, last)

      def prices(first, last)
        json = client.get(PATH, bzn: settings.bzn, start: first.to_s, end: last.to_s)
        check_unit!(json['unit'])

        build(json)
      end

      def client
        @client ||= Client.new
      end

      def build(json)
        Client.series(json, SERIES_ID).map do |starts_at, amount|
          Price.new(starts_at, (amount / KWH_PER_MWH).round(5))
        end
      end

      def nothing_found
        'no prices in the answer'
      end

      def summary(prices)
        "#{prices.size} prices"
      end

      # The currency can differ per bidding zone, and the collector passes
      # it through unchanged. The energy unit must not differ, because the
      # division by 1000 depends on it.
      def check_unit!(unit)
        return if unit.to_s.delete(' ').downcase.end_with?('/mwh')

        raise FetchError, "unexpected unit #{unit.inspect}, expected a price per MWh"
      end
    end
  end
end
