# When each provider reads next. Loop asks this class, and tells it how
# every read went.
#
# Every provider reads at the first cycle, so that a new container fills
# InfluxDB at once. After that, the schedule of a provider says whether it
# is due.
#
# A provider whose read fails tries again after one interval, whatever its
# schedule says. Every further failure doubles the wait, so a source that
# fails for good, for example because it does not know the country, costs
# little. The schedule still applies: a weekly provider always reads at
# its slot.
class Timetable
  # The failed reads of a provider in a row, and the time of the last one
  Failure =
    Data.define(:count, :at) do
      # One interval after the first failure, and twice as long after each
      # further one
      def retry_at(interval)
        at + (interval * (2**(count - 1)))
      end
    end

  def initialize(interval)
    @interval = interval
    @read_at = {}
    @failures = {}
  end

  attr_reader :interval

  # True until the provider had one read that reached InfluxDB.
  def first_read?(provider)
    !read_at.key?(provider)
  end

  # A provider that failed is due at its retry, or at the next slot of its
  # schedule after the failure, whichever comes first.
  def due?(provider, now)
    if (failure = failures[provider])
      return now >= failure.retry_at(interval) || provider.schedule.due?(now:, last_read: failure.at)
    end

    last_read = read_at[provider]
    last_read.nil? || provider.schedule.due?(now:, last_read:)
  end

  # The seconds until the provider needs the loop. A cycle can run past the
  # retry of a provider that failed before, so they never drop below zero.
  def wake_after(provider, now)
    seconds = provider.schedule.wake_after(interval, now:)
    failure = failures[provider]
    return seconds unless failure

    [seconds, (failure.retry_at(interval) - now).ceil].min.clamp(0..)
  end

  # `time` is the end of the read, not the start of the cycle. A read that
  # runs past a slot therefore does not make the provider due again.
  def succeeded(provider, time)
    read_at[provider] = time
    failures.delete(provider)
  end

  def failed(provider, time)
    failures[provider] = Failure.new(count: (failures[provider]&.count || 0) + 1, at: time)
  end

  private

  attr_reader :read_at, :failures
end
