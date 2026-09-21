require 'date'

module Providers
  # When a provider reads. Every provider answers one schedule, and
  # Timetable, Providers and main.rb ask the schedule instead of the
  # provider. None of
  # them knows the kinds of schedule, so a new kind changes this file
  # alone.
  #
  # Every provider reads at the first cycle, whatever its schedule says.
  # Timetable does that, so the schedule decides only about the cycles
  # after. Timetable also decides when a failed read tries again.
  #
  # A schedule answers these:
  #
  #   due?(now:, last_read:)     whether to read in this cycle. `last_read`
  #                              is the time of the last read.
  #   wake_after(interval, now:) the longest sleep of the loop in seconds
  #                              this schedule allows, with `INTERVAL` as
  #                              the setting of the user
  #   minimum_interval           the shortest `INTERVAL` it accepts
  #   description(interval)      its pace, for the banner
  module Schedule
    # Reads on every cycle, so `INTERVAL` sets the pace. The minimum is the
    # shortest cycle in seconds the source allows.
    EveryCycle =
      Data.define(:minimum_interval) do
        def initialize(minimum_interval: 1) = super

        def due?(**) = true
        def wake_after(interval, **) = interval

        def description(interval)
          "every #{interval} seconds"
        end
      end

    # Reads once a week, on its weekday (as Date#wday counts) at its full
    # hour, in local time, which `TZ` sets. `INTERVAL` does not apply: the
    # schedule wakes the loop at its hour, so it accepts any interval.
    Weekly =
      Data.define(:weekday, :hour) do
        # Due when the last read is older than the newest slot. A loop that
        # wakes late, for example after the host was suspended, still reads.
        def due?(now:, last_read:)
          last_read < last_slot(now)
        end

        # Rounded up, so the loop never wakes before the slot
        def wake_after(_interval, now:)
          (slot_on(last_slot(now).to_date + 7) - now).ceil
        end

        def minimum_interval = 0

        def description(_interval)
          format('on %<day>s at %<hour>02d:00', day: Date::DAYNAMES[weekday], hour:)
        end

        private

        # The newest slot at or before `now`
        def last_slot(now)
          date = now.to_date - ((now.wday - weekday) % 7)
          slot = slot_on(date)
          slot > now ? slot_on(date - 7) : slot
        end

        def slot_on(date)
          Time.local(date.year, date.month, date.day, hour)
        end
      end
  end
end
