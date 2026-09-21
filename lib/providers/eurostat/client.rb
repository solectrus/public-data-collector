require 'uri'

require 'providers/json_api'

module Providers
  module Eurostat
    NAME = 'Eurostat'.freeze

    # One request asks for one dataset.
    class Client < JsonApi
      BASE_URL = 'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data'.freeze

      private

      def source
        NAME
      end

      def uri(dataset, **params)
        URI("#{BASE_URL}/#{dataset}?#{URI.encode_www_form(params.merge(format: 'JSON', lang: 'EN'))}")
      end
    end
  end
end
