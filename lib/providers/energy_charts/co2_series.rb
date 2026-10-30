require 'providers/energy_charts/client'
require 'providers/energy_charts/history'
require 'providers/series'

module Providers
  module EnergyCharts
    # Computes the CO2 that the German power mix emits per kWh.
    #
    # The API reports no CO2 value. The collector computes it from the net
    # generation of every source, which `/v2/total_power` reports per
    # quarter hour, and from emission factors of the Umweltbundesamt (UBA).
    # The result follows the definition of the "Emissionsfaktor Strommix" of
    # the UBA: the direct CO2 per kWh of consumption, without the emissions
    # upstream and without the trade balance.
    #
    # For 2015 to 2025, the yearly average differs from the value of the
    # UBA by 1.6 percent at most. The factors describe the power plants of
    # Germany, so the provider reads this series for Germany alone.
    class Co2Series < Series
      include History

      # Net generation per source, including the plants of the industry. The
      # UBA counts those plants as well. `/v2/public_power` leaves them out
      # and gives a mix that is 2 to 4 percent cleaner than the UBA value.
      PATH = '/v2/total_power'.freeze

      # Gram CO2 per kWh of net generation, for every source that burns
      # fuel. The UBA publishes the emissions per fuel and the energy per
      # fuel (Climate Change 16/2026, tables 6 and 7). Their ratio, related
      # to the energy that Energy-Charts reports for the same fuel, gave
      # these values for 2023, 2024 and 2025. They differ by 1 percent or
      # less between the years for coal and gas.
      #
      # The factor for waste is about half of the UBA value per kWh of
      # waste. The UBA counts the fossil part of waste alone, and
      # Energy-Charts reports all of it. Coal-derived gas comes from steel
      # works and goes with the other sources, as at the UBA.
      FACTORS = {
        'fossil_brown_coal_lignite' => 1100,
        'fossil_hard_coal' => 862,
        'fossil_gas' => 390,
        'fossil_oil' => 770,
        'waste' => 830,
        'others' => 1090,
        'fossil_coal_derived_gas' => 1090,
      }.freeze

      # Sources without direct CO2. The UBA counts biomass as zero, as the
      # reporting rules of the UNFCCC require.
      CLEAN = %w[
        nuclear biomass geothermal solar wind_onshore wind_offshore
        hydro_run_of_river hydro_water_reservoir hydro_pumped_storage
      ].freeze

      # A quarter hour counts only when these sources have a value. The
      # newest quarter hours of an answer have no values yet, and a mix
      # without some of its sources would be wrong. The other sources are
      # small or gone, for example nuclear since April 2023. Coal-derived gas
      # is missing in some years, for example 2021 and 2022. It is part of
      # `others` then, which has the same factor.
      REQUIRED = %w[
        fossil_brown_coal_lignite fossil_hard_coal fossil_gas fossil_oil waste others
        biomass solar wind_onshore wind_offshore hydro_run_of_river
      ].freeze

      # The energy that pumped storage plants take from the grid. The UBA
      # subtracts it from the consumption.
      PUMPING = 'hydro_pumped_storage_consumption'.freeze

      # The UBA divides by the consumption, which is the net generation less
      # the losses of the grid. In 2023, 2024 and 2025, the consumption was
      # 94.7 percent of the net generation that Energy-Charts reports, less
      # pumping. 2025 gave 94.4 percent, the other two years 94.9 percent.
      CONSUMPTION_SHARE = 0.947

      # Gram CO2 per kWh for one quarter hour
      Intensity = Data.define(:starts_at, :co2)

      def label = 'CO2 intensities'

      def measurement = MEASUREMENT
      def fields = { co2: 'co2_intensity' }

      # Yesterday and today. The last quarter hours of a day have values
      # about two hours after midnight, so the read after midnight still
      # needs yesterday.
      def records
        intensities(current_start, today)
      end

      private

      def current_start = today - 1

      def history_records(first, last) = intensities(first, last)

      def intensities(first, last)
        json = client.get(PATH, country: 'de', start: first.to_s, end: last.to_s)

        Array(json['data']).filter_map { |entry| build(entry) }
      end

      def build(entry)
        values = entry['values']
        return unless values.is_a?(Hash) && REQUIRED.all? { |id| values[id].is_a?(Numeric) }

        consumption = (generation(values) - pumping(values)) * CONSUMPTION_SHARE
        return unless consumption.positive?

        Intensity.new(Time.iso8601(entry.fetch('timestamp')), (emissions(values) / consumption).round)
      end

      # Megawatt times gram per kWh. The unit cancels in the division.
      def emissions(values)
        FACTORS.sum { |id, factor| power(values, id) * factor }
      end

      def generation(values)
        [*FACTORS.keys, *CLEAN].sum { |id| power(values, id) }
      end

      # The API reports the pumping as a negative power.
      def pumping(values)
        value = values[PUMPING]
        value.is_a?(Numeric) ? value.abs : 0
      end

      # A source that is missing or negative produces nothing.
      def power(values, id)
        value = values[id]
        value.is_a?(Numeric) ? [value, 0].max : 0
      end

      def client
        @client ||= Client.new
      end

      def nothing_found
        'no CO2 intensities in the answer'
      end

      def summary(intensities)
        "#{intensities.size} values"
      end
    end
  end
end
