require 'env'
require 'providers/country'

module Providers
  module Eurostat
    # The settings of Eurostat, read from ENV.
    Settings =
      Data.define(:country, :measurement) do
        def initialize(**)
          super

          Env.validate_presence!(country, 'COUNTRY')
          Env.validate_presence!(measurement, 'GAS_MEASUREMENT')
        end

        # Eurostat asks for the country code in upper case, which is the
        # spelling the collector stores.
        def self.from_env
          new(
            country: Country.from_env,
            measurement: Env['GAS_MEASUREMENT'] || 'Gas',
          )
        end
      end
  end
end
