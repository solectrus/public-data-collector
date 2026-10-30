require 'env'
require 'providers/country'

module Providers
  module Eurostat
    # The settings of Eurostat, read from ENV.
    Settings =
      Data.define(:country) do
        def initialize(**)
          super

          Env.validate_presence!(country, 'COUNTRY')
        end

        # Eurostat asks for the country code in upper case, which is the
        # spelling the collector stores.
        def self.from_env
          new(country: Country.from_env)
        end
      end
  end
end
