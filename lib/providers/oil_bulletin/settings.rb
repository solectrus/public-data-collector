require 'env'
require 'providers/country'

module Providers
  module OilBulletin
    # The settings of the oil bulletin, read from ENV.
    Settings =
      Data.define(:country) do
        def initialize(**)
          super

          Env.validate_presence!(country, 'COUNTRY')
        end

        def self.from_env
          new(country: Country.from_env)
        end
      end
  end
end
