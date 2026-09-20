# Reads settings out of ENV. Config and the settings of every provider use
# this module, so a blank value means the same everywhere.
module Env
  # A setting that is missing or makes no sense. The collector cannot start
  # with it, so main.rb prints the message and stops.
  class Error < StandardError; end

  # The value of a key, or nil. A blank value counts as unset, so an empty
  # line in the compose file does not overwrite a default.
  def self.[](key)
    value = ENV.fetch(key, '').strip
    value.empty? ? nil : value
  end

  # The value of a key the collector cannot run without.
  def self.fetch(key)
    self[key] || raise(Error, "#{key} is missing")
  end

  # Raises when a setting has no value.
  def self.validate_presence!(value, key)
    return unless value.to_s.strip.empty?

    raise Error, "#{key} is missing"
  end
end
