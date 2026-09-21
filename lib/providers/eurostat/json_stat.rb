module Providers
  module Eurostat
    # Reads the JSON-stat format that Eurostat answers with.
    #
    # JSON-stat keeps the values in a flat list, keyed by the position in a
    # grid of all dimensions. This module knows that format, not the
    # meaning of any dataset.
    module JsonStat
      # Every period of an answer with its value, as [period, value] pairs.
      # The period is the label Eurostat uses, for example "2025-S2" or
      # "2026-08".
      #
      # The caller asks for one country and one category, so every dimension
      # but the time has one member and the position in the list is the index
      # of the period. A dimension with more members would break that, so
      # this checks it instead of assuming it.
      def self.series(json)
        return [] unless single_series?(json)

        periods = json.dig('dimension', 'time', 'category', 'index') || {}
        values = json['value'] || {}

        periods.filter_map do |period, index|
          value = values[index.to_s]
          [period, value] if value.is_a?(Numeric)
        end
      end

      def self.single_series?(json)
        sizes = json['size']
        dimensions = json['id']
        return false unless sizes.is_a?(Array) && dimensions.is_a?(Array)

        sizes.zip(dimensions).all? { |size, name| name == 'time' || size == 1 }
      end

      private_class_method :single_series?
    end
  end
end
