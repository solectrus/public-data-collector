require 'time'
require 'uri'

require 'providers/json_api'

module Providers
  module EnergyCharts
    NAME = 'Energy-Charts'.freeze

    # Every endpoint answers with the same envelope: a `data` array of
    # entries, each with a `timestamp` and a `values` hash keyed by the
    # series ids that `series` declares. This class knows the envelope,
    # not the meaning of a series. A series class reads the ids it needs.
    class Client < JsonApi
      BASE_URL = 'https://api.energy-charts.info'.freeze

      # Seconds between two requests to the same endpoint. The API limits
      # the requests per endpoint, and most endpoints allow 2 per minute. A
      # cycle makes one request per endpoint, so this matters only for the
      # history, which makes one request per year.
      SPACING = 31

      # The timestamp and the value of one series id for every entry of an
      # envelope. An entry without a numeric value is left out.
      def self.series(json, id)
        Array(json['data']).filter_map do |entry|
          values = entry['values']
          value = values[id] if values.is_a?(Hash)
          next unless value.is_a?(Numeric)

          [Time.iso8601(entry.fetch('timestamp')), value]
        end
      end

      # Waits until the endpoint accepts the next request.
      def get(path, **)
        pause(path)
        super
      ensure
        requested_at[path] = Time.now
      end

      private

      def requested_at
        @requested_at ||= {}
      end

      def pause(path)
        return unless (last = requested_at[path])

        seconds = last + SPACING - Time.now
        sleep(seconds) if seconds.positive?
      end

      def source
        NAME
      end

      def uri(path, **params)
        URI("#{BASE_URL}#{path}?#{URI.encode_www_form(params)}")
      end
    end
  end
end
