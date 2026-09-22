require 'providers/base'
require 'providers/oil_bulletin/fuel_price_series'
require 'providers/oil_bulletin/settings'

module Providers
  # The price history of the Weekly Oil Bulletin.
  # https://energy.ec.europa.eu/data-and-analysis/weekly-oil-bulletin_en
  #
  # The European Commission collects the consumer prices of petroleum
  # products from every member state and publishes them once a week. The
  # file needs no account and no key. It reaches back to 2005, which is why
  # this collector reads it instead of a live price service: those know
  # today and nothing else.
  #
  # The fuel prices get a measurement of their own, because they carry
  # their own unit and their own pace.
  module OilBulletin
    class Provider < Base
      # The European Commission surveys the prices of every Monday, saves
      # the file on the Wednesday after, and announces it on the Thursday.
      # A read on Friday (5, as Date#wday counts) therefore finds the newest
      # week and keeps two days of margin for a late upload. At 6 in the
      # morning, the prices are there before the day starts.
      WEEKDAY = 5
      HOUR = 6

      def self.from_env
        new(Settings.from_env)
      end

      def source = NAME
      def schedule = Schedule::Weekly.new(WEEKDAY, HOUR)

      private

      def series
        @series ||= [FuelPriceSeries.new(settings)]
      end
    end
  end
end
