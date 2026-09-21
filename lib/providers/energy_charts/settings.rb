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
      ) do
        def initialize(**)
          super

          Env.validate_presence!(bzn, 'PUBLIC_GRID_BIDDING_ZONE')
          Env.validate_presence!(country, 'COUNTRY')
          Env.validate_presence!(measurement, 'PUBLIC_GRID_MEASUREMENT')
          Env.validate_presence!(field_price, 'PUBLIC_GRID_FIELD_PRICE')
          Env.validate_presence!(field_share, 'PUBLIC_GRID_FIELD_RENEWABLE_SHARE')
          validate_distinct_fields!
        end

        def self.from_env
          new(
            bzn: Env['PUBLIC_GRID_BIDDING_ZONE'] || 'DE-LU',
            country: Country.from_env,
            measurement: Env['PUBLIC_GRID_MEASUREMENT'] || 'PublicGrid',
            field_price: Env['PUBLIC_GRID_FIELD_PRICE'] || 'price',
            field_share: Env['PUBLIC_GRID_FIELD_RENEWABLE_SHARE'] || 'renewable_share',
          )
        end

        private

        # Price and share go to the same measurement and carry the same
        # timestamps. One field name for both would therefore let one value
        # overwrite the other.
        def validate_distinct_fields!
          return unless field_price == field_share

          raise Env::Error,
                'PUBLIC_GRID_FIELD_PRICE and PUBLIC_GRID_FIELD_RENEWABLE_SHARE ' \
                "are both #{field_price}, they must differ"
        end
      end
  end
end
