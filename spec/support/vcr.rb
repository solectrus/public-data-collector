require 'vcr'
require 'webmock'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock

  sensitive_environment_variables = %w[INFLUX_HOST INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET]
  sensitive_environment_variables.each do |key_name|
    config.filter_sensitive_data("<#{key_name}>") { ENV.fetch(key_name, nil) }
  end

  record_mode = ENV['VCR'] ? ENV['VCR'].to_sym : :once
  config.default_cassette_options = {
    record: record_mode,
    allow_playback_repeats: true,
    decode_compressed_response: true,
    serialize_with: :yaml,
    # The request carries the current date, which moves every day. Matching
    # on the method and the path alone keeps the cassettes usable.
    match_requests_on: %i[method host path],
  }

  config.before_record { |interaction| interaction.response.body.force_encoding('UTF-8') }
end
