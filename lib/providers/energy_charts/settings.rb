require 'env'
require 'providers/country'

module Providers
  module EnergyCharts
    # The settings of Energy-Charts, read from ENV.
    Settings =
      Data.define(
        :bzn,
        :country,
        :measurement,
        :field_price,
        :field_share,
        :field_co2,
      ) do
        def initialize(**)
          super

          Env.validate_presence!(bzn, 'PUBLIC_GRID_BIDDING_ZONE')
          Env.validate_presence!(country, 'COUNTRY')
          Env.validate_presence!(measurement, 'PUBLIC_GRID_MEASUREMENT')
          Env.validate_presence!(field_price, 'PUBLIC_GRID_FIELD_PRICE')
          Env.validate_presence!(field_share, 'PUBLIC_GRID_FIELD_RENEWABLE_SHARE')
          Env.validate_presence!(field_co2, 'PUBLIC_GRID_FIELD_CO2_INTENSITY')
          validate_distinct_fields!
        end

        def self.from_env
          new(
            bzn: Env['PUBLIC_GRID_BIDDING_ZONE'] || 'DE-LU',
            country: Country.from_env,
            measurement: Env['PUBLIC_GRID_MEASUREMENT'] || 'PublicGrid',
            field_price: Env['PUBLIC_GRID_FIELD_PRICE'] || 'price',
            field_share: Env['PUBLIC_GRID_FIELD_RENEWABLE_SHARE'] || 'renewable_share',
            field_co2: Env['PUBLIC_GRID_FIELD_CO2_INTENSITY'] || 'co2_intensity',
          )
        end

        private

        # Every value goes to the same measurement and carries the same
        # timestamps. One field name for two values would therefore let one
        # value overwrite the other.
        def validate_distinct_fields!
          field_names.keys.combination(2) do |one, other|
            next unless public_send(one) == public_send(other)

            raise Env::Error,
                  "#{field_names[one]} and #{field_names[other]} are both #{public_send(one)}, they must differ"
          end
        end

        def field_names
          {
            field_price: 'PUBLIC_GRID_FIELD_PRICE',
            field_share: 'PUBLIC_GRID_FIELD_RENEWABLE_SHARE',
            field_co2: 'PUBLIC_GRID_FIELD_CO2_INTENSITY',
          }
        end
      end
  end
end
