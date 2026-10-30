require 'env'
require 'providers/country'

module Providers
  module EnergyCharts
    # The bidding zone of a country.
    #
    # Most countries have one zone that carries their own code. Germany and
    # Luxembourg share one, and Ireland has one with Northern Ireland.
    # Denmark, Italy, Norway and Sweden have more than one zone, so the user
    # must name it there.
    module BiddingZone
      # Countries whose zone carries the code of the country
      OWN = %w[AT BE BG CH CZ EE ES FI FR GR HR HU LT LV ME NL PL PT RO RS SI SK].freeze

      # Countries that share a zone, or whose zone has another code
      SHARED = { 'DE' => 'DE-LU', 'LU' => 'DE-LU', 'IE' => 'IE(SEM)' }.freeze

      # The zone, or nil for a country with more than one zone or without a
      # zone at Energy-Charts
      def self.of(country)
        iso = Country.iso(country)

        SHARED.fetch(iso) { iso if OWN.include?(iso) }
      end
    end

    # The settings of Energy-Charts, read from ENV.
    Settings =
      Data.define(:country, :bzn) do
        def initialize(**)
          super

          Env.validate_presence!(country, 'COUNTRY')
          return unless bzn.to_s.strip.empty?

          raise Env::Error, "BIDDING_ZONE is missing, because COUNTRY #{country} has no single bidding zone"
        end

        def self.from_env
          country = Country.from_env

          new(country:, bzn: Env['BIDDING_ZONE'] || BiddingZone.of(country))
        end
      end
  end
end
