require 'env'
require 'providers/base'

# Loads every provider. A provider is a folder below lib/providers whose
# provider.rb defines a subclass of Providers::Base, so a new folder is a
# new provider and nothing outside of it changes.
Dir[File.join(__dir__, 'providers', '*', 'provider.rb')].each do |file|
  require "providers/#{File.basename(File.dirname(file))}/provider"
end

module Providers
  # Every provider, built from ENV.
  #
  # Raises Env::Error when the interval is shorter than one of them allows.
  def self.from_env(config)
    providers = Base.all.map(&:from_env)
    validate_interval!(config.interval, providers)
    providers
  end

  # Every schedule names the shortest interval it accepts.
  def self.validate_interval!(interval, providers)
    minimum = providers.map { |provider| provider.schedule.minimum_interval }.max
    return if interval >= minimum

    raise Env::Error, "Interval is invalid: #{interval} (minimum is #{minimum})"
  end

  private_class_method :validate_interval!
end
