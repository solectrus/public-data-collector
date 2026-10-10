require 'influx_client'

# Writes the batches of the providers to InfluxDB.
#
# This class knows no provider. Every provider names its own measurement
# and fields in the batches it answers.
class FluxWriter
  # Seconds between two questions to InfluxDB at the start, while it boots.
  READY_RETRY_WAIT = 5

  # The most points in one request to InfluxDB
  POINTS_PER_WRITE = 5000

  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def ready?
    ok?(influx_client.ping)
  end

  # Asks InfluxDB until it answers, and reports whether it did. A
  # container of InfluxDB needs a moment after a start, and the collector
  # has nothing to write to until then.
  #
  # `max_wait` is the number of questions, not a number of seconds. Nil
  # waits for good. When InfluxDB stays silent, the log names the reason
  # of the last question, for example a host name that does not resolve.
  def ready_within?(max_wait)
    print 'Wait until InfluxDB is ready ...'

    waited = 0
    until ok?(ping = influx_client.ping) || (max_wait && waited >= max_wait)
      print '.'
      waited += 1
      sleep READY_RETRY_WAIT
    end

    if ok?(ping)
      puts ' OK'
      puts
      return true
    end

    reason = " (#{ping.message})" unless ping.message.to_s.empty?
    puts "\nInfluxDB not ready after #{waited * READY_RETRY_WAIT} seconds#{reason} - aborting."
    false
  end

  # A point that exists already is overwritten with the same value, so a
  # repeated write costs nothing and repairs the data after a gap.
  #
  # A history of quarter hours holds 35,000 points per year. InfluxDB
  # advises 5000 points per request, so a large batch takes several.
  def push(batch)
    points(batch).each_slice(POINTS_PER_WRITE) do |slice|
      write_api.write(data: slice, bucket: config.influx_bucket, org: config.influx_org)
    end
  end

  # InfluxDB stores a measurement as a table, one row per timestamp and one
  # column per field. It merges two points that share a measurement and a
  # timestamp, so two batches can fill two columns of the same rows.
  def points(batch)
    batch.rows.map do |row|
      InfluxDB2::Point.new(name: batch.measurement, time: row.time.to_i, fields: row.fields)
    end
  end

  private

  def ok?(ping)
    ping.status == 'ok'
  end

  def influx_client
    @influx_client ||= InfluxClient.build(config)
  end

  def write_api
    @write_api ||= influx_client.create_write_api
  end
end
