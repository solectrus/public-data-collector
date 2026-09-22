#!/usr/bin/env ruby

# Add lib directory to load path so we can use simple require statements
$LOAD_PATH.unshift(__dir__)

require 'dotenv/load'
require 'app_version'
require 'config'
require 'loop'
require 'providers'

# Flush output immediately
$stdout.sync = true

puts 'Public-data collector for SOLECTRUS, ' \
       "Version #{AppVersion.current || '<unknown>'}, " \
       "built at #{ENV.fetch('BUILDTIME', '<unknown>')}"
puts 'https://github.com/solectrus/public-data-collector'
puts 'Copyright (c) 2026 Georg Ledermann, released under the MIT License'
puts "\n"

begin
  config = Config.from_env
  providers = Providers.from_env(config)
rescue Env::Error => e
  puts "Error: #{e.message}"
  exit(1)
end

puts "Using Ruby #{RUBY_VERSION} on platform #{RUBY_PLATFORM}"
puts "Pushing to InfluxDB at #{config.influx_url}, bucket #{config.influx_bucket}"

# The providers by their pace, one line per value they read. Every provider
# reads at the start, see Loop.
providers.group_by { |provider| provider.schedule.description(config.interval) }.each do |pace, group|
  puts "Reading at start, then #{pace}:"
  group.flat_map(&:descriptions).each { |line| puts "  #{line}" }
end

puts "\n"

begin
  Loop.start(config:, providers:)
rescue Loop::NotReady
  exit(1)
end
