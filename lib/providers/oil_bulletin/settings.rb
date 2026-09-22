require 'env'
require 'providers/country'

module Providers
  module OilBulletin
    # The settings of the oil bulletin, read from ENV.
    Settings =
      Data.define(:country, :measurement) do
        def initialize(**)
          super

          Env.validate_presence!(country, 'COUNTRY')
          Env.validate_presence!(measurement, 'FUEL_MEASUREMENT')
        end

        def self.from_env
          new(
            country: Country.from_env,
            measurement: Env['FUEL_MEASUREMENT'] || 'Fuel',
          )
        end
      end
  end
end
