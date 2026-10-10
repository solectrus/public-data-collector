require 'time'

require 'extent'
require 'influx_client'

# Reads from InfluxDB the one thing the collector needs to know: where the
# other data in the bucket begins.
#
# A series with a long history, for example the fuel prices back to 2005,
# writes nothing before that time. With an unlimited retention, InfluxDB
# keeps one shard per week that holds a point, and every shard costs
# memory and open files for good. A price of 2005 in a bucket whose data
# begins in 2020 therefore costs 15 years of shards that hold nothing
# else.
class FluxReader
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  # Where the other data begins, for the series with a history, and a
  # line on it in the log. Without other data, or without the permission
  # to read, it is `now`: such a series then writes its newest value
  # alone, and never a point before the data of the user.
  def history_start(except:, now:)
    oldest = oldest_time(except:)
    return note(now, 'The bucket holds no other data, so no history is written.') unless oldest

    start = [oldest.localtime, now].min
    note(start, "The other data in the bucket begins #{moment(start)}, so the history starts there.")
  rescue StandardError => e
    note(
      now,
      "Cannot find where the data in the bucket begins (#{e.message.lines.first&.strip}), " \
      'so no history is written. The token needs read permission for that.',
    )
  end

  # The time of the oldest point outside the given measurements, or nil
  # when there is none. Raises when InfluxDB refuses the query, for
  # example because the token has no read permission.
  def oldest_time(except:)
    tables = query_api.query(query: query(except), org: config.influx_org)

    tables.flat_map(&:records).map { |record| Time.iso8601(record.time) }.min
  end

  # What the bucket holds of the given fields, as {[measurement, field] =>
  # Extent}. A field without a point is left out. `before` is the start
  # of today. When InfluxDB refuses the query, the answer is empty, and a
  # series then reads its whole history.
  def extents(targets, before:)
    return {} if targets.empty?

    newest = times(targets, 'last()', stop: before)
    times(targets, 'first()').to_h do |target, oldest|
      [target, Extent.new(oldest:, newest: newest[target])]
    end
  rescue StandardError
    {}
  end

  private

  # The time of one point per field, as {[measurement, field] => time}
  def times(targets, selector, stop: nil)
    tables = query_api.query(query: extent_query(targets, selector, stop), org: config.influx_org)

    tables.flat_map(&:records).to_h { |record| [[record.measurement, record.field], Time.iso8601(record.time)] }
  end

  def extent_query(targets, selector, stop)
    filter = targets.map do |measurement, field|
      "(r._measurement == #{quote(measurement)} and r._field == #{quote(field)})"
    end

    <<~FLUX
      from(bucket: #{quote(config.influx_bucket)})
        |> range(start: 0#{", stop: #{stop.utc.iso8601}" if stop})
        |> filter(fn: (r) => #{filter.join(' or ')})
        |> #{selector}
        |> keep(columns: ["_measurement", "_field", "_time"])
    FLUX
  end

  def note(start, text)
    puts text
    puts
    start
  end

  def moment(time)
    "on #{time.strftime('%a %Y-%m-%d')} at #{time.strftime('%H:%M:%S')}"
  end

  # InfluxDB pushes `first` down to its storage, which then reads one block
  # per series and not every point. The filter compares every measurement
  # on its own, because the storage takes such a filter as well, but not
  # a `contains`.
  def query(except)
    filter = except.map { |measurement| "r._measurement != #{quote(measurement)}" }.join(' and ')

    <<~FLUX
      from(bucket: #{quote(config.influx_bucket)})
        |> range(start: 0)
        #{"|> filter(fn: (r) => #{filter})" unless filter.empty?}
        |> first()
        |> keep(columns: ["_time"])
        |> group()
        |> min(column: "_time")
    FLUX
  end

  # A Flux string literal. A measurement name comes from ENV, so a quote or
  # a backslash in it must not end the literal.
  def quote(text)
    %("#{text.to_s.gsub(/["\\]/) { "\\#{it}" }}")
  end

  def query_api
    @query_api ||= InfluxClient.build(config).create_query_api
  end
end
