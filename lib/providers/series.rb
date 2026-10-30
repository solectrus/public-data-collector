require 'batch'
require 'providers/fetch_error'

module Providers
  # One value a provider reads, written to one measurement.
  #
  # A series is a part of its provider and never seen from outside. It
  # turns its records into a Batch, so the writer needs no knowledge of
  # the records. A subclass answers these:
  #
  #   label              names the records in the log
  #   measurement        the measurement the records go to
  #   fields             record accessor => field name
  #   records            the records. It raises FetchError when the
  #                      source failed.
  #   nothing_found      why there is nothing to write
  #   summary(records)   what arrived, in a few words
  #
  # and may answer these:
  #
  #   subject            what the log says this series is fetching
  #   window             for a series with a history: the days a read
  #                      covers once the history is written, see `since`
  #   since(...)         for a series with a history that a window cannot
  #                      describe: the time from which a read writes
  #   records_since(time, extents)
  #                      for a source that takes a time range: the records
  #                      from `time` on (private). `extents` tells what the
  #                      bucket holds already, see Extent. The default
  #                      reads every record, and `fetch` drops the older
  #                      ones.
  #
  # Every record answers `starts_at` and one accessor per field.
  class Series
    SECONDS_PER_DAY = 86_400

    def initialize(settings)
      @settings = settings
    end

    attr_reader :settings

    def subject
      "#{label} for #{settings.country}"
    end

    # Nil for a series that writes everything it reads, for example the
    # prices of today and tomorrow.
    def window = nil

    # The fields this series fills, as [measurement, field].
    def targets
      fields.values.map { |field| [measurement, field] }
    end

    # The time from which a read writes, or nil for everything.
    #
    # The first read writes the history from `history_start` on, where the
    # other data in the bucket begins. Every later read writes the window
    # alone, so a weekly read does not touch every shard of the history
    # again. Nil for a series without a window, or without a start.
    def since(history_start, first_read:)
      return unless window && history_start
      return history_start if first_read

      [history_start, Time.now - (window * SECONDS_PER_DAY)].max
    end

    # The records from `since` on as a Batch, and a few words on what
    # arrived. Raises FetchError when the source failed or delivered
    # nothing. `extents` is what the bucket holds already, as
    # {[measurement, field] => Extent}.
    def fetch(since = nil, extents: {})
      records = since ? records_since(since, extents) : self.records
      raise FetchError, nothing_found if records.empty?
      return [batch(records), summary(records)] unless since

      records = from(records, since)
      [batch(records), "#{summary(records)} (from #{records.map(&:starts_at).min.strftime('%Y-%m-%d')})"]
    end

    private

    def records_since(_since, _extents) = records

    # The records from `since` on, and the newest one before it. That one
    # holds the value that applies at `since`, for example the price of
    # the week in which the data of the bucket begins.
    def from(records, since)
      before, after = records.partition { |record| record.starts_at < since }

      [before.max_by(&:starts_at), *after].compact
    end

    def batch(records)
      Batch.new(measurement:, rows: rows(records))
    end

    # A record without a single value gives no row.
    def rows(records)
      records.filter_map do |record|
        values = values_of(record)

        Batch::Row.new(time: record.starts_at, fields: values) unless values.empty?
      end
    end

    def values_of(record)
      fields.filter_map do |accessor, name|
        value = record.public_send(accessor)

        [name, value] unless value.nil?
      end.to_h
    end
  end
end
