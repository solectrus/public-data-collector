require 'providers/base'
require 'providers/energy_charts/price_series'
require 'providers/energy_charts/settings'
require 'providers/energy_charts/share_series'

module Providers
  # The Energy-Charts API of Fraunhofer ISE.
  # https://api.energy-charts.info/
  #
  # It reports the electricity market of more than 50 bidding zones in
  # Europe, and it needs no account and no key. The collector reads two
  # values of it: the day-ahead price and the renewable share.
  #
  # Both values go to one measurement, in two fields. They carry the same
  # quarter hour timestamps, so they fill two columns of the same rows.
  module EnergyCharts
    class Provider < Base
      # The price endpoint accepts 2 requests per minute, which is the
      # lowest limit of every source this collector reads. One cycle makes
      # one request per endpoint, so this minimum keeps the collector below
      # the limit.
      MINIMUM_INTERVAL = 60

      def self.from_env
        new(Settings.from_env)
      end

      def source = NAME
      def schedule = Schedule::EveryCycle.new(minimum_interval: MINIMUM_INTERVAL)

      private

      def series
        @series ||= [
          PriceSeries.new(settings),
          ShareSeries.new(settings)
        ]
      end
    end
  end
end
