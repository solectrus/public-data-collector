require 'providers/country'
require 'providers/energy_charts/client'
require 'providers/energy_charts/history'
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
      include History

      PATH = '/v2/signal'.freeze

      # Id of the series that carries the share, as declared by the API.
      SERIES_ID = 'share'.freeze

      # `signal` answers for today and the forecast alone. The days before
      # come from `public_power`, which carries the same share as a series
      # of its own, measured and not forecast. The two agree on every
      # quarter hour that is measured.
      HISTORY_PATH = '/v2/public_power'.freeze
      HISTORY_SERIES_ID = 'renewable_share_of_load'.freeze

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
        build(client.get(PATH, country:), SERIES_ID)
      end

      private

      # The answer carries every kind of generation as well, which makes a
      # year about 20 MB. The endpoint cannot leave them out.
      def history_records(first, last)
        build(client.get(HISTORY_PATH, country:, start: first.to_s, end: last.to_s), HISTORY_SERIES_ID)
      end

      # Energy-Charts asks for the ISO code in lower case.
      def country
        Country.iso(settings.country).downcase
      end

      def client
        @client ||= Client.new
      end

      def build(json, id)
        Client.series(json, id).map do |starts_at, share|
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
