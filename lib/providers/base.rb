require 'providers/result'
require 'providers/schedule'
require 'providers/series'

module Providers
  # Base class of the providers. A provider reads one remote source.
  #
  # From outside every provider looks the same: `from_env` builds it,
  # and `call` yields what each series delivered. What it reads and how
  # is its own business. A provider that reads several values keeps them
  # in series of its own, and nothing outside the provider sees them.
  #
  # A subclass answers these:
  #
  #   self.from_env      the provider, with its settings read from ENV
  #   source             the name of the remote source, for the log
  #   series             the series it reads (private)
  #
  # and may answer this:
  #
  #   schedule           when it reads, see Providers::Schedule. The
  #                      default reads on every cycle.
  class Base
    class << self
      # Every provider a `require` has loaded, in the order it loaded them.
      # Ask this of Base, never of a subclass.
      def all
        @all ||= []
      end

      def inherited(subclass)
        super
        Base.all << subclass
      end
    end

    def initialize(settings)
      @settings = settings
    end

    attr_reader :settings

    def schedule = Schedule::EveryCycle.new

    # Reads one series after the other and yields a Result for each. A
    # series that fails yields its reason, so it does not stop the others
    # nor the collector. Without a block it answers an Enumerator.
    #
    # `history_start` and `first_read` tell a series with a history how far
    # back to write, see Series#since. Without them, it writes everything.
    def call(history_start: nil, first_read: true)
      return enum_for(:call, history_start:, first_read:) unless block_given?

      series.each { |one| yield read(one, one.since(history_start, first_read:)) }
    end

    # One line per series for the banner: what it reads, where it reads it,
    # and which sensors it fills.
    def descriptions
      series.map { |one| "#{one.subject} from #{source} => #{one.sensors.join(', ')}" }
    end

    # The measurements this provider writes to.
    def measurements
      series.map(&:measurement).uniq
    end

    private

    def read(one, since)
      batch, summary = one.fetch(since)
      Result.new(subject: one.subject, batch:, summary:)
    rescue FetchError => e
      Result.new(subject: one.subject, error: e.message)
    rescue StandardError => e
      # An answer in a shape the series does not expect, for example JSON
      # without the expected keys. The class names the problem better than
      # the message alone.
      Result.new(subject: one.subject, error: "unexpected answer (#{e.class}: #{e.message})")
    end
  end
end
