require 'date'

require 'providers/fetch_error'

module Providers
  module EnergyCharts
    # The history of a value: the days before today, which the current
    # answer does not cover.
    #
    # The first read writes the history from where the other data in the
    # bucket begins. Every later read writes the current answer alone, as a
    # series without a history does. That answer covers today and tomorrow,
    # so the days before need no second write.
    #
    # The history arrives in requests of one year each, newest first. A year
    # of quarter hours is the largest answer the collector asks for: about
    # 20 MB for the renewable share, which the source sends together with
    # every kind of generation.
    #
    # A series that includes this module answers:
    #
    #   history_records(first, last)   the records of the days from `first`
    #                                  to `last`, both included (private)
    module History
      # An older request that the source answers with one of these has
      # reached the time before its data begins. The price answers 404, the
      # renewable share 400.
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
      def records_since(since)
        history(since.to_date, today - 1).sort_by(&:starts_at) + records
      end

      # The day of the loop clock, which is Time.now
      def today = Time.now.to_date

      # The newest request answers with an error only when something is
      # wrong, so that error stops the read. An older request that finds no
      # data ends the history.
      def history(first, last)
        records = []
        years(first, last).each_with_index do |(from, to), index|
          records.concat(history_records(from, to))
        rescue FetchError => e
          raise if index.zero? || !END_OF_DATA.include?(e.status)

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
