require 'providers/base'
require 'providers/eurostat/gas_price_series'
require 'providers/eurostat/settings'

module Providers
  # The dissemination API of Eurostat.
  # https://ec.europa.eu/eurostat/web/main/data/web-services
  #
  # Eurostat is the statistical office of the European Union. The API
  # needs no account and no key. It answers in JSON-stat, a format that
  # keeps the values in one flat list and the labels of every dimension
  # beside it. The collector reads one value of it: what households pay
  # for natural gas.
  #
  # The gas price gets a measurement of its own, because it carries its
  # own unit and its own pace.
  module Eurostat
    class Provider < Base
      # Eurostat publishes the gas price twice a year and the index once a
      # month, so a weekly read is enough. Any day would do. The provider
      # reads on Friday (5, as Date#wday counts) at 6 in the morning.
      WEEKDAY = 5
      HOUR = 6

      def self.from_env
        new(Settings.from_env)
      end

      def source = NAME
      def schedule = Schedule::Weekly.new(WEEKDAY, HOUR)

      private

      def series
        @series ||= [GasPriceSeries.new(settings)]
      end
    end
  end
end
