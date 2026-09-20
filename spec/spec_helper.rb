require 'simplecov'
SimpleCov.start do
  skip '/spec/'

  # The collector is small enough to keep every line covered
  minimum_coverage 100
end

require 'bundler/setup'

require 'dotenv'
Dotenv.load('.env.test.local', '.env.test')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
Dir[File.join(__dir__, 'support/**/*.rb')].each { |f| require f }

require 'webmock/rspec'
require 'climate_control'

# Silence deprecation warnings caused by the `influxdb-client` gem
Warning[:deprecated] = false

RSpec.configure do |config|
  config.expect_with(:rspec) { |e| e.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed
end
