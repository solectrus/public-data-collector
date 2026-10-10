require 'date'

require 'providers/fetch_error'

module Providers
  module EnergyCharts
    # The history of a value: the days before today, which the current
    # answer does not cover.
    #
    # The first read after a start writes the days that the bucket lacks
    # since the other data in the bucket begins. Every later read writes the
    # current answer alone, as a series without a history does. That answer
    # covers today and tomorrow, so the days before need no second write.
    #
    # The history arrives in requests of one year each, newest first. A year
    # of quarter hours is the largest answer the collector asks for: about
    # 20 MB for the renewable share, which the source sends together with
    # every kind of generation. A start therefore reads only what is
    # missing, and not the whole history again.
    #
    # A series that includes this module answers:
    #
    #   history_records(first, last)   the records of the days from `first`
    #                                  to `last`, both included (private)
    module History
      # A request that the source answers with one of these has reached the
      # time before its data begins. The price answers 404, the renewable
      # share 400. An error of the source shows at the request for today,
      # which the current answer makes.
      END_OF_DATA = [400, 404].freeze

      # The first read writes from `history_start` on. A start within today
      # needs no history, so the first read then writes the current answer
      # alone, as every later read does.
      def since(history_start, first_read:)
        history_start if first_read && history_start && history_start < today.to_time
      end

      private

      # The years arrive newest first. InfluxDB stores points in the order
      # of their time best, so the records go out sorted.
      def records_since(since, extents)
        days = missing(since, extents[targets.first])

        days.flat_map { |first, last| history(first, last) }.sort_by(&:starts_at) + records
      end

      # The day of the loop clock, which is Time.now
      def today = Time.now.to_date

      # The days before today that the bucket lacks, as [first, last] pairs.
      #
      # These are the days before its oldest point, and the days since its
      # newest point before today. Every cycle writes until the end of the
      # forecast, which is the end of tomorrow. The share of the day of the
      # last cycle is therefore partly a forecast, and the newest point lies
      # one day after it. The read starts one day before the newest point,
      # so the measurement replaces the forecast.
      def missing(since, stored)
        first = since.to_date
        yesterday = today - 1
        return [[first, yesterday]] unless stored

        days = []
        days << [first, [stored.oldest.to_date, yesterday].min] if since < stored.oldest
        days << [[first, stored.newest.to_date - 1].max, yesterday] if stored.newest
        merge(days)
      end

      # Pairs that overlap or touch become one, and an empty pair goes.
      def merge(days)
        days.select { |first, last| first <= last }.sort.each_with_object([]) do |(first, last), merged|
          if merged.any? && first <= merged.last.last + 1
            merged.last[1] = [merged.last.last, last].max
          else
            merged << [first, last]
          end
        end
      end

      # The days from `first` to `last`, newest year first. A year that
      # finds no data ends them.
      def history(first, last)
        records = []
        years(first, last).each do |from, to|
          records.concat(history_records(from, to))
        rescue FetchError => e
          raise unless END_OF_DATA.include?(e.status)

          break
        end
        records
      end

      # The days from `first` to `last` in years, newest first
      def years(first, last)
        Enumerator.new do |years|
          while last >= first
            from = [first, last.prev_year + 1].max
            years << [from, last]
            last = from - 1
          end
        end
      end
    end
  end
end
