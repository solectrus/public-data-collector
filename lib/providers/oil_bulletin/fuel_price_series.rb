require 'providers/oil_bulletin/client'
require 'providers/series'

module Providers
  module OilBulletin
    # Reads what a litre of fuel costs in one country.
    #
    # The prices are national averages with every tax included, as the
    # member states report them to the European Commission. They answer what
    # a year of driving or heating costs, not where to fill up today.
    class FuelPriceSeries < Series
      # The field names are fixed. Every field names the measured quantity,
      # so a later version can add a second quantity of the same product,
      # for example the number of open stations.
      FIELDS = {
        petrol: 'price_petrol',
        diesel: 'price_diesel',
        heating_oil: 'price_heating_oil',
        lpg: 'price_lpg',
      }.freeze

      # The products of the bulletin this collector keeps, and the name each
      # one carries in InfluxDB. The bulletin also reports two heavy fuel
      # oils, which power ships and industry and have no place in a house.
      #
      # The bulletin knows one petrol, Euro-super 95. It does not separate
      # E5 from E10, so neither does this collector.
      PRODUCTS = {
        'euro95' => :petrol,
        'diesel' => :diesel,
        'heating_oil' => :heating_oil,
        'LPG' => :lpg,
      }.freeze

      # The bulletin quotes a price per 1000 litres. SOLECTRUS stores a price
      # per litre.
      LITRES = 1000.0

      # Prices in euro per litre for one week. `starts_at` is the day the
      # prices were collected. A product without a price is nil, which
      # happens where a country does not report one.
      Prices = Data.define(:starts_at, :petrol, :diesel, :heating_oil, :lpg)

      # After the history, a read writes the last eight weeks. They repeat
      # the newest weeks in case the Commission corrects one. A correction
      # of an older week arrives with the history at the next start.
      WINDOW = 8 * 7

      def label = 'fuel prices'

      def measurement = MEASUREMENT
      def fields = FIELDS

      def window = WINDOW

      # One entry per week, back to 2005. The first read writes them from
      # the start of the history on, see Series#since.
      def records
        Client.new(country: settings.country).weeks.filter_map { |week| build(week) }
      end

      private

      def build(week)
        amounts = PRODUCTS.to_h do |product, name|
          [name, amount(week.prices[product])]
        end
        return if amounts.values.all?(&:nil?)

        Prices.new(starts_at: week.date.to_time, **amounts)
      end

      # Fuel prices carry three decimals, the third being the famous nine.
      def amount(value)
        return unless value.is_a?(Numeric)

        (value / LITRES).round(3)
      end

      def nothing_found
        "no prices for country #{settings.country.inspect}"
      end

      def summary(prices)
        latest = prices.max_by(&:starts_at)

        "#{prices.size} weeks, latest #{latest.starts_at.strftime('%Y-%m-%d')}: " \
          "petrol #{latest.petrol || '-'}, diesel #{latest.diesel || '-'} EUR/l"
      end
    end
  end
end
