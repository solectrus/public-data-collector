require 'date'

require 'flux_reader'
require 'flux_writer'
require 'providers'
require 'timetable'

# The cycle of the collector.
#
# This class names no provider and no kind of schedule. It calls every
# provider it is given in the same way, and pushes the batches that come
# back. Timetable says which provider is due, and how long the loop may
# sleep. The interval is a setting, `INTERVAL`, and one hour by default.
#
# At the start, the loop asks InfluxDB where the other data in the bucket
# begins. A series with a history writes from there on at its first read,
# and a short window after that, see Providers::Series#since.
class Loop
  # A write to InfluxDB can time out when the host is busy, and InfluxDB
  # itself can restart. The collector must not stop for that, so it repeats
  # the push before it gives up.
  PUSH_ATTEMPTS = 5

  # Seconds before the second attempt. Every further attempt waits twice as
  # long, which gives 5, 10, 20 and 40 seconds, or 75 seconds in total. That
  # is long enough for a restart of InfluxDB.
  PUSH_RETRY_WAIT = 5

  # Questions to InfluxDB at the start before the collector gives up. With
  # FluxWriter::READY_RETRY_WAIT between two of them, that is one minute.
  READY_ATTEMPTS = 12

  # InfluxDB did not answer within READY_ATTEMPTS. FluxWriter has printed
  # the reason already, so main.rb only stops.
  class NotReady < StandardError; end

  def self.start(config:, max_count: nil, max_wait: READY_ATTEMPTS, **)
    new(config:, **).start(max_count:, max_wait:)
  end

  # The providers, the reader and the writer are built from the config
  # unless the caller hands them in, so main.rb and the loop can share one
  # of each.
  def initialize(
    config:,
    providers: Providers.from_env(config),
    flux_reader: FluxReader.new(config:),
    flux_writer: FluxWriter.new(config:)
  )
    @config = config
    @providers = providers
    @flux_reader = flux_reader
    @flux_writer = flux_writer
    @timetable = Timetable.new(config.interval)
  end

  attr_reader :config, :providers, :flux_reader, :flux_writer

  # Runs the cycles, and raises NotReady at once when InfluxDB does not
  # answer. Without `max_count` it runs for good.
  def start(max_count: nil, max_wait: READY_ATTEMPTS)
    raise NotReady unless flux_writer.ready_within?(max_wait)

    @history_start = flux_reader.history_start(except: providers.flat_map(&:measurements).uniq, now: Time.now)

    1.step do |count|
      now = Time.now
      puts "Cycle ##{count} at #{now.strftime('%Y-%m-%d %H:%M:%S %z')}"
      cycle(now)

      break if max_count && count >= max_count

      seconds = interval(Time.now)
      puts "  Next cycle #{moment(Time.now + seconds)}"
      sleep seconds
      puts
    end
  end

  private

  attr_reader :timetable, :history_start

  # One provider that fails does not stop the others. Every provider
  # carries timestamps that a later read writes again, so the next read
  # repairs the data of a failed one.
  #
  # A read counts only when every series of the provider reached InfluxDB.
  def cycle(now)
    due = providers.select { |provider| timetable.due?(provider, now) }
    return puts '  Nothing to do, no source is due.' if due.empty?

    due.each do |provider|
      puts "  #{provider.source}"
      first_read = timetable.first_read?(provider)
      results = provider.call(history_start:, first_read:, extents: first_read ? extents(provider) : {})
      errors = results.filter_map { |result| report(result) }
      finished(provider, errors.empty?, Time.now)
    end
  end

  # What the bucket holds of the fields of a provider, for its first read.
  # A series with a history then reads only the days that are missing.
  def extents(provider)
    flux_reader.extents(provider.targets, before: Time.now.to_date.to_time)
  end

  def finished(provider, success, time)
    return timetable.succeeded(provider, time) if success

    timetable.failed(provider, time)
    puts "    Next attempt #{moment(time + timetable.wake_after(provider, time))}"
  end

  # One line per series: a check mark when its batch reached InfluxDB, a
  # cross when the read or the push failed. A warning of the provider comes
  # before the line, so it never splits it. Answers nil when the batch
  # reached InfluxDB, else the reason.
  def report(result)
    return failure(result.subject, result.error) unless result.ok?

    error = push(result.batch)
    return failure(result.subject, "#{result.summary}, but not stored in InfluxDB (#{error})") if error

    line('✓', result.subject, result.summary)
    nil
  end

  def failure(subject, reason)
    line('✗', subject, reason)
    reason
  end

  def line(mark, subject, text)
    puts "    #{mark} #{subject}: #{text}"
  end

  # The time of day when it is today, else the day as well
  def moment(time)
    return "at #{time.strftime('%H:%M:%S')}" if time.to_date == Time.now.to_date

    "on #{time.strftime('%a %Y-%m-%d')} at #{time.strftime('%H:%M:%S')}"
  end

  # The loop wakes up when the first provider needs it.
  def interval(now)
    providers.map { |provider| timetable.wake_after(provider, now) }.min
  end

  # Answers nil when the push worked, else the reason of the last attempt.
  # A failed push never stops the collector. The next read writes the same
  # points again, so a push that fails for good costs data only until then.
  def push(batch)
    attempt = 0

    begin
      attempt += 1
      flux_writer.push(batch)
      nil
    rescue StandardError => e
      return "#{e.message}, #{PUSH_ATTEMPTS} attempts" if attempt >= PUSH_ATTEMPTS

      wait = PUSH_RETRY_WAIT * (2**(attempt - 1))
      puts "    ! InfluxDB: #{e.message}, next attempt in #{wait} seconds"
      sleep wait
      retry
    end
  end
end
