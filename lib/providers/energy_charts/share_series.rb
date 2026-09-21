require 'providers/country'
require 'providers/energy_charts/client'
require 'providers/series'

module Providers
  module EnergyCharts
    # Reads the renewable share of the load for one country.
    #
    # The endpoint is called `signal`, because it also carries a traffic
    # light derived from the share. The collector does not read that light:
    # its thresholds are not published, they differ per country, and it can
    # hold the same value for days while the share moves by 50 percentage
    # points.
    class ShareSeries < Series
      PATH = '/v2/signal'.freeze

      # Id of the series that carries the share, as declared by the API.
      SERIES_ID = 'share'.freeze

      # The renewable share of the load in percent, for one quarter hour.
      # The value goes above 100 when the renewable sources produce more
      # than the country consumes.
      Share = Data.define(:starts_at, :share)

      def label = 'renewable shares'

      # The share goes to the measurement of the price, in a field of its
      # own. The user can rename that field, as with the price.
      def fields = { share: settings.field_share }

      # Shares from today until the end of the forecast. The API decides
      # how far the forecast reaches, so the collector asks for no time
      # range.
      def records
        # Energy-Charts asks for the ISO code in lower case.
        build(client.get(PATH, country: Country.iso(settings.country).downcase))
      end

      private

      def client
        @client ||= Client.new
      end

      def build(json)
        Client.series(json, SERIES_ID).map do |starts_at, share|
          Share.new(starts_at, share.to_f)
        end
      end

      def nothing_found
        'no shares in the answer'
      end

      def summary(shares)
        "#{shares.size} shares"
      end
    end
  end
end
